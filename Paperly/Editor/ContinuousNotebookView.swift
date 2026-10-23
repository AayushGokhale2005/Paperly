import SwiftUI

struct ContinuousNotebookView: UIViewControllerRepresentable {
    @Bindable var session: NotebookSession
    let resetRevision: Int
    func makeUIViewController(context: Context) -> ContinuousNotebookController { ContinuousNotebookController(session: session) }
    func updateUIViewController(_ controller: ContinuousNotebookController, context: Context) {
        controller.configure(direction: session.active.pageScrollDirection,
            oneFingerPan: session.active.pencilOnly && session.active.tool != .image,
            resetRevision: resetRevision, scrollRevision: session.scrollRevision,
            pages: session.manifest.pages, pdfReady: session.pdf != nil, paged: session.active.preferences.pagePresentation == .paged)
    }
}

@MainActor final class ContinuousNotebookController: UIViewController, UIScrollViewDelegate {
    let scroll = UIScrollView()
    let content = UIView()
    let session: NotebookSession
    private var hosts: [UUID: UIHostingController<NotebookPageSurface>] = [:]
    private var releasing: Set<UUID> = []
    private var frames: [CGRect] = []
    private var pages: [NotebookPage] = []
    private var direction: PageScrollDirection = .vertical
    private var paged = false
    private var animateNavigation = false
    private var dragStartIndex = 0
    private var fit: CGFloat = 1
    private var viewport = CGSize.zero
    private var needsGeometry = true
    private var resetRevision = 0
    private var scrollRevision = -1
    private var pendingScroll = false
    private var pdfReady = false
    private var forceFit = false
    private var targetPage: UUID?
    private var adjusting = false
    private var addArmed = false
    private let pullLabel = UILabel()

