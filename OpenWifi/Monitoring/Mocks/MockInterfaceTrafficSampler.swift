import Foundation

/// Deterministic fake: counters grow by a fixed amount per read.
actor MockInterfaceTrafficSampler: InterfaceTrafficSampler {
  private var reads: UInt64 = 0

  func readCounters() -> InterfaceCounters {
    reads += 1
    return InterfaceCounters(
      interfaceName: "en0",
      timestamp: Date(),
      receivedBytes: reads * 2_500_000,
      sentBytes: reads * 300_000,
      counterBits: 64,
    )
  }
}
