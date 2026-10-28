import SwiftUI

struct TrafficSection: View {
  let traffic: TrafficRate?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(Strings.trafficTitle)
        .font(.subheadline.weight(.semibold))
      row(Strings.download, systemImage: "arrow.down", bytes: traffic?.downloadBytesPerSecond)
      row(Strings.upload, systemImage: "arrow.up", bytes: traffic?.uploadBytesPerSecond)
    }
  }

  private func row(_ title: String, systemImage: String, bytes: Double?) -> some View {
    HStack {
      Label(title, systemImage: systemImage)
      Spacer()
      Text(bytes.map(format) ?? Strings.trafficUnavailable)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
    .font(.callout)
    .accessibilityElement(children: .combine)
  }

  private func format(_ bytesPerSecond: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .decimal) + "/s"
  }
}
