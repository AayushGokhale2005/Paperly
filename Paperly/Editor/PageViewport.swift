import SwiftUI

/// Zoom the complete page as a single surface, keeping ink, PDF and image coordinates identical.
struct PageViewport<Content: View>: UIViewControllerRepresentable {
    let pageID: UUID
    let pageSize: CGSize
    let pageIndex: Int
    let pageCount: Int
    let direction: PageScrollDirection
    let pencilOnly: Bool
    let enabled: Bool
    let resetRevision: Int
    let onZoom: (Double) -> Void
    let onPage: (PagePullAction) -> Void
    @ViewBuilder var content: () -> Content

    func makeUIViewController(context: Context) -> PageViewportController<Content> {
        PageViewportController(root: content())
    }
    func updateUIViewController(_ controller: PageViewportController<Content>, context: Context) {
        controller.configure(root: content(), pageID: pageID, pageSize: pageSize,
            pageIndex: pageIndex, pageCount: pageCount, direction: direction,
            pencilOnly: pencilOnly, enabled: enabled, resetRevision: resetRevision,
            onZoom: onZoom, onPage: onPage)
    }
}

@MainActor final class PageViewportController<Content: View>: UIViewController, UIScrollViewDelegate {
    let scrollView = UIScrollView()
    let hosting: UIHostingController<Content>
    private let pullLabel = UILabel()
    private var pageID: UUID?
    private var pageSize = CGSize(width: 768, height: 1024)
    private var pageIndex = 0
    private var pageCount = 1
    private var direction: PageScrollDirection = .vertical
    private var enabled = true
    private var resetRevision = 0
    private var fitScale: CGFloat = 1
    private var needsFit = true
    private var lastViewportSize = CGSize.zero
    private var pendingAction: PagePullAction?
    private var onZoom: ((Double) -> Void)?
    private var onPage: ((PagePullAction) -> Void)?
    private var adjusting = false

