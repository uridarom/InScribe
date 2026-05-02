# InScribe — Technical Specification Sheet
**Platform:** iPadOS  
**Distribution:** Apple App Store  
**Language:** Swift 5.9+  
**Minimum Deployment Target:** iPadOS 16.0  
**Architecture Pattern:** MVVM (Model–View–ViewModel)

InScribe is a note-taking app made for iPad and Apple Pencil.
It should be implemented as described below. Make the app as light and bloat-free as possible.

---

## Tech Stack Overview

| Layer | Technology |
|---|---|
| Primary UI Framework | SwiftUI |
| Drawing Engine | PencilKit (`PKCanvasView`, `PKDrawing`, `PKStroke`) |
| UIKit Integration | `UIViewRepresentable` wrapper around `PKCanvasView` |
| Data Persistence | SwiftData (iOS 17+) or Core Data (for iOS 16 compatibility) |
| Scroll & Zoom | `UIScrollView` hosting the canvas |
| Undo / Redo | `UndoManager` (system-provided, tied to `PKCanvasView`) |

---

## Feature 1 — Basic Writing Canvas

### Goal
Display a blank, white canvas that accepts handwriting input via Apple Pencil in black ink.

### Implementation Details

**Canvas Setup**
- Wrap Apple's `PKCanvasView` in a `UIViewRepresentable` struct to embed it inside SwiftUI views.
- Set `canvasView.drawingPolicy = .pencilOnly` so that only Apple Pencil input registers as strokes (finger input should scroll/navigate, not draw).
- Set the initial tool to `PKInkingTool(.pen, color: .black, width: 3)`.
- The logical canvas size should be large — at minimum 4× the iPad screen in both dimensions (e.g., 5464 × 4096 points) — to give ample writing space before scrolling becomes necessary.

**Background**
- Set `canvasView.backgroundColor = .white`.
- At this stage the background is purely white with no markings.

**Pencil Interaction**
- Do not configure `PKToolPicker` at this stage; tool selection is added in Feature 4.
- `canvasView.isRulerActive = false`.

---

## Feature 2 — Zoom In / Out

### Goal
Allow the user to pinch-to-zoom the canvas to adjust the writing scale.

### Implementation Details

**Scroll View Container**
- Host the `PKCanvasView` inside a `UIScrollView`.
- Set `scrollView.delegate` to a coordinator that implements `viewForZooming(in:)`, returning the `PKCanvasView`.
- Set zoom bounds: `scrollView.minimumZoomScale = 0.25` and `scrollView.maximumZoomScale = 4.0`.
- Enable `scrollView.bouncesZoom = true` for a natural feel.

**Scroll vs. Draw Conflict**
- When `drawingPolicy = .pencilOnly`, `UIScrollView` pan/pinch gestures handle finger input automatically, since finger touches are not intercepted by PencilKit. No additional gesture recognizer configuration is needed.

**Persistent Zoom State**
- Store the current `zoomScale` and `contentOffset` in the view model so they are restored when the user navigates away and returns to the page.

---

## Feature 3 — Auto-Slide (Writing Drift Compensation)

### Goal
When the user finishes a stroke, automatically shift the viewport horizontally in the opposite direction of the stroke, by an amount equal to the stroke's horizontal displacement. This keeps the active writing area stationary on screen.

### Implementation Details

**Stroke Completion Detection**
- Implement `PKCanvasViewDelegate` and observe the `canvasViewDrawingDidChange(_:)` method, which fires after each stroke is committed.
- To isolate the *just-completed* stroke, compare the current `PKDrawing.strokes` array against the previously cached copy. The newly appended stroke is the one to analyze.

**Horizontal Displacement Calculation**
1. Get the bounding `CGRect` of the new stroke via `stroke.renderBounds`.
2. Compute the horizontal displacement: `deltaX = stroke.renderBounds.maxX - stroke.renderBounds.minX`, signed by the direction of the stroke. A more precise method is to compare the X coordinate of the stroke path's first and last `PKStrokePoint`: `deltaX = lastPoint.location.x - firstPoint.location.x`.
3. Clamp `deltaX` to avoid extreme jumps (suggested max per stroke: 300 points).

