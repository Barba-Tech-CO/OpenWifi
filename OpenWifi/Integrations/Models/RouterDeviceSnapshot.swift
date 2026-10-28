import Foundation

/// Optional fields stay nil when the router does not report them.
struct RouterDeviceSnapshot: Sendable, Equatable {
  let macAddress: String?
  let address: String?
  let name: String?
  let meshNode: String?
  let associatedSince: Date?
  let signalStrengthDbm: Int?
}
