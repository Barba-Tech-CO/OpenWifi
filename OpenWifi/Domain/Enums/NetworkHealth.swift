enum NetworkHealth: Sendable, Hashable {
  case normal
  case degraded
  case offline
  case unknown

  /// No internet-target samples yet: unknown. Every internet probe lost: offline.
  /// Either target losing 5% or more, or internet latency above 150 ms: degraded.
  init(gateway: LatencyStats, external: LatencyStats) {
    if external.sampleCount == 0 {
      self = .unknown
    } else if external.lossRatio == 1 {
      self = .offline
    } else if gateway.lossRatio >= 0.05
      || external.lossRatio >= 0.05
      || (external.averageMilliseconds ?? 0) > 150 {
      self = .degraded
    } else {
      self = .normal
    }
  }
}