**Applying the Shift**
- Adjust `scrollView.contentOffset.x += deltaX * scrollView.zoomScale`.
- Animate the shift using `UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut)` for a smooth feel.
- Clamp the resulting offset to the valid range `[0, scrollView.contentSize.width - scrollView.bounds.width]` to prevent overscrolling.

**Edge Case — Vertical Strokes**
- If the horizontal component of a stroke is smaller than a threshold (e.g., < 10 points), do not trigger a slide to avoid jitter during vertical strokes.

---

## Feature 4 — Stroke Size and Color

### Goal
Allow the user to change the ink color and stroke width via an on-screen toolbar.

### Implementation Details

**Toolbar Placement**
- Display a floating toolbar on the side of the canvas view built in SwiftUI.
- The toolbar should match the aesthetics of the auto-slide button; semi transparent, rounded corners, compact layout.

**Color Picker**
- Use SwiftUI's native `ColorPicker` control, bound to a `@State var selectedColor: Color` in the view model.
- On color change, update the canvas tool: `canvasView.tool = PKInkingTool(.pen, color: UIColor(selectedColor), width: currentWidth)`.
- Provide quick-select swatches for common colors (black, blue, red, green, pencil grey) alongside the full color picker.

**Stroke Width**
- Use a `Slider` control bound to `@State var strokeWidth: CGFloat` (range: 1.0–20.0).
- On change, recreate the `PKInkingTool` with the updated width.
- Display a live preview dot of the selected color and size next to the slider.

**Ink Types**
- Expose a segmented control or icon strip for ink types: Pen (`PKInkingTool.InkType.pen`), Marker (`.marker`), and Pencil (`.pencil`).
- Erasure: include an eraser button that sets `canvasView.tool = PKEraserTool(.bitmap)`.

**State Persistence**
- Store the last-used color, width, and ink type in `UserDefaults` so they are restored across sessions.

---

## Feature 5 — Notebooks and Pages

### Goal
Organize content into named notebooks, each containing one or more pages. The app's home screen becomes a notebook browser.

### Data Models (SwiftData)

```swift
@Model class Notebook {
    var id: UUID
    var name: String
    var createdAt: Date
    var coverColor: String       // hex string, for visual differentiation
    @Relationship(deleteRule: .cascade) var pages: [Page]
}

@Model class Page {
    var id: UUID
    var order: Int               // display order within the notebook
    var drawingData: Data        // PKDrawing serialized via pkDrawing.dataRepresentation()
    var backgroundStyle: String  // "blank" | "grid" | "ruled" (used in Feature 9)
    var notebook: Notebook?
}
```

**Persistence**
- Initialize a `ModelContainer` with `Notebook` and `Page` as schema types in the `App` entry point.
- Inject the container via `.modelContainer(...)` modifier.
- All reads and writes use `@Query` and `modelContext.insert` / `modelContext.delete`.

### Home Screen — Notebook List

**Layout**
- Use a SwiftUI `NavigationSplitView` (sidebar + detail) on iPad for a native split-layout experience.
- Display notebooks in a `LazyVGrid` with 2–3 columns. Each notebook card shows its name, page count, and cover color.

**Create Notebook**
- A "New Notebook" button opens a sheet with a `TextField` for the name and a color/style picker for the cover.
- On confirm, insert a new `Notebook` with one default blank `Page`.

**Delete Notebook**
- Support swipe-to-delete on list rows and long-press → context menu → "Delete" on grid cards.
- Show a confirmation alert before deletion (since it cascades to all pages).

**Rename Notebook**
- Long-press context menu includes a "Rename" option, triggering an inline `TextField` or a modal sheet.

### Notebook View — Page Navigation

