import Foundation

struct ProbeResult: Sendable, Equatable {
  let target: String
  let timestamp: Date
  /// nil means no reply (lost or filtered); never a made-up value.
  let rttMilliseconds: Double?
  let method: ProbeMethod
  let isEstimated: Bool
}