    init(root: Content) { hosting = UIHostingController(rootView: root); super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Use init(root:)") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.panGestureRecognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.pinchGestureRecognizer?.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        scrollView.accessibilityIdentifier = "pageViewport"
        view.addSubview(scrollView)
        addChild(hosting)
        hosting.view.backgroundColor = .clear
        scrollView.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        pullLabel.font = .preferredFont(forTextStyle: .callout)
        pullLabel.adjustsFontForContentSizeCategory = true
        pullLabel.textColor = .label
        pullLabel.backgroundColor = .secondarySystemBackground
        pullLabel.layer.cornerRadius = 12; pullLabel.clipsToBounds = true
        pullLabel.textAlignment = .center; pullLabel.numberOfLines = 2
        pullLabel.isUserInteractionEnabled = false; pullLabel.isHidden = true
        view.addSubview(pullLabel)
    }
    func configure(root: Content, pageID: UUID, pageSize: CGSize, pageIndex: Int, pageCount: Int,
                   direction: PageScrollDirection, pencilOnly: Bool, enabled: Bool,
                   resetRevision: Int, onZoom: @escaping (Double) -> Void,
                   onPage: @escaping (PagePullAction) -> Void) {
        loadViewIfNeeded()
        let changedPage = self.pageID != pageID || self.pageSize != pageSize
        let reset = self.resetRevision != resetRevision
        self.pageID = pageID; self.pageSize = pageSize
        self.pageIndex = pageIndex; self.pageCount = pageCount
        self.direction = direction; self.enabled = enabled
        self.resetRevision = resetRevision; self.onZoom = onZoom; self.onPage = onPage
        hosting.rootView = root
        // Keep one-finger/Pencil strokes available. With Pencil-only enabled, one finger pans.
        scrollView.panGestureRecognizer.minimumNumberOfTouches = pencilOnly ? 1 : 2
        scrollView.isScrollEnabled = enabled
        if !enabled { pendingAction = nil; pullLabel.isHidden = true }
        if changedPage || reset { needsFit = true }
        view.setNeedsLayout()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let viewport = view.bounds.size
        guard viewport.width > 24, viewport.height > 24, pageSize.width > 0, pageSize.height > 0 else { return }
        scrollView.frame = view.bounds
        guard needsFit || viewport != lastViewportSize else { return }
        let reset = needsFit
        let relativeZoom = reset ? 1 : scrollView.zoomScale / max(fitScale, 0.001)
        let oldCenter = CGPoint(x: (scrollView.contentOffset.x + scrollView.bounds.width / 2) / max(scrollView.zoomScale, 0.001),
                                y: (scrollView.contentOffset.y + scrollView.bounds.height / 2) / max(scrollView.zoomScale, 0.001))
        adjusting = true
        // Remove the old transform before changing the page's unscaled geometry.
        scrollView.minimumZoomScale = 0.01; scrollView.maximumZoomScale = 20
        scrollView.setZoomScale(1, animated: false)
        hosting.view.frame = CGRect(origin: .zero, size: pageSize)
        scrollView.contentSize = pageSize
        fitScale = min((viewport.width - 24) / pageSize.width, (viewport.height - 24) / pageSize.height)
        scrollView.minimumZoomScale = fitScale
        scrollView.maximumZoomScale = fitScale * 6
        scrollView.setZoomScale(min(scrollView.maximumZoomScale, fitScale * relativeZoom), animated: false)
        centerPage()
        let minimum = CGPoint(x: -scrollView.contentInset.left, y: -scrollView.contentInset.top)
        let maximum = CGPoint(x: max(minimum.x, scrollView.contentSize.width - viewport.width + scrollView.contentInset.right),
                              y: max(minimum.y, scrollView.contentSize.height - viewport.height + scrollView.contentInset.bottom))
        scrollView.contentOffset = reset ? minimum : CGPoint(
            x: min(maximum.x, max(minimum.x, oldCenter.x * scrollView.zoomScale - viewport.width / 2)),
            y: min(maximum.y, max(minimum.y, oldCenter.y * scrollView.zoomScale - viewport.height / 2)))
        needsFit = false; lastViewportSize = viewport; adjusting = false
    }
    private func centerPage() {
        let horizontal = max(12, (scrollView.bounds.width - scrollView.contentSize.width) / 2)
        let vertical = max(12, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { hosting.view }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard !adjusting else { return }
        pendingAction = nil; pullLabel.isHidden = true; centerPage()
    }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        onZoom?(Double(scale / max(fitScale, 0.001)))
    }
    private func action() -> PagePullAction? {
        let inset = scrollView.contentInset, size = scrollView.bounds.size, content = scrollView.contentSize
        let minX = -inset.left, minY = -inset.top
        let maxX = max(minX, content.width - size.width + inset.right)
        let maxY = max(minY, content.height - size.height + inset.bottom)
        let x = scrollView.contentOffset.x, y = scrollView.contentOffset.y
        let cross = direction == .vertical ? max(minX - x, x - maxX, 0) : max(minY - y, y - maxY, 0)
        return PagePullAction.resolve(offset: Double(direction == .vertical ? y : x),
            minimum: Double(direction == .vertical ? minY : minX), maximum: Double(direction == .vertical ? maxY : maxX),
            crossOverscroll: Double(cross), pageIndex: pageIndex, pageCount: pageCount)
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard enabled, !adjusting, scrollView.isDragging, !scrollView.isZooming,
              scrollView.pinchGestureRecognizer?.state != .began,
              scrollView.pinchGestureRecognizer?.state != .changed else { return }
        let next = action()
        if next != pendingAction, next != nil { UISelectionFeedbackGenerator().selectionChanged() }
        pendingAction = next
        pullLabel.isHidden = next == nil
        guard let next else { return }
        switch next {
        case .previous: pullLabel.text = "Release for previous page"
        case .next: pullLabel.text = "Release for next page"
        case .add: pullLabel.text = "Release to add page"
        }
        let height: CGFloat = 64, width = min(view.bounds.width - 32, 340)
        pullLabel.frame = CGRect(x: (view.bounds.width - width) / 2,
                                y: next == .previous ? 16 : view.bounds.height - height - 16,
                                width: width, height: height)
    }
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                  targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let selected = pendingAction
        pendingAction = nil; pullLabel.isHidden = true
        guard enabled, let selected, selected == action(), !scrollView.isZooming else { return }
        // Only explicit dragging can turn/add pages; deceleration and pinch bounce cannot.
        targetContentOffset.pointee = scrollView.contentOffset
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        onPage?(selected)
    }
}