- Tapping a notebook navigates to a page view.
- Display a horizontal page strip at the bottom (thumbnail scroll view) for navigating between pages.
- An "Add Page" button appends a new blank `Page` to the notebook.
- Pages are re-orderable via drag-and-drop on the thumbnail strip.

---

## Feature 6 — Undo and Redo

### Goal
Allow the user to undo and redo individual strokes.

### Implementation Details

**UndoManager Integration**
- `PKCanvasView` registers its own undo/redo actions automatically with the responder chain's `UndoManager`.
- Ensure the `PKCanvasView` (or its hosting `UIViewController`) is in the responder chain and does not have undo manager suppressed.
- Access the canvas's undo manager via `canvasView.undoManager`.

**Toolbar Buttons**
- Add Undo and Redo buttons to the main toolbar (SF Symbols: `arrow.uturn.backward` / `arrow.uturn.forward`).
- Bind enabled state to `canvasView.undoManager?.canUndo` and `canvasView.undoManager?.canRedo` respectively, observed via a `Publisher` on `NSUndoManager.didUndoChangeNotification` and `NSUndoManager.didRedoChangeNotification`.

**Persistence Caveat**
- Undo history is in-memory only and is not persisted when the app is closed. When the page is loaded from storage, the undo stack starts fresh.

---

## Feature 7 — Lasso Selection and Deletion

### Goal
Allow the user to draw a freeform closed shape on the canvas. Any stroke fully or partially within the enclosed area is deleted.

### Implementation Details

**Selection Mode Toggle**
- Add a lasso/selection icon button in the toolbar. When active, entering "selection mode" changes the canvas interaction from drawing to selection.
- In selection mode, set `canvasView.isUserInteractionEnabled = false` (to suppress PencilKit input) and attach a custom `UIPanGestureRecognizer` to the hosting scroll view that captures pencil-only touches.

> **Alternative approach:** Use `PKLassoTool` (`canvasView.tool = PKLassoTool()`) which is natively supported by PencilKit. However, `PKLassoTool` does not expose the selected strokes programmatically in the public API; for full programmatic control, the custom approach below is preferred.

**Custom Lasso Path (Recommended)**
1. On gesture start, initialize an empty `CGMutablePath` and add the first touch point via `path.move(to:)`.
2. On each gesture update, append points via `path.addLine(to:)`. Draw a live preview of the lasso path using a `CAShapeLayer` overlaid on the canvas.
3. On gesture end, close the path via `path.closeSubpath()`.

**Stroke Hit Testing**
1. Iterate over all `PKStroke` objects in `canvasView.drawing.strokes`.
2. For each stroke, iterate its `PKStrokePath` sample points and check whether any point falls inside the lasso `CGPath` using `lassoPath.contains(point.location)`.
3. Collect all strokes where at least one sample point is contained.

**Deletion**
- Remove identified strokes: create a new `PKDrawing` from the filtered strokes array (excluding matches) and assign it to `canvasView.drawing`.
- Register this as an undoable action via `undoManager.registerUndo(...)` so the deletion can be reversed.

**Cleanup**
- After deletion (or cancellation), remove the `CAShapeLayer` overlay and exit selection mode.

---

## Feature 8 — Modify Selected Strokes (Color and Size)

### Goal
After making a lasso selection (as described in Feature 7), allow the user to change the color and/or stroke width of the selected strokes, rather than deleting them.

### Implementation Details

**Selection State**
- After the lasso path is closed, instead of immediately deleting, enter a "selection confirmed" state.
- Highlight selected strokes visually by rendering a tinted overlay `CAShapeLayer` using the union of selected stroke `renderBounds` rectangles.
- Display a contextual action bar (floating near the selection) with color swatches and a width slider, matching the controls from Feature 4.

**Applying Style Changes**
- Modifying `PKStroke` properties directly is not possible (strokes are value types and immutable once in a drawing).
- To restyle: iterate selected strokes and recreate each one with a new `PKInkingTool` using the chosen color/width. The stroke path points (`PKStrokePath`) are copied from the original; only the ink is replaced.

