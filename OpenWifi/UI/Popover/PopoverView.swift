import SwiftUI

struct PopoverView: View {
  let model: MonitorViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HeaderView(model: model)
      Divider()
      HealthSection(gateway: model.gatewayStats, external: model.externalStats)
      Divider()
      TrafficSection(traffic: model.traffic)
      Divider()
      DeviceListSection(devices: model.devices)
      Divider()
      ActionsBar(model: model)
      if let notice = model.notice {
        Text(notice)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .frame(width: 360)
  }
}
