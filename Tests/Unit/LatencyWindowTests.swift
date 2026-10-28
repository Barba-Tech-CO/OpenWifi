import Foundation
import Testing
@testable import OpenWifi

struct LatencyWindowTests {
  private let start = Date(timeIntervalSince1970: 1_000_000)

  private func result(
    _ rtt: Double?,
    second: Int = 0,
    method: ProbeMethod = .icmp,
  ) -> ProbeResult {
    ProbeResult(
      target: "192.0.2.1",
      timestamp: start.addingTimeInterval(Double(second)),
      rttMilliseconds: rtt,
      method: method,
      isEstimated: false,
    )
  }

  @Test func emptyWindowHasNoStatsAndNoLoss() {
    let window = LatencyWindow(capacity: 5)

    #expect(window.stats == .empty)
  }

  @Test func averageMinMaxIgnoreLostSamples() {
    var window = LatencyWindow(capacity: 5)
    window.add(result(10))
    window.add(result(nil))
    window.add(result(30))

    #expect(window.stats.sampleCount == 3)
    #expect(window.stats.averageMilliseconds == 20)
    #expect(window.stats.minimumMilliseconds == 10)
    #expect(window.stats.maximumMilliseconds == 30)
  }

  @Test func lossRatioIsLostOverAttempts() {
    var window = LatencyWindow(capacity: 4)
    window.add(result(10))
    window.add(result(nil))
    window.add(result(nil))
    window.add(result(10))

    #expect(window.stats.lossRatio == 0.5)
  }

  @Test func allLostGivesFullLossAndNoAverage() {
    var window = LatencyWindow(capacity: 3)
    window.add(result(nil))
    window.add(result(nil))

    #expect(window.stats.lossRatio == 1)
    #expect(window.stats.averageMilliseconds == nil)
  }

  @Test func oldestSampleIsEvictedAtCapacity() {
    var window = LatencyWindow(capacity: 2)
    window.add(result(nil))
    window.add(result(10))
    window.add(result(20))

    #expect(window.stats.sampleCount == 2)
    #expect(window.stats.lossRatio == 0)
    #expect(window.stats.averageMilliseconds == 15)
  }

  @Test func methodIsTheOneOfTheLatestSample() {
    var window = LatencyWindow(capacity: 3)
    window.add(result(10, method: .icmp))
    window.add(result(12, second: 1, method: .tcp))

    #expect(window.stats.method == .tcp)
  }
}
