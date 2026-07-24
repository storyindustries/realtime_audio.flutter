import Foundation

#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

struct CancelledError: LocalizedError {
  public var errorDescription: String { "Cancelled." }
}

struct UnimplementedError: LocalizedError {
  public var errorDescription: String { "Unimplemented." }
}

struct UndefinedError: LocalizedError {
  public var errorDescription: String { "Undefined error." }
}

struct TextError: LocalizedError {
  var message: String

  init(_ message: String) {
    self.message = message
  }

  public var errorDescription: String { message }
}

func realtimeAudioFlutterError(_ error: Error) -> FlutterError {
  let nsError = error as NSError
  let code = IOSAudioErrorClassifier.code(
    domain: nsError.domain,
    osStatus: nsError.code
  )

  if code == .insufficientPriority {
    return FlutterError(
      code: code.rawValue,
      message: "Another call or app currently has priority over the audio session.",
      details: [
        "domain": nsError.domain,
        "osStatus": nsError.code,
        "recoverable": true,
      ]
    )
  }

  return FlutterError(
    code: code.rawValue,
    message: (error as? TextError)?.message ?? error.localizedDescription,
    details: nil
  )
}
