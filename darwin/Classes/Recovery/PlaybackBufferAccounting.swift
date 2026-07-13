import Foundation

enum PlaybackAccountingRepairOutcome: String, Equatable {
  case repaired
  case noOutstandingBuffers = "no_outstanding_buffers"
  case scheduledExtentChanged = "scheduled_extent_changed"
}

/// Completion-driven playback accounting, isolated from the player node so
/// repair and stale-callback behavior are deterministic and hardware-free.
struct PlaybackBufferAccounting {
  private(set) var generation = 0
  private(set) var outstandingBuffers = 0
  private(set) var renderedMsAccumulated: Double = 0
  private(set) var scheduledMsAccumulated: Double = 0
  private(set) var lastPlaybackEndedAt: TimeInterval?

  var renderedMs: Int { Int(renderedMsAccumulated.rounded()) }
  var scheduledMs: Int { Int(scheduledMsAccumulated.rounded()) }

  mutating func schedule(bufferMs: Double) -> Int {
    scheduledMsAccumulated += bufferMs
    outstandingBuffers += 1
    return generation
  }

  mutating func complete(generation scheduledGeneration: Int, bufferMs: Double, now: TimeInterval) {
    guard scheduledGeneration == generation, outstandingBuffers > 0 else { return }
    renderedMsAccumulated += bufferMs
    outstandingBuffers -= 1
    if outstandingBuffers == 0 { lastPlaybackEndedAt = now }
  }

  mutating func discardOutstanding(now: TimeInterval) {
    generation += 1
    if outstandingBuffers > 0 { lastPlaybackEndedAt = now }
    outstandingBuffers = 0
  }

  /// Compare-and-repair: a caller that diagnosed rendered-out playback passes
  /// the scheduled extent from that same snapshot. Any newly queued audio
  /// changes the extent and makes the stale repair a no-op.
  mutating func repairRenderedOut(
    expectedScheduledMs: Int,
    now: TimeInterval
  ) -> PlaybackAccountingRepairOutcome {
    guard expectedScheduledMs == scheduledMs else { return .scheduledExtentChanged }
    guard outstandingBuffers > 0 else { return .noOutstandingBuffers }
    outstandingBuffers = 0
    generation += 1
    lastPlaybackEndedAt = now
    return .repaired
  }
}

/// Player-node sample offsets must survive non-destructive accounting repair.
/// They reset only when `AVAudioPlayerNode.stop()` resets the render timeline.
struct PlaybackQueueTimeline {
  private(set) var totalFrames: UInt32 = 0

  mutating func reserve(frameCount: UInt32) -> UInt32 {
    let offset = totalFrames
    totalFrames += frameCount
    return offset
  }

  mutating func resetAfterPlayerStop() {
    totalFrames = 0
  }
}
