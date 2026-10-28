protocol LatencyProbe: Sendable {
  func measureRoundTrip(to target: String) async -> ProbeResult
}
