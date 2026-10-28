struct DiscoveredHost: Sendable, Equatable {
  let address: String
  let macAddress: String?
  let name: String?
  let source: DataSource
  /// false when the host shows up (for example in the neighbor table) but filters probes.
  let respondsToProbes: Bool
}
