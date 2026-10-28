protocol RouterAdapter: Sendable {
  func probeCapabilities() async throws -> RouterCapabilities
  func fetchDevices() async throws -> [RouterDeviceSnapshot]
  func fetchTraffic() async throws -> [RouterTrafficSample]
}
