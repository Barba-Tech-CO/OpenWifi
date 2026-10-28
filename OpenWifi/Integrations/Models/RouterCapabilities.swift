struct RouterCapabilities: Sendable, Equatable {
  let clients: Bool
  let clientTraffic: Bool
  let associationTime: Bool
  let meshNode: Bool
  let signalStrength: Bool
}
