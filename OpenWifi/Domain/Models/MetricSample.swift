import Foundation

struct MetricSample: Sendable, Equatable {
  let timestamp: Date
  let value: Double
  let unit: String
  let source: DataSource
  /// nil when the metric does not come from a probe (for example interface counters).
  let method: ProbeMethod?
  let isEstimated: Bool
}
