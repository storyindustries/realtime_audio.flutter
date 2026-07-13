import XCTest
@testable import RealtimeAudioRecovery

final class PlaybackBufferAccountingTests: XCTestCase {
  func testRenderedOutRepairClearsOutstandingWithoutDiscardingPlayer() {
    var accounting = PlaybackBufferAccounting()
    _ = accounting.schedule(bufferMs: 120)

    let outcome = accounting.repairRenderedOut(expectedScheduledMs: 120, now: 10)

    XCTAssertEqual(outcome, .repaired)
    XCTAssertEqual(accounting.outstandingBuffers, 0)
    XCTAssertEqual(accounting.generation, 1)
    XCTAssertEqual(accounting.lastPlaybackEndedAt, 10)
  }

  func testRepairRejectsStaleScheduledExtentWhenNewAudioWasQueued() {
    var accounting = PlaybackBufferAccounting()
    _ = accounting.schedule(bufferMs: 120)
    let staleExpectedExtent = accounting.scheduledMs
    _ = accounting.schedule(bufferMs: 80)

    let outcome = accounting.repairRenderedOut(expectedScheduledMs: staleExpectedExtent, now: 10)

    XCTAssertEqual(outcome, .scheduledExtentChanged)
    XCTAssertEqual(accounting.outstandingBuffers, 2)
    XCTAssertEqual(accounting.generation, 0)
  }

  func testLateCompletionFromRepairedGenerationCannotCorruptNewGeneration() {
    var accounting = PlaybackBufferAccounting()
    let repairedGeneration = accounting.schedule(bufferMs: 120)
    XCTAssertEqual(accounting.repairRenderedOut(expectedScheduledMs: 120, now: 10), .repaired)
    let currentGeneration = accounting.schedule(bufferMs: 80)

    accounting.complete(generation: repairedGeneration, bufferMs: 120, now: 11)

    XCTAssertEqual(currentGeneration, 1)
    XCTAssertEqual(accounting.outstandingBuffers, 1)
    XCTAssertEqual(accounting.renderedMs, 0)
  }

  func testCompletionAndDiscardMaintainMonotonicCounters() {
    var accounting = PlaybackBufferAccounting()
    let generation = accounting.schedule(bufferMs: 120)
    accounting.complete(generation: generation, bufferMs: 120, now: 10)
    _ = accounting.schedule(bufferMs: 80)
    accounting.discardOutstanding(now: 11)

    XCTAssertEqual(accounting.scheduledMs, 200)
    XCTAssertEqual(accounting.renderedMs, 120)
    XCTAssertEqual(accounting.outstandingBuffers, 0)
    XCTAssertEqual(accounting.generation, 1)
  }

  func testQueueTimelineKeepsOffsetsAcrossAccountingRepairUntilPlayerStop() {
    var timeline = PlaybackQueueTimeline()

    XCTAssertEqual(timeline.reserve(frameCount: 2_400), 0)
    XCTAssertEqual(timeline.reserve(frameCount: 2_400), 2_400)
    XCTAssertEqual(timeline.totalFrames, 4_800)

    // Accounting repair deliberately does not reset the player timeline.
    XCTAssertEqual(timeline.reserve(frameCount: 2_400), 4_800)
    timeline.resetAfterPlayerStop()
    XCTAssertEqual(timeline.reserve(frameCount: 2_400), 0)
  }
}
