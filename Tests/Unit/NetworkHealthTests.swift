import Testing
@testable import OpenWifi

struct NetworkHealthTests {
  private func stats(loss: Double, average: Double?, count: Int = 10) -> LatencyStats {
    LatencyStats(
      sampleCount: count,
      lossRatio: loss,
      averageMilliseconds: average,
      minimumMilliseconds: average,
      maximumMilliseconds: average,
      method: .tcp,
    )
  }

  @Test func noExternalSamplesIsUnknown() {
    #expect(NetworkHealth(gateway: .empty, external: .empty) == .unknown)
  }

  @Test func totalExternalLossIsOffline() {
    let health = NetworkHealth(gateway: stats(loss: 0, average: 2), external: stats(loss: 1, average: nil))

    #expect(health == .offline)
  }

  @Test func someLossOrHighLatencyIsDegraded() {
    let lossy = NetworkHealth(gateway: stats(loss: 0.1, average: 2), external: stats(loss: 0, average: 20))
    let slow = NetworkHealth(gateway: stats(loss: 0, average: 2), external: stats(loss: 0, average: 400))

    #expect(lossy == .degraded)
    #expect(slow == .degraded)
  }

  @Test func lowLossAndLatencyIsNormal() {
    let health = NetworkHealth(gateway: stats(loss: 0, average: 2), external: stats(loss: 0, average: 20))

    #expect(health == .normal)
  }
}