    init(session: NotebookSession) { self.session = session; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(session:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        scroll.delegate = self; scroll.contentInsetAdjustmentBehavior = .never
        scroll.delaysContentTouches = false; scroll.canCancelContentTouches = true
        scroll.alwaysBounceVertical = true; scroll.alwaysBounceHorizontal = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scroll.pinchGestureRecognizer?.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        view.addSubview(scroll); scroll.addSubview(content)
        pullLabel.font = .preferredFont(forTextStyle: .callout); pullLabel.adjustsFontForContentSizeCategory = true
        pullLabel.text = "Release to add page"; pullLabel.textAlignment = .center
        pullLabel.textColor = .label; pullLabel.backgroundColor = .secondarySystemBackground
        pullLabel.layer.cornerRadius = 12; pullLabel.clipsToBounds = true
        pullLabel.isHidden = true; pullLabel.isUserInteractionEnabled = false
        view.addSubview(pullLabel)
    }
    func configure(direction: PageScrollDirection, oneFingerPan: Bool, resetRevision: Int,
                   scrollRevision: Int, pages: [NotebookPage], pdfReady: Bool, paged: Bool = false) {
        loadViewIfNeeded()
        if self.paged != paged || self.direction != direction || self.pages.map(\.id) != pages.map(\.id) {
            needsGeometry = true; pendingScroll = true
        }
        if self.resetRevision != resetRevision { needsGeometry = true; pendingScroll = true; forceFit = true }
        if self.paged != paged { forceFit = true }
        self.paged = paged
        self.direction = direction; self.resetRevision = resetRevision; self.pages = pages
        if self.scrollRevision != scrollRevision {
            animateNavigation = self.scrollRevision >= 0 && session.requestedPage != nil && !UIAccessibility.isReduceMotionEnabled
            pendingScroll = true; targetPage = session.requestedPage; self.scrollRevision = scrollRevision
        }
        scroll.panGestureRecognizer.minimumNumberOfTouches = oneFingerPan ? 1 : 2
        if self.pdfReady != pdfReady {
            self.pdfReady = pdfReady
            for (id, host) in hosts { if let model = session.models[id] { host.rootView = NotebookPageSurface(model: model, pdf: session.pdf) } }
        }
        view.setNeedsLayout()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size.width > 32, size.height > 32, !pages.isEmpty else { return }
        scroll.frame = view.bounds
        if needsGeometry || viewport != size {
            adjusting = true
            let oldRelative = scroll.zoomScale / max(fit, 0.001)
            scroll.minimumZoomScale = 0.01; scroll.maximumZoomScale = 100
            scroll.setZoomScale(1, animated: false)
            let widest = pages.map(\.width).max() ?? 768, tallest = pages.map(\.height).max() ?? 1024
            if paged {
                fit = min((size.width - 32) / widest, (size.height - 32) / tallest)
                let slot = CGSize(width: size.width / fit, height: size.height / fit)
                frames = pages.enumerated().map { index, page in
                    CGRect(x: (slot.width - page.width) / 2 + (direction == .horizontal ? CGFloat(index) * slot.width : 0),
                           y: (slot.height - page.height) / 2 + (direction == .vertical ? CGFloat(index) * slot.height : 0),
                           width: page.width, height: page.height)
                }
                content.frame = CGRect(origin: .zero, size: CGSize(width: slot.width * (direction == .horizontal ? CGFloat(pages.count) : 1),
                                                                   height: slot.height * (direction == .vertical ? CGFloat(pages.count) : 1)))
            } else {
                var cursor: CGFloat = 0
                frames = pages.map { page in
                    let rect: CGRect
                    if direction == .vertical { rect = CGRect(x: (widest - page.width) / 2, y: cursor, width: page.width, height: page.height); cursor += page.height + 24 }
                    else { rect = CGRect(x: cursor, y: (tallest - page.height) / 2, width: page.width, height: page.height); cursor += page.width + 24 }
                    return rect
                }
                content.frame = CGRect(origin: .zero, size: direction == .vertical ? CGSize(width: widest, height: max(1, cursor - 24)) : CGSize(width: max(1, cursor - 24), height: tallest))
                fit = direction == .vertical ? (size.width - 32) / widest : min((size.width - 32) / widest, (size.height - 32) / tallest)
            }
            scroll.contentSize = content.bounds.size
            scroll.minimumZoomScale = fit; scroll.maximumZoomScale = fit * 6
            let reset = forceFit; forceFit = false
            scroll.setZoomScale(fit * (reset ? 1 : max(1, min(6, oldRelative))), animated: false)
            centerDocument()
            for (id, host) in hosts { if let index = pages.firstIndex(where: { $0.id == id }) { host.view.frame = frames[index] } }
            viewport = size; needsGeometry = false; pendingScroll = true; adjusting = false
        }
        if pendingScroll {
            pendingScroll = false
            let target = targetPage ?? session.active.page.id; targetPage = nil
            if let index = pages.firstIndex(where: { $0.id == target }) {
                let frame = frames[index]
                let proposed: CGPoint
                if paged {
                    let relative = scroll.zoomScale / fit
                    proposed = direction == .vertical ? CGPoint(x: 0, y: CGFloat(index) * size.height * relative) : CGPoint(x: CGFloat(index) * size.width * relative, y: 0)
                } else {
                    proposed = direction == .vertical ? CGPoint(x: -scroll.contentInset.left, y: frame.minY * scroll.zoomScale - 16) : CGPoint(x: frame.minX * scroll.zoomScale - 16, y: -scroll.contentInset.top)
                }
                scroll.setContentOffset(clamped(proposed), animated: animateNavigation && view.window != nil)
                animateNavigation = false
            }
        }
        updateVisible()
    }
    private func clamped(_ proposed: CGPoint) -> CGPoint {
        let inset = scroll.contentInset
        return CGPoint(x: min(max(-inset.left, proposed.x), max(-inset.left, scroll.contentSize.width - scroll.bounds.width + inset.right)),
                       y: min(max(-inset.top, proposed.y), max(-inset.top, scroll.contentSize.height - scroll.bounds.height + inset.bottom)))
    }
    private func centerDocument() {
        let padding: CGFloat = paged ? 0 : 16
        let x = max(padding, (scroll.bounds.width - scroll.contentSize.width) / 2)
        let y = max(padding, (scroll.bounds.height - scroll.contentSize.height) / 2)
        scroll.isPagingEnabled = paged && abs(scroll.zoomScale - fit) < max(0.005, fit * 0.01)
        scroll.contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard !adjusting else { return }; centerDocument(); addArmed = false; pullLabel.isHidden = true; updateVisible()
    }
    private func updateVisible(focusFromScroll: Bool = false) {
        guard !adjusting, frames.count == pages.count, !pages.isEmpty else { return }
        let visible = scroll.convert(scroll.bounds, to: content)
        let nearby = visible.insetBy(dx: direction == .horizontal ? -visible.width : 0, dy: direction == .vertical ? -visible.height : 0)
        let indices = frames.indices.filter { frames[$0].intersects(nearby) }
        let keep = Set(indices.map { pages[$0].id })
        session.retainedPages = keep
        for index in indices where hosts[pages[index].id] == nil {
            let model = session.editor(for: index)
            let host = UIHostingController(rootView: NotebookPageSurface(model: model, pdf: session.pdf))
            hosts[pages[index].id] = host
            addChild(host); host.view.backgroundColor = .clear; host.view.frame = frames[index]
            content.addSubview(host.view); host.didMove(toParent: self)
        }
        if focusFromScroll, let index = frames.indices.max(by: { area(frames[$0].intersection(visible)) < area(frames[$1].intersection(visible)) }),
           frames[index].intersects(visible), hosts[pages[index].id] != nil {
            let id = pages[index].id
            if session.active.page.id != id {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let now = self.scroll.convert(self.scroll.bounds, to: self.content)
                    guard let best = self.frames.indices.max(by: { self.area(self.frames[$0].intersection(now)) < self.area(self.frames[$1].intersection(now)) }), self.pages[best].id == id else { return }
                    self.session.focus(id, fromScroll: true)
                }
            }
        }
        for id in hosts.keys where !keep.contains(id) && !releasing.contains(id) {
            releasing.insert(id)
            Task { [weak self] in
                guard let self else { return }
                if await self.session.prepareRelease(id), self.session.discardPage(id), let host = self.hosts.removeValue(forKey: id) {
                    host.willMove(toParent: nil); host.view.removeFromSuperview(); host.removeFromParent()
                }
                self.releasing.remove(id)
            }
        }
    }
    private func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : max(0, rect.width) * max(0, rect.height) }
    private func isPastEnd() -> Bool {
        let inset = scroll.contentInset, size = scroll.bounds.size, content = scroll.contentSize
        let minX = -inset.left, minY = -inset.top
        let maxX = max(minX, content.width - size.width + inset.right)
        let maxY = max(minY, content.height - size.height + inset.bottom)
        let x = scroll.contentOffset.x, y = scroll.contentOffset.y
        let cross = direction == .vertical ? max(minX - x, x - maxX, 0) : max(minY - y, y - maxY, 0)
        return PagePullAction.resolve(offset: Double(direction == .vertical ? y : x),
            minimum: Double(direction == .vertical ? minY : minX), maximum: Double(direction == .vertical ? maxY : maxX),
            crossOverscroll: Double(cross), pageIndex: pages.count - 1, pageCount: pages.count) == .add
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !adjusting else { return }
        updateVisible(focusFromScroll: scroll.isDragging || scroll.isDecelerating || scroll.isZooming)
        guard scroll.isDragging, !scroll.isZooming, scroll.pinchGestureRecognizer?.state != .began, scroll.pinchGestureRecognizer?.state != .changed else { return }
        let armed = isPastEnd() && !session.busy
        if armed && !addArmed { UISelectionFeedbackGenerator().selectionChanged() }
        addArmed = armed; pullLabel.isHidden = !armed
        pullLabel.frame = CGRect(x: 20, y: view.bounds.height - 80, width: view.bounds.width - 40, height: 60)
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { dragStartIndex = session.activeIndex }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { updateVisible(focusFromScroll: true) }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { updateVisible(focusFromScroll: true) }
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let add = addArmed && isPastEnd() && !scroll.isZooming
        addArmed = false; pullLabel.isHidden = true
        if add { session.addPage(template: session.manifest.pages.last?.template) }
        if paged, scroll.isPagingEnabled, !pages.isEmpty {
            let extent = direction == .vertical ? scroll.bounds.height : scroll.bounds.width
            let proposed = direction == .vertical ? targetContentOffset.pointee.y : targetContentOffset.pointee.x
            let nearest = Int((proposed / max(1, extent)).rounded())
            let index = min(pages.count - 1, max(0, min(dragStartIndex + 1, max(dragStartIndex - 1, nearest))))
            if direction == .vertical { targetContentOffset.pointee.y = CGFloat(index) * extent }
            else { targetContentOffset.pointee.x = CGFloat(index) * extent }
        }
    }
}
