import Foundation
import Testing
@testable import OpenWifi

struct TrafficRateCalculatorTests {
  private let start = Date(timeIntervalSince1970: 1_000_000)

  private func counters(
    received: UInt64,
    sent: UInt64,
    second: Double,
    interface: String = "en0",
    bits: Int = 64,
  ) -> InterfaceCounters {
    InterfaceCounters(
      interfaceName: interface,
      timestamp: start.addingTimeInterval(second),
      receivedBytes: received,
      sentBytes: sent,
      counterBits: bits,
    )
  }

  @Test func firstSampleOnlySetsBaseline() {
    var calculator = TrafficRateCalculator()

    #expect(calculator.recordCounters(counters(received: 100, sent: 50, second: 0)) == nil)
  }

  @Test func rateIsDeltaOverElapsedSeconds() {
    var calculator = TrafficRateCalculator()
    _ = calculator.recordCounters(counters(received: 1_000, sent: 500, second: 0))
    let rate = calculator.recordCounters(counters(received: 3_000, sent: 1_000, second: 2))

    #expect(rate?.downloadBytesPerSecond == 1_000)
    #expect(rate?.uploadBytesPerSecond == 250)
    #expect(rate?.interfaceName == "en0")
  }

  @Test func counterResetDropsSampleAndRebaselines() {
    var calculator = TrafficRateCalculator()
    _ = calculator.recordCounters(counters(received: 10_000_000_000, sent: 10_000_000_000, second: 0))

    #expect(calculator.recordCounters(counters(received: 100, sent: 100, second: 1)) == nil)

    let rate = calculator.recordCounters(counters(received: 1_100, sent: 600, second: 2))
    #expect(rate?.downloadBytesPerSecond == 1_000)
    #expect(rate?.uploadBytesPerSecond == 500)
  }

  @Test func plausible32BitRolloverIsCountedAcrossTheWrap() {
    var calculator = TrafficRateCalculator()
    let max32 = UInt64(UInt32.max)
    _ = calculator.recordCounters(counters(received: max32 - 255, sent: 0, second: 0, bits: 32))
    let rate = calculator.recordCounters(counters(received: 500, sent: 0, second: 1, bits: 32))

    // 255 bytes to the wrap, 1 for the wrap itself, 500 after it.
    #expect(rate?.downloadBytesPerSecond == 756)
  }

  @Test func implausible32BitDropIsTreatedAsResetNotRollover() {
    var calculator = TrafficRateCalculator()
    _ = calculator.recordCounters(counters(received: 3_000_000_000, sent: 0, second: 0, bits: 32))

    #expect(calculator.recordCounters(counters(received: 100, sent: 0, second: 1, bits: 32)) == nil)
  }

  @Test func plausible64BitRolloverIsCountedAcrossTheWrap() {
    var calculator = TrafficRateCalculator()
    _ = calculator.recordCounters(counters(received: UInt64.max - 99, sent: 0, second: 0))
    let rate = calculator.recordCounters(counters(received: 400, sent: 0, second: 1))

    #expect(rate?.downloadBytesPerSecond == 500)
  }

  @Test func interfaceSwitchDropsSampleAndRebaselines() {
    var calculator = TrafficRateCalculator()
    _ = calculator.recordCounters(counters(received: 1_000, sent: 1_000, second: 0, interface: "en0"))

    #expect(
      calculator.recordCounters(counters(received: 9_000_000, sent: 9_000_000, second: 1, interface: "en1")) == nil
    )

    let rate = calculator.recordCounters(
      counters(received: 9_001_000, sent: 9_000_500, second: 2, interface: "en1")
    )
    #expect(rate?.interfaceName == "en1")
    #expect(rate?.downloadBytesPerSecond == 1_000)
  }

  @Test func nonIncreasingTimestampIsIgnoredAndKeepsBaseline() {
    var calculator = TrafficRateCalculator()
    _ = calculator.recordCounters(counters(received: 1_000, sent: 0, second: 5))

    #expect(calculator.recordCounters(counters(received: 2_000, sent: 0, second: 5)) == nil)

    let rate = calculator.recordCounters(counters(received: 3_000, sent: 0, second: 6))
    #expect(rate?.downloadBytesPerSecond == 2_000)
  }
}
