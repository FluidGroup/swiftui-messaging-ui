
import os.log

enum Log {
  
  static let generic = Logger(OSLog.makeOSLogInDebug { OSLog.init(subsystem: "MessagingUI", category: "generic") })
  static let layout = Logger(OSLog.makeOSLogInDebug { OSLog.init(subsystem: "MessagingUI", category: "layout") })
  
}

extension OSLog {

  @inline(__always)
  fileprivate static func makeOSLogInDebug(isEnabled: Bool = true, _ factory: () -> OSLog) -> OSLog {
#if DEBUG
    return factory()
#else
    return .disabled
#endif
  }

}
