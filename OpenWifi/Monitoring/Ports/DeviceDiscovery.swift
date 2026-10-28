protocol DeviceDiscovery: Sendable {
  func sweep() async -> [DiscoveredHost]
}
