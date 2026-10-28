import Foundation

struct InterfaceCounters: Sendable, Equatable {
  let interfaceName: String
  let timestamp: Date
  let receivedBytes: UInt64
  let sentBytes: UInt64
  /// Width of the kernel counters: 32 or 64. Decides where rollover happens.
  let counterBits: Int
}
