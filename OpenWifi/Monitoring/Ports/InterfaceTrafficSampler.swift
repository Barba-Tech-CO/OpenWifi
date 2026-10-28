protocol InterfaceTrafficSampler: Sendable {
  func readCounters() async throws -> InterfaceCounters
}
