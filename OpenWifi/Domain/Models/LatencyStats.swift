struct LatencyStats: Sendable, Equatable {
  let sampleCount: Int
  /// 0...1; 0 when there are no samples.
  let lossRatio: Double
  let averageMilliseconds: Double?
  let minimumMilliseconds: Double?
  let maximumMilliseconds: Double?
  /// Method of the most recent sample, so the UI labels ICMP vs TCP honestly.
  let method: ProbeMethod?

  static let empty = LatencyStats(
    sampleCount: 0,
    lossRatio: 0,
    averageMilliseconds: nil,
    minimumMilliseconds: nil,
    maximumMilliseconds: nil,
    method: nil,
  )
}
