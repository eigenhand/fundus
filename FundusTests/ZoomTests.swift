import AVFoundation
import XCTest
@testable import Fundus

/// Der Zoom — und vor allem die Umrechnung auf „×".
///
/// Die ist der heikle Teil, und zwar aus einem Grund, den man nicht sieht:
/// `videoZoomFactor` 1 ist die **weiteste** Linse, die das Geraet hat. Bei einem
/// Telefon mit Ultraweitwinkel ist das, was der Nutzer 0,5× nennt. Bei einem ohne ist
/// dieselbe 1 schon 1×. Wer das verwechselt, beschriftet jeden Knopf falsch — und
/// zwar plausibel falsch, sodass es niemandem auffaellt ausser dem, der zoomt.
final class ZoomTests: XCTestCase {

    /// Drei Linsen: Ultraweitwinkel, Weitwinkel, Tele. Umschaltpunkte bei 2 und 6.
    private var triple: CameraSession.Zoom {
        CameraSession.zoomRange(switchOver: [2, 6], hasUltraWide: true,
                                minimum: 1, maximum: 123)
    }

    /// Zwei Linsen ohne Ultraweitwinkel: Weitwinkel und Tele.
    private var wideAndTele: CameraSession.Zoom {
        CameraSession.zoomRange(switchOver: [3], hasUltraWide: false,
                                minimum: 1, maximum: 60)
    }

    /// Eine einzige Linse.
    private var single: CameraSession.Zoom {
        CameraSession.zoomRange(switchOver: [], hasUltraWide: false, minimum: 1, maximum: 16)
    }

    // MARK: Wo „1×" liegt

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

    /// Ohne Wahl keine Zeile: ein Knopf, der nichts umschaltet, ist keiner.
    func testASingleLensOffersNoButtons() {
        XCTAssertEqual(single.stops.count, 1)
    }

    /// Ein Umschaltpunkt jenseits der Obergrenze gehoert nicht auf einen Knopf.
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

    /// Kann das Geraet weniger, gilt das Geraet.
    func testAModestDeviceKeepsItsOwnLimit() {
        let z = CameraSession.zoomRange(switchOver: [], hasUltraWide: false,
                                        minimum: 1, maximum: 3)
        XCTAssertEqual(z.maximum, 3)
    }
}
