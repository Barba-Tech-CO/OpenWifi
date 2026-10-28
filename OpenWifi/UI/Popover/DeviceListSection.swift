import SwiftUI

struct DeviceListSection: View {
  let devices: [NetworkDevice]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("\(Strings.devicesTitle) (\(detectedCount))")
        .font(.subheadline.weight(.semibold))
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(devices) { device in
            DeviceRow(device: device)
          }
        }
      }
      .frame(maxHeight: 180)
    }
  }

  private var detectedCount: Int {
    devices.filter { $0.presence == .active }.count
  }
}