```swift
// Pseudocode for stroke restyling
let restyled = selectedStrokes.map { original in
    PKStroke(
        ink: PKInk(inkType, color: newColor),
        path: original.path,       // reuse the exact same path
        transform: original.transform,
        mask: original.mask
    )
}
// Replace in drawing
var strokes = canvasView.drawing.strokes
strokes.removeAll { selectedStrokes.contains($0) }
strokes.append(contentsOf: restyled)
canvasView.drawing = PKDrawing(strokes: strokes)
```

- Register the entire operation as a single undoable action.

**Commit / Cancel**
- Tapping outside the selection area, or pressing a "Deselect" button, clears the selection state and removes overlays.

---

## Feature 9 — Page Background Styles

### Goal
Allow users to choose a background for each page from three options: blank white canvas, grid, and traditional ruled notebook lines.

### Options
| Style | Description |
|---|---|
| `blank` | Plain white, no markings |
| `grid` | Evenly spaced horizontal and vertical lines (e.g., 40 pt spacing) |
| `ruled` | Horizontal ruled lines only, with an optional left red margin line, mimicking a standard notebook |

### Implementation Details

**Rendering the Background**
- The background must be drawn *below* the `PKCanvasView` (which has a transparent background in this mode).
- Set `canvasView.backgroundColor = .clear` so the background layer shows through.
- Create a `BackgroundView: UIView` subclass that overrides `draw(_ rect:)` to render the appropriate pattern using `CGContext`.

**Grid Drawing**
```swift
// In draw(_ rect:) — grid pattern
let spacing: CGFloat = 40
context.setStrokeColor(UIColor.lightGray.withAlphaComponent(0.5).cgColor)
context.setLineWidth(0.5)
for x in stride(from: 0, through: rect.width, by: spacing) {
    context.move(to: CGPoint(x: x, y: 0))
    context.addLine(to: CGPoint(x: x, y: rect.height))
}
for y in stride(from: 0, through: rect.height, by: spacing) {
    context.move(to: CGPoint(x: 0, y: y))
    context.addLine(to: CGPoint(x: rect.width, y: y))
}
context.strokePath()
```

**Ruled Lines Drawing**
- Draw horizontal lines at regular intervals (e.g., every 40 points), using light blue (`#B0C4DE`, α 0.6).
- Draw a single vertical red margin line at x = 60 points from the left edge.

**Stack Layout**
- Layer the views: `BackgroundView` → `PKCanvasView` (transparent), both filling the same frame inside the scroll view's content area.

**Per-Page Persistence**
- Store the background style as the `backgroundStyle` string field on the `Page` SwiftData model.
- Provide a background picker (sheet or popover) accessible from the canvas toolbar.

**Default**
- New pages default to `blank`. The default can be set globally in app settings and overridden per-page.

---

## Additional Implementation Notes

**Saving Drawings**
- Serialize `PKDrawing` to `Data` via `pkDrawing.dataRepresentation()` and store in `Page.drawingData`.
- Deserialize on load via `PKDrawing(data: page.drawingData)`.
- Save on every stroke completion (via `canvasViewDrawingDidChange`) with a debounce of ~1 second to avoid excessive write operations.

**iPad Multitasking**
- Support Split View and Slide Over by using adaptive layouts with `GeometryReader` or `ViewThatFits`.
- Observe `UIScene` size-class changes and adjust toolbar layout accordingly.

**Performance**
- For large drawings, avoid re-rendering the full `PKDrawing` on every change. Use `PKCanvasView`'s built-in tile rendering; do not layer additional custom drawing views that iterate strokes.
- Thumbnail generation for the page strip (Feature 5) should be performed off the main thread using `PKDrawing.image(from:scale:)`.

**Testing**
- Use the iOS Simulator's "Apple Pencil" simulation (`I/O → Apple Pencil`) for basic input testing.
- For gesture-based features (lasso, auto-slide), test on a physical iPad with Apple Pencil as simulator pencil simulation is limited.
