import SwiftUI

struct HeaderView: View {
  let model: MonitorViewModel

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(model.path?.networkName ?? Strings.unknownNetwork)
          .font(.headline)
        Text(model.path?.interfaceName ?? Strings.unknownInterface)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Label(model.health.label, systemImage: model.health.symbolName)
          .font(.subheadline)
        Text(updatedText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var updatedText: String {
    guard let date = model.lastUpdate else { return Strings.notUpdatedYet }
    return "\(Strings.updatedPrefix) \(date.formatted(date: .omitted, time: .standard))"
  }
}
