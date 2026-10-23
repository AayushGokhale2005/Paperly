import SwiftUI

struct NotebookImagesView: View {
    @Bindable var model: EditorViewModel
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.images) { image in
                PageImageObject(model: model, item: image)
            }
        }
        .frame(width: model.page.width, height: model.page.height)
        .allowsHitTesting(model.tool == .image && !model.loading && !model.importingImage)
    }
}

private struct PageImageObject: View {
    @Bindable var model: EditorViewModel
    let item: NotebookImage
    @State private var decoded: UIImage?
    @State private var translation: CGSize = .zero
    @State private var resizeFactor: Double = 1
    private var selected: Bool { model.tool == .image && model.selectedImageID == item.id }
    var body: some View {
        Group {
            if let decoded { Image(uiImage: decoded).resizable().scaledToFit() }
            else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .frame(width: item.width * resizeFactor, height: item.height * resizeFactor)
        .overlay {
            if selected { Rectangle().stroke(.blue, style: StrokeStyle(lineWidth: 1.5, dash: [6, 3])) }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.onFocus?(); model.selectedImageID = item.id }
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("paperPage"))
            .onChanged { value in model.onFocus?(); model.selectedImageID = item.id; translation = value.translation }
            .onEnded { value in
                var moved = item; moved.x += value.translation.width; moved.y += value.translation.height
                translation = .zero; model.updateImage(moved)
            })
        .overlay(alignment: .bottomTrailing) {
            if selected {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.body.bold()).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(.blue, in: Circle())
                    .accessibilityLabel("Resize image")
                    .accessibilityAdjustableAction { direction in
                        var resized = item
                        let factor = direction == .increment ? 1.1 : 0.9
                        resized.width *= factor; resized.height *= factor
                        model.updateImage(resized, action: "Resize image")
                    }
                    .highPriorityGesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("paperPage"))
                        .onChanged { value in resizeFactor = max(0.15, 1 + Double(value.translation.width) / max(item.width, 1)) }
                        .onEnded { _ in
                            var resized = item
                            let centerX = item.x + item.width / 2, centerY = item.y + item.height / 2
                            resized.width *= resizeFactor; resized.height *= resizeFactor
                            resized.x = centerX - resized.width / 2; resized.y = centerY - resized.height / 2
                            resizeFactor = 1; model.updateImage(resized, action: "Resize image")
                        })
                    .offset(x: 20, y: 20)
            }
        }
        .rotationEffect(.degrees(item.rotation))
        .position(x: item.x + item.width / 2 + translation.width, y: item.y + item.height / 2 + translation.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(selected ? "Selected image" : "Page image")
        .accessibilityAction(named: "Select image") { model.onFocus?(); model.tool = .image; model.selectedImageID = item.id }
        .accessibilityAction(named: "Move right") { var value = item; value.x += 20; model.updateImage(value) }
        .accessibilityAction(named: "Move down") { var value = item; value.y += 20; model.updateImage(value) }
        .task(id: item.assetPath) { if let data = model.imageBytes[item.id] { decoded = UIImage(data: data) } }
    }
}
