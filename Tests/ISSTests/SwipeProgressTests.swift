import ISS
import XCTest

// iss_swipe_progress_for_phase isn't in ISS.h, so it's bound by name.
// CGSGesturePhase is uint8_t in cgs_private.h; ISSDirection is a C enum (int).
@_silgen_name("iss_swipe_progress_for_phase")
private func iss_swipe_progress_for_phase(_ phase: UInt8, _ direction: ISSDirection) -> Double

private let phaseBegan: UInt8 = 1
private let phaseChanged: UInt8 = 2
private let phaseEnded: UInt8 = 4

/// Mirrors kMinimalSwipeProgress in ISS.c
private let minimalProgress = 0.000016

final class SwipeProgressTests: XCTestCase {
  /// Every phase uses a tiny signed progress, so there's nothing visible to animate.
  func testEveryPhaseUsesMinimalSignedProgress() {
    for phase in [phaseBegan, phaseChanged, phaseEnded] {
      XCTAssertEqual(iss_swipe_progress_for_phase(phase, ISSDirectionRight), minimalProgress)
      XCTAssertEqual(iss_swipe_progress_for_phase(phase, ISSDirectionLeft), -minimalProgress)
    }
  }

  func testSignIsConsistentAcrossPhases() {
    for direction in [ISSDirectionLeft, ISSDirectionRight] {
      let signs = [phaseBegan, phaseChanged, phaseEnded].map {
        iss_swipe_progress_for_phase($0, direction).sign
      }
      XCTAssertEqual(Set(signs).count, 1, "phases disagree on direction for \(direction)")
    }
  }
}
