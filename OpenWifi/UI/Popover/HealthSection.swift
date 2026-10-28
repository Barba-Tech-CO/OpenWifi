import SwiftUI

struct HealthSection: View {
  let gateway: LatencyStats
  let external: LatencyStats

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(Strings.healthTitle)
        .font(.subheadline.weight(.semibold))
      LatencyRow(title: Strings.gateway, stats: gateway)
      LatencyRow(title: Strings.internet, stats: external)
    }
  }
}
