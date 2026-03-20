import Foundation

/// Swift wrapper around the WebRTC Audio Processing Module (APM) C bridge.
///
/// Provides echo cancellation (AEC3/AECM), noise suppression, and automatic
/// gain control by processing audio through the standalone WebRTC APM library.
/// Mirrors the Android `WebRtcApm.kt` implementation.
class WebRtcApm {
  private var handle: WebRtcApmHandle?

  /// Whether the APM was successfully initialized.
  var isAvailable: Bool { handle != nil }

  /// Create and configure a WebRTC APM instance.
  ///
  /// - Parameters:
  ///   - captureSampleRate: Mic capture sample rate in Hz (e.g., 48000).
  ///   - renderSampleRate: Speaker playback sample rate in Hz (e.g., 24000).
  ///   - aecEnabled: Enable acoustic echo cancellation.
  ///   - nsEnabled: Enable noise suppression.
  ///   - agcEnabled: Enable automatic gain control.
  init(
    captureSampleRate: Int,
    renderSampleRate: Int,
    aecEnabled: Bool = true,
    nsEnabled: Bool = true,
    agcEnabled: Bool = true
  ) {
    handle = webrtc_apm_bridge_create(
      Int32(captureSampleRate),
      Int32(renderSampleRate),
      aecEnabled,
      nsEnabled,
      agcEnabled
    )
  }

  /// Set the estimated audio pipeline delay in milliseconds.
  func setStreamDelay(_ delayMs: Int) {
    guard let handle else { return }
    webrtc_apm_bridge_set_stream_delay(handle, Int32(delayMs))
  }

  /// Process captured (near-end / microphone) audio through APM.
  ///
  /// Audio is processed in-place — the buffer is modified. Must contain
  /// PCM int16 LE samples at the capture sample rate.
  func processCapture(_ data: UnsafeMutablePointer<Int8>, length: Int) {
    guard let handle else { return }
    webrtc_apm_bridge_process_capture(handle, data, Int32(length))
  }

  /// Feed render (far-end / speaker playback) audio into APM as echo reference.
  ///
  /// The buffer is read but not modified. Must contain PCM int16 LE samples
  /// at the render sample rate.
  func processRender(_ data: UnsafePointer<Int8>, length: Int) {
    guard let handle else { return }
    webrtc_apm_bridge_process_render(handle, data, Int32(length))
  }

  /// Release the APM instance and all native resources.
  func release() {
    guard let handle else { return }
    webrtc_apm_bridge_destroy(handle)
    self.handle = nil
  }

  deinit {
    release()
  }
}
