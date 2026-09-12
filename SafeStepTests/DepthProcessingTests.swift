import XCTest
@testable import SafeStep

final class DepthProcessingTests: XCTestCase {
    func testUniformFrameFillsEveryCell() {
        let frame = DepthFrame(width: 6, height: 6, meters: Array(repeating: 2.5, count: 36))
        let grid = DepthGridSampler.sample(frame)

        XCTAssertEqual(grid.columns, 3)
        XCTAssertEqual(grid.rows, 3)
        XCTAssertEqual(grid.cells.count, 9)

        for row in 0..<3 {
            for column in 0..<3 {
                let cell = grid.cell(row: row, column: column)
                XCTAssertEqual(cell.minMeters ?? -1, 2.5, accuracy: 0.0001)
                XCTAssertEqual(cell.validFraction, 1.0, accuracy: 0.0001)
            }
        }
    }

    func testInvalidSamplesAreExcludedFromMinAndFraction() {
        // 2×2 frame → one 3×3-incompatible split; use 2×2 grid instead.
        let meters: [Float] = [
            1.0, 0,
            Float.nan, -3.0
        ]
        let frame = DepthFrame(width: 2, height: 2, meters: meters)
        let grid = DepthGridSampler.sample(frame, columns: 2, rows: 2)

        XCTAssertEqual(grid.cell(row: 0, column: 0).minMeters ?? -1, 1.0, accuracy: 0.0001)
        XCTAssertEqual(grid.cell(row: 0, column: 0).validFraction, 1.0, accuracy: 0.0001)

        XCTAssertNil(grid.cell(row: 0, column: 1).minMeters)
        XCTAssertEqual(grid.cell(row: 0, column: 1).validFraction, 0)

        XCTAssertNil(grid.cell(row: 1, column: 0).minMeters)
        XCTAssertEqual(grid.cell(row: 1, column: 0).validFraction, 0)

        XCTAssertNil(grid.cell(row: 1, column: 1).minMeters)
        XCTAssertEqual(grid.cell(row: 1, column: 1).validFraction, 0)
    }

    func testCellUsesMinimumOfValidSamples() {
        let meters: [Float] = [
            4.0, 1.5, 8.0, 0,
            3.0, 2.0, Float.nan, 9.0,
            5.0, 5.0, 5.0, 5.0,
            5.0, 5.0, 5.0, 5.0
        ]
        let frame = DepthFrame(width: 4, height: 4, meters: meters)
        let grid = DepthGridSampler.sample(frame, columns: 2, rows: 2)
        let topLeft = grid.cell(row: 0, column: 0)

        XCTAssertEqual(topLeft.minMeters ?? -1, 1.5, accuracy: 0.0001)
        XCTAssertEqual(topLeft.validFraction, 1.0, accuracy: 0.0001)

        let topRight = grid.cell(row: 0, column: 1)
        XCTAssertEqual(topRight.minMeters ?? -1, 8.0, accuracy: 0.0001)
        XCTAssertEqual(topRight.validFraction, 0.5, accuracy: 0.0001)
    }

    func testThreeByThreeLayoutMapsLeftCenterRightAndFarMidNearGround() {
        // 3×3 frame: each pixel is one cell. Columns increase left→right;
        // rows increase far (top) → near-ground (bottom).
        let meters: [Float] = [
            10, 11, 12,
            20, 21, 22,
            30, 31, 32
        ]
        let grid = DepthGridSampler.sample(DepthFrame(width: 3, height: 3, meters: meters))

        XCTAssertEqual(grid.cell(row: .far, column: .left).minMeters ?? -1, 10, accuracy: 0.0001)
        XCTAssertEqual(grid.cell(row: .far, column: .center).minMeters ?? -1, 11, accuracy: 0.0001)
        XCTAssertEqual(grid.cell(row: .far, column: .right).minMeters ?? -1, 12, accuracy: 0.0001)

        XCTAssertEqual(grid.cell(row: .mid, column: .left).minMeters ?? -1, 20, accuracy: 0.0001)
        XCTAssertEqual(grid.cell(row: .mid, column: .center).minMeters ?? -1, 21, accuracy: 0.0001)
        XCTAssertEqual(grid.cell(row: .mid, column: .right).minMeters ?? -1, 22, accuracy: 0.0001)

        XCTAssertEqual(grid.cell(row: .nearGround, column: .left).minMeters ?? -1, 30, accuracy: 0.0001)
        XCTAssertEqual(grid.cell(row: .nearGround, column: .center).minMeters ?? -1, 31, accuracy: 0.0001)
        XCTAssertEqual(grid.cell(row: .nearGround, column: .right).minMeters ?? -1, 32, accuracy: 0.0001)
    }

