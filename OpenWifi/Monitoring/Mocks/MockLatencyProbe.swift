import Foundation

/// Deterministic fake: gateway answers in 2-4 ms (ICMP), everything else in 14-20 ms (TCP);
/// every 10th external probe is lost.
actor MockLatencyProbe: LatencyProbe {
  private var calls = 0

  func measureRoundTrip(to target: String) -> ProbeResult {
    calls += 1
    let isGateway = target == MockNetworkPathObserver.gatewayAddress
    let isLost = !isGateway && calls % 10 == 0
    let rtt = isGateway ? 2.0 + Double(calls % 3) : 14.0 + Double(calls % 7)
    return ProbeResult(
      target: target,
      timestamp: Date(),
      rttMilliseconds: isLost ? nil : rtt,
      method: isGateway ? .icmp : .tcp,
      isEstimated: false,
    )
  }
}
