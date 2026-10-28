import SwiftUI

struct LatencyRow: View {
  let title: String
  let stats: LatencyStats

  var body: some View {
    HStack {
      Text(title)
      Spacer()
      Text(summary)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
    .font(.callout)
    .accessibilityElement(children: .combine)
  }

  private var summary: String {
    guard let average = stats.averageMilliseconds else { return Strings.noReply }
    let milliseconds = average.formatted(.number.precision(.fractionLength(0)))
    let loss = stats.lossRatio.formatted(.percent.precision(.fractionLength(0)))
    let method = stats.method?.label ?? ""
    return "\(milliseconds) ms · \(method) · \(loss) \(Strings.lossSuffix)"
  }
}
