import SwiftUI
import PencilKit

struct PenSettingsView: View {
    @Bindable var model: EditorViewModel
    var body: some View {
        NavigationStack {
            Form {
                Section("Pen style") {
                    Picker("Ink", selection: $model.penStyle) {
                        ForEach(PenStyle.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    Text(model.penStyle.detail).font(.subheadline).foregroundStyle(.secondary)
                    PenStrokePreview(style: model.penStyle, color: model.color, width: model.width)
                        .frame(height: 90).listRowBackground(Color.white)
                }
                Section {
                    LabeledContent("Stroke width", value: String(format: "%.1f pt", model.width))
                    Slider(value: $model.width, in: 0.5...12, step: 0.5).accessibilityLabel("Stroke width")
                    HStack {
                        ForEach([1.0, 3.0, 5.0], id: \.self) { width in
                            Button("\(Int(width)) pt") { model.width = width }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(model.width == width ? Color.blue.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }.buttonStyle(.plain)
                    ColorPicker("Ink color", selection: $model.color, supportsOpacity: true)
                } header: { Text("Ink") }
                Section {
                    Toggle("Scribble to Erase", isOn: $model.scribbleToErase)
                    Toggle("Include highlighter", isOn: $model.scribbleIncludesHighlighter).disabled(!model.scribbleToErase)
                } header: { Text("Pen gestures") } footer: {
                    Text("With the Pen selected, scribble back and forth quickly over existing ink. Only overlapping ink is removed; images and PDF content stay intact. Undo restores the erased ink.")
                }
                Section {
                    Toggle("Apple Pencil only", isOn: $model.pencilOnly)
                    Toggle("Precision eraser", isOn: $model.precisionEraser)
                }
            }
            .navigationTitle("Pen settings").navigationBarTitleDisplayMode(.inline)
        }.frame(idealWidth: 390, idealHeight: 640)
    }
}

private struct PenStrokePreview: UIViewRepresentable {
    let style: PenStyle
    let color: Color
    let width: Double
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView(); canvas.overrideUserInterfaceStyle = .light; canvas.isUserInteractionEnabled = false; canvas.backgroundColor = .white
        return canvas
    }
    func updateUIView(_ view: PKCanvasView, context: Context) {
        let points = (0...60).map { index in
            let progress = Double(index) / 60
            let pressure = 0.2 + 0.8 * sin(progress * .pi)
            let size = style == .ball ? width : width * (0.35 + pressure * 1.5)
            return PKStrokePoint(location: CGPoint(x: 10 + progress * 285, y: 45 + sin(progress * .pi * 2) * 22), timeOffset: progress, size: CGSize(width: size, height: size), opacity: 1, force: pressure, azimuth: 0, altitude: .pi / 2)
        }
        let stroke = PKStroke(ink: PKInk(style.inkType, color: PaperInk.color(UIColor(color))), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0)))
        view.drawing = PKDrawing(strokes: [stroke])
    }
}