    func testDirectionFromColumnIndex() {
        XCTAssertEqual(DepthGridSampler.direction(fromColumn: 0), .left)
        XCTAssertEqual(DepthGridSampler.direction(fromColumn: 1), .center)
        XCTAssertEqual(DepthGridSampler.direction(fromColumn: 2), .right)

        let grid = DepthGridSampler.sample(
            DepthFrame(width: 3, height: 3, meters: Array(repeating: 1, count: 9))
        )
        XCTAssertEqual(grid.direction(fromColumn: 0), .left)
        XCTAssertEqual(grid.direction(fromColumn: 1), .center)
        XCTAssertEqual(grid.direction(fromColumn: 2), .right)
    }

    func testUnevenDimensionsAssignRemainderToLaterCells() {
        // width 5 → columns 1, 2, 2 pixels. Fill each pixel with its column bucket depth.
        var meters = [Float](repeating: 0, count: 5 * 3)
        for y in 0..<3 {
            meters[y * 5 + 0] = 1
            meters[y * 5 + 1] = 2
            meters[y * 5 + 2] = 2
            meters[y * 5 + 3] = 3
            meters[y * 5 + 4] = 3
        }
        let grid = DepthGridSampler.sample(DepthFrame(width: 5, height: 3, meters: meters))

        XCTAssertEqual(grid.cell(row: 0, column: 0).minMeters ?? -1, 1, accuracy: 0.0001)
        XCTAssertEqual(grid.cell(row: 0, column: 1).minMeters ?? -1, 2, accuracy: 0.0001)
        XCTAssertEqual(grid.cell(row: 0, column: 2).minMeters ?? -1, 3, accuracy: 0.0001)
        XCTAssertEqual(grid.cell(row: 0, column: 0).validFraction, 1.0, accuracy: 0.0001)
        XCTAssertEqual(grid.cell(row: 0, column: 1).validFraction, 1.0, accuracy: 0.0001)
        XCTAssertEqual(grid.cell(row: 0, column: 2).validFraction, 1.0, accuracy: 0.0001)
    }

    func testEmptyFrameYieldsEmptyCells() {
        let grid = DepthGridSampler.sample(DepthFrame(width: 0, height: 0, meters: []))
        XCTAssertEqual(grid.cells.count, 9)
        for cell in grid.cells {
            XCTAssertNil(cell.minMeters)
            XCTAssertEqual(cell.validFraction, 0)
        }
    }

    func testInfinityIsInvalid() {
        let frame = DepthFrame(width: 1, height: 1, meters: [.infinity])
        let cell = DepthGridSampler.sample(frame, columns: 1, rows: 1).cell(row: 0, column: 0)
        XCTAssertNil(cell.minMeters)
        XCTAssertEqual(cell.validFraction, 0)
    }

    func testPixelSizeMatchesWidthAndHeight() {
        let frame = DepthFrame(width: 8, height: 4, meters: Array(repeating: 1, count: 32))
        XCTAssertEqual(frame.size.x, 8)
        XCTAssertEqual(frame.size.y, 4)
        XCTAssertEqual(frame[7, 3], 1)
    }
}
