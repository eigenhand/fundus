import AVFoundation
import XCTest
@testable import Fundus

/// The zoom — and above all the conversion to "×".
///
/// That is the delicate part, for a reason you cannot see: `videoZoomFactor` 1 is the
/// **widest** lens the device has. On a phone with an ultra-wide that is what the user
/// calls 0.5×. On one without, the same 1 is already 1×. Confuse the two and every
/// button is labelled wrong — plausibly wrong, so that nobody notices except the person
/// zooming.
final class ZoomTests: XCTestCase {

    /// Three lenses: ultra-wide, wide, telephoto. Switch-over points at 2 and 6.
    private var triple: CameraSession.Zoom {
        CameraSession.zoomRange(switchOver: [2, 6], hasUltraWide: true,
                                minimum: 1, maximum: 123)
    }

    /// Two lenses without an ultra-wide: wide and telephoto.
    private var wideAndTele: CameraSession.Zoom {
        CameraSession.zoomRange(switchOver: [3], hasUltraWide: false,
                                minimum: 1, maximum: 60)
    }

    /// Eine einzige Linse.
    private var single: CameraSession.Zoom {
        CameraSession.zoomRange(switchOver: [], hasUltraWide: false, minimum: 1, maximum: 16)
    }

    // MARK: Where "1×" sits

    func testWithAnUltraWideTheBaselineIsTheFirstSwitchOver() {
        XCTAssertEqual(triple.baseline, 2, "Auf dem Ultraweitwinkel ist 1 gleich 0,5×.")
        XCTAssertEqual(triple.current, 2, "Der Sucher macht bei 1× auf, nicht bei 0,5×.")
    }

    func testWithoutAnUltraWideOneIsOne() {
        XCTAssertEqual(wideAndTele.baseline, 1)
        XCTAssertEqual(single.baseline, 1)
    }

    // MARK: Die Beschriftung

    func testLabelsOnATripleCamera() {
        let z = triple
        XCTAssertEqual(z.label(1), "0,5×")
        XCTAssertEqual(z.label(2), "1×")
        XCTAssertEqual(z.label(6), "3×")
        XCTAssertEqual(z.label(3), "1,5×", "Zwischen den Linsen mit Komma, nicht mit Punkt.")
    }

    func testLabelsWithoutAnUltraWide() {
        let z = wideAndTele
        XCTAssertEqual(z.label(1), "1×")
        XCTAssertEqual(z.label(3), "3×")
    }

    // MARK: Die Knoepfe

    func testTheStopsAreTheLenses() {
        XCTAssertEqual(triple.stops, [1, 2, 6])
        XCTAssertEqual(triple.stops.map { triple.label($0) }, ["0,5×", "1×", "3×"])
    }

    /// No choice, no row: a button that switches nothing is not one.
    func testASingleLensOffersNoButtons() {
        XCTAssertEqual(single.stops.count, 1)
    }

    /// A switch-over point beyond the upper bound does not belong on a button.
    func testStopsBeyondTheCapAreDropped() {
        let z = CameraSession.zoomRange(switchOver: [2, 40], hasUltraWide: true,
                                        minimum: 1, maximum: 123)
        XCTAssertEqual(z.maximum, 16, "Achtmal die Ausgangsweite, mehr ist Brei.")
        XCTAssertEqual(z.stops, [1, 2], "40 liegt darueber.")
    }

    // MARK: Die Obergrenze

    func testTheCapFollowsTheBaseline() {
        XCTAssertEqual(triple.maximum, 16, "Achtmal 1× — und 1× ist hier 2.")
        XCTAssertEqual(wideAndTele.maximum, 8)
    }

    /// If the device can do less, the device wins.
    func testAModestDeviceKeepsItsOwnLimit() {
        let z = CameraSession.zoomRange(switchOver: [], hasUltraWide: false,
                                        minimum: 1, maximum: 3)
        XCTAssertEqual(z.maximum, 3)
    }
}
