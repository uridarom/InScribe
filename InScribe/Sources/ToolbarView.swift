import SwiftUI
import PencilKit

struct ToolbarView: View {
    @ObservedObject var viewModel: CanvasViewModel

    private let swatches: [Color] = [
        .black, .red, .orange, .yellow, .green, .blue, .purple
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Color swatches
            HStack(spacing: 6) {
                ForEach(swatches, id: \.self) { color in
                    Button {
                        viewModel.inkColor = color
                        viewModel.isEraser = false
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .stroke(viewModel.inkColor == color && !viewModel.isEraser
                                            ? Color.white : Color.clear, lineWidth: 2)
                            )
                    }
                }
                // Color picker
                ColorPicker("", selection: $viewModel.inkColor)
                .labelsHidden()
                .padding(.horizontal, 4)
                // Stroke width slider + preview
                HStack(spacing: 10) {
                    Circle()
                        .fill(viewModel.inkColor)
                        .frame(width: max(4, viewModel.strokeWidth),
                               height: max(4, viewModel.strokeWidth))

                    Slider(value: $viewModel.strokeWidth, in: 1...20, step: 1)
                        .labelsHidden()

                    Text(String(format: "%.0f", viewModel.strokeWidth))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(width: 24, alignment: .trailing)
                }
            }

            // Ink types
            HStack(spacing: 4) {
                inkTypeButton(label: "Pen", type: .pen)
                inkTypeButton(label: "Marker", type: .marker)
                inkTypeButton(label: "Pencil", type: .pencil)
                Divider().frame(height: 24)
                eraserButton()
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func inkTypeButton(label: String, type: PKInkingTool.InkType) -> some View {
        Button {
            viewModel.inkType = type
            viewModel.isEraser = false
            viewModel.applyTool()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(viewModel.inkType == type && !viewModel.isEraser
                                 ? .black : .white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(viewModel.inkType == type && !viewModel.isEraser
                            ? Color.white.opacity(0.5) : Color.clear)
                .clipShape(Capsule())
        }
    }

    private func eraserButton() -> some View {
        Button {
            viewModel.isEraser = true
            viewModel.applyTool()
        } label: {
            Text("Eraser")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(viewModel.isEraser ? .black : .white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(viewModel.isEraser
                            ? Color.white.opacity(0.5) : Color.clear)
                .clipShape(Capsule())
        }
    }
}
