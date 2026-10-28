import Foundation

/// Traffic of THIS Mac on one interface; never the whole network.
struct TrafficRate: Sendable, Equatable {
  let interfaceName: String
  let timestamp: Date
  let downloadBytesPerSecond: Double
  let uploadBytesPerSecond: Double
}
