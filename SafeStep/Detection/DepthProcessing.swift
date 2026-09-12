import Foundation
import simd

/// Camera-space depth image in meters, stored row-major (`meters[y * width + x]`).
///
/// Values that are non-finite or `<= 0` are invalid. This is the ARKit seam: later,
/// copy `ARFrame.sceneDepth.depthMap` (`CVPixelBuffer` Float32 meters) into `meters`
/// without importing ARKit or UIKit here.
struct DepthFrame: Equatable {
    let width: Int
    let height: Int
    /// Row-major depth samples in meters. Count must equal `width * height`.
    let meters: [Float]

    /// Pixel width and height as a SIMD vector.
    var size: SIMD2<Int> { SIMD2(width, height) }

    init(width: Int, height: Int, meters: [Float]) {
        precondition(width >= 0 && height >= 0, "DepthFrame dimensions must be non-negative")
        precondition(
            meters.count == width * height,
            "DepthFrame meters count (\(meters.count)) must equal width * height (\(width * height))"
        )
        self.width = width
        self.height = height
        self.meters = meters
    }

    /// Depth at pixel `(x, y)`, with `x` left-to-right and `y` top-to-bottom.
    subscript(x: Int, y: Int) -> Float {
        meters[y * width + x]
    }

    /// A sample is valid when it is a finite, strictly positive distance in meters.
    static func isValid(_ meters: Float) -> Bool {
        meters.isFinite && meters > 0
    }
}

/// Horizontal walk-path column, derived from a grid column index.
enum HazardDirection: Int, CaseIterable, Equatable {
    case left
    case center
    case right
}

/// Vertical band of the default 3-row grid. Row 0 is the top of the depth image.
enum DepthGridRow: Int, CaseIterable, Equatable {
    /// Top of the image — farther scene.
    case far = 0
    /// Middle band — typical obstacle / torso height.
    case mid = 1
    /// Bottom of the image — near-ground walking surface.
    case nearGround = 2
}

/// Aggregated samples for one cell of a depth grid.
struct DepthGridCell: Equatable {
    /// Closest valid depth in the cell, in meters. `nil` when every sample is invalid.
    let minMeters: Float?
    /// Fraction of samples in the cell that were valid, in `0...1`.
    let validFraction: Float
}

/// Rectangular grid of depth cells. The default layout is 3×3:
/// columns left / center / right, rows far / mid / near-ground (top to bottom).
struct DepthGrid: Equatable {
    let columns: Int
    let rows: Int
    /// Row-major cells, length `columns * rows`.
    let cells: [DepthGridCell]

    func cell(row: Int, column: Int) -> DepthGridCell {
        precondition(row >= 0 && row < rows, "row \(row) is outside 0..<\(rows)")
        precondition(column >= 0 && column < columns, "column \(column) is outside 0..<\(columns)")
        return cells[row * columns + column]
    }

    func cell(row: DepthGridRow, column: HazardDirection) -> DepthGridCell {
        cell(row: row.rawValue, column: column.rawValue)
    }

    /// Maps a column index onto left / center / right using this grid's column count.
    func direction(fromColumn column: Int) -> HazardDirection {
        DepthGridSampler.direction(fromColumn: column, columnCount: columns)
    }
}

/// Splits a `DepthFrame` into a coarse grid and reduces each cell to its nearest
/// valid sample plus coverage fraction.
enum DepthGridSampler {
    /// Samples `frame` into `columns` × `rows` cells (defaults to 3×3).
    ///
    /// Column 0 is left, then center, then right. Row 0 is far (top of the image),
    /// then mid, then near-ground (bottom). Remainders from uneven dimensions go
    /// to the later columns and rows.
    static func sample(_ frame: DepthFrame, columns: Int = 3, rows: Int = 3) -> DepthGrid {
        precondition(columns > 0 && rows > 0, "grid dimensions must be positive")

        var cells: [DepthGridCell] = []
        cells.reserveCapacity(columns * rows)

        for row in 0..<rows {
            let y0 = row * frame.height / rows
            let y1 = (row + 1) * frame.height / rows
            for column in 0..<columns {
                let x0 = column * frame.width / columns
                let x1 = (column + 1) * frame.width / columns
                cells.append(sampleCell(frame, x0: x0, x1: x1, y0: y0, y1: y1))
            }
        }

        return DepthGrid(columns: columns, rows: rows, cells: cells)
    }

    /// Maps a column index onto left / center / right.
    ///
    /// For the default 3-column grid this is `0 → left`, `1 → center`, `2 → right`.
    /// Other column counts are split into thirds.
    static func direction(fromColumn column: Int, columnCount: Int = 3) -> HazardDirection {
        precondition(columnCount > 0, "columnCount must be positive")
        precondition(column >= 0 && column < columnCount, "column \(column) is outside 0..<\(columnCount)")
        switch (column * 3) / columnCount {
        case 0:
            return .left
        case 1:
            return .center
        default:
            return .right
        }
    }

    private static func sampleCell(
        _ frame: DepthFrame,
        x0: Int,
        x1: Int,
        y0: Int,
        y1: Int
    ) -> DepthGridCell {
        let total = (x1 - x0) * (y1 - y0)
        guard total > 0 else {
            return DepthGridCell(minMeters: nil, validFraction: 0)
        }

        var validCount = 0
        var minMeters: Float = .infinity

        for y in y0..<y1 {
            let rowStart = y * frame.width
            for x in x0..<x1 {
                let value = frame.meters[rowStart + x]
                guard DepthFrame.isValid(value) else { continue }
                validCount += 1
                minMeters = simd_min(minMeters, value)
            }
        }

        return DepthGridCell(
            minMeters: validCount > 0 ? minMeters : nil,
            validFraction: Float(validCount) / Float(total)
        )
    }
}
