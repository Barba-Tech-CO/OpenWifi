struct TrafficRateCalculator: Sendable {
  private var previous: InterfaceCounters?

  /// Returns nil for the baseline sample, an interface switch, a counter reset
  /// and a non-increasing timestamp; the sample is dropped, never guessed.
  mutating func recordCounters(_ current: InterfaceCounters) -> TrafficRate? {
    guard let last = previous, last.interfaceName == current.interfaceName else {
      previous = current
      return nil
    }
    let elapsed = current.timestamp.timeIntervalSince(last.timestamp)
    guard elapsed > 0 else { return nil }
    previous = current

    let bits = current.counterBits
    guard
      let received = delta(from: last.receivedBytes, to: current.receivedBytes, bits: bits, elapsed: elapsed),
      let sent = delta(from: last.sentBytes, to: current.sentBytes, bits: bits, elapsed: elapsed)
    else { return nil }

    return TrafficRate(
      interfaceName: current.interfaceName,
      timestamp: current.timestamp,
      downloadBytesPerSecond: Double(received) / elapsed,
      uploadBytesPerSecond: Double(sent) / elapsed,
    )
  }

  /// A drop is a rollover only when the bytes across the wrap fit a plausible rate;
  /// otherwise it is a reset. ponytail: 500 MB/s ceiling (~4 Gbps) can misread a rollover
  /// on a sustained 10GbE link as a reset, costing one sample; tune after the sampler spike.
  private func delta(from previous: UInt64, to current: UInt64, bits: Int, elapsed: Double) -> UInt64? {
    if current >= previous { return current - previous }
    let maximum = bits >= 64 ? UInt64.max : (UInt64(1) << UInt64(bits)) - 1
    let wrapped = (maximum - previous) + current + 1
    return Double(wrapped) / elapsed <= 500_000_000 ? wrapped : nil
  }
}
