import SwiftUI

struct DeviceRow: View {
  let device: NetworkDevice

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(device.displayName ?? Strings.noName)
          .font(.callout)
        Text(device.addresses.joined(separator: ", "))
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("\(Strings.seenSinceEstimated): \(device.firstSeen.formatted(date: .omitted, time: .shortened))")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text(device.presence.label)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }
}
