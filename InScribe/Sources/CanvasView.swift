import SwiftUI
import PencilKit

struct CanvasView: View {
    @StateObject private var canvasViewModel = CanvasViewModel()
    @State private var autoSlideOn = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            CanvasViewWrapper(viewModel: canvasViewModel)
                .ignoresSafeArea()

            HStack(spacing: 8) {
                // Home and new page buttons
                VStack(alignment: .leading, spacing: 8) {
                    
                    Button {
                        // Implement go-to-home logic here
                    } label: {
                        Image(systemName:"house")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 45, height: 45)
                            .background(Color.gray.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    Button {
                        // Implement add-page logic here
                    } label: {
                        Image(systemName: "document.badge.plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 45, height: 45)
                            .background(Color.gray.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                
                // Auto-slide and nudge buttons
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            autoSlideOn.toggle()
                        }
                        canvasViewModel.autoSlideEnabled = autoSlideOn
                    } label: {
                        Image(systemName: autoSlideOn ? "pencil.line" : "pencil.and.scribble")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 45, height: 45)
                            .background(Color.gray.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Image(systemName: "arrow.forward")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 45, height: 45)
                        .background(Color.gray.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in canvasViewModel.startContinuousNudge() }
                                .onEnded   { _ in canvasViewModel.stopContinuousNudge()  }
                        )
                    
                }

                ToolbarView(viewModel: canvasViewModel)
            }
            .padding(16)
        }
    }
}

struct CanvasViewWrapper: UIViewRepresentable {
    let viewModel: CanvasViewModel

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawingPolicy = .pencilOnly
        canvasView.backgroundColor = .white
        canvasView.isRulerActive = false
        canvasView.tool = PKInkingTool(viewModel.inkType,
                                       color: UIColor(viewModel.inkColor),
                                       width: viewModel.strokeWidth)

        canvasView.minimumZoomScale = 0.25
        canvasView.maximumZoomScale = 4.0
        canvasView.bouncesZoom = true
        canvasView.showsHorizontalScrollIndicator = false
        canvasView.showsVerticalScrollIndicator = false
        canvasView.contentSize = viewModel.canvasSize

        canvasView.delegate = context.coordinator
        viewModel.canvasView = canvasView

        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate, UIScrollViewDelegate {
        let viewModel: CanvasViewModel
        private var previousStrokeCount = 0

        init(viewModel: CanvasViewModel) {
            self.viewModel = viewModel
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let strokes = canvasView.drawing.strokes
            if viewModel.autoSlideEnabled, strokes.count > previousStrokeCount {
                applyAutoSlide(strokes.last, in: canvasView)
            }
            previousStrokeCount = strokes.count
            viewModel.lastDrawing = canvasView.drawing
        }

        private func applyAutoSlide(_ stroke: PKStroke?, in canvasView: PKCanvasView) {
            guard let stroke = stroke else { return }

            let firstPoint = stroke.path[0].location.x
            let lastPoint = stroke.path[stroke.path.count - 1].location.x
            let deltaX = lastPoint - firstPoint

            guard deltaX > 1 else { return }

            let shift = deltaX * canvasView.zoomScale
            var newOffsetX = canvasView.contentOffset.x + shift
            let maxOffset = max(0, canvasView.contentSize.width - canvasView.bounds.width)
            newOffsetX = max(0, min(maxOffset, newOffsetX))

            UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseOut) {
                canvasView.contentOffset.x = newOffsetX
            }
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            viewModel.zoomScale = scrollView.zoomScale
            viewModel.contentOffset = scrollView.contentOffset
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            viewModel.contentOffset = scrollView.contentOffset
        }
    }
}

final class CanvasViewModel: ObservableObject {
    let canvasSize = CGSize(width: 5464, height: 4096)
    var lastDrawing: PKDrawing?
    var zoomScale: CGFloat = 1.0
    var contentOffset: CGPoint = .zero
    var autoSlideEnabled: Bool = true

    weak var canvasView: PKCanvasView?

    // MARK: - Tool state

    @Published var inkColor: Color = .black {
        didSet { if !isEraser { applyTool() } }
    }
    @Published var strokeWidth: CGFloat = 3.0 {
        didSet { if !isEraser { applyTool() } }
    }
    @Published var inkType: PKInkingTool.InkType = .pen
    @Published var isEraser: Bool = false

    init() {
        loadDefaults()
    }

    private func loadDefaults() {
        let r = UserDefaults.standard.double(forKey: "inkColorR")
        let g = UserDefaults.standard.double(forKey: "inkColorG")
        let b = UserDefaults.standard.double(forKey: "inkColorB")
        let a = UserDefaults.standard.double(forKey: "inkColorA")
        if r != 0 || g != 0 || b != 0 {
            inkColor = Color(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), opacity: CGFloat(a))
        }
        strokeWidth = UserDefaults.standard.double(forKey: "strokeWidth")
            .isZero ? 3.0 : UserDefaults.standard.double(forKey: "strokeWidth")
        if let raw = UserDefaults.standard.string(forKey: "inkType") {
            inkType = PKInkingTool.InkType(rawValue: raw) ?? .pen
        }
        isEraser = UserDefaults.standard.bool(forKey: "isEraser")
    }

    private func saveDefaults() {
        let uiColor = UIColor(inkColor)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
            UserDefaults.standard.set(Double(r), forKey: "inkColorR")
            UserDefaults.standard.set(Double(g), forKey: "inkColorG")
            UserDefaults.standard.set(Double(b), forKey: "inkColorB")
            UserDefaults.standard.set(Double(a), forKey: "inkColorA")
        }
        UserDefaults.standard.set(Double(strokeWidth), forKey: "strokeWidth")
        UserDefaults.standard.set(inkType.rawValue, forKey: "inkType")
        UserDefaults.standard.set(isEraser, forKey: "isEraser")
    }

    func applyTool() {
        guard let canvasView else { return }
        if isEraser {
            canvasView.tool = PKEraserTool(.bitmap)
        } else {
            canvasView.tool = PKInkingTool(inkType, color: UIColor(inkColor), width: strokeWidth)
        }
        saveDefaults()
    }

    // MARK: - Continuous nudge

    /// Points per second to scroll while the button is held.
    private let nudgeRate: CGFloat = 600
    /// Timer fires at 60 Hz for smooth scrolling.
    private let timerInterval: TimeInterval = 1.0 / 60.0
    private var nudgeTimer: Timer?

    func startContinuousNudge() {
        guard nudgeTimer == nil else { return }   // already running
        nudgeTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { [weak self] _ in
            self?.stepNudge()
        }
    }

    func stopContinuousNudge() {
        nudgeTimer?.invalidate()
        nudgeTimer = nil
    }

    private func stepNudge() {
        guard let canvasView else { return }
        let step = nudgeRate * timerInterval
        let maxOffset = max(0, canvasView.contentSize.width - canvasView.bounds.width)
        let newOffsetX = max(0, min(maxOffset, canvasView.contentOffset.x + step))
        canvasView.contentOffset.x = newOffsetX   // no animation — timer provides the smoothness
    }
}
