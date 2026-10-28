struct LatencyWindow: Sendable {
  private let capacity: Int
  private var results: [ProbeResult] = []

  init(capacity: Int) {
    self.capacity = capacity
  }

  mutating func add(_ result: ProbeResult) {
    results.append(result)
    if results.count > capacity {
      results.removeFirst(results.count - capacity)
    }
  }

  var stats: LatencyStats {
    guard let latest = results.last else { return .empty }
    let replies = results.compactMap(\.rttMilliseconds)
    let lost = results.count - replies.count
    return LatencyStats(
      sampleCount: results.count,
      lossRatio: Double(lost) / Double(results.count),
      averageMilliseconds: replies.isEmpty ? nil : replies.reduce(0, +) / Double(replies.count),
      minimumMilliseconds: replies.min(),
      maximumMilliseconds: replies.max(),
      method: latest.method,
    )
  }
}
