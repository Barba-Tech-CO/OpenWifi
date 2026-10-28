import Foundation

struct RouterTrafficSample: Sendable, Equatable {
  let macAddress: String
  let timestamp: Date
  let downloadBytesPerSecond: Double
  let uploadBytesPerSecond: Double
}
