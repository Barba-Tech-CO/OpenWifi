import SwiftUI

@main
struct OpenWifiApp: App {
  @State private var model: MonitorViewModel

  // M0 dev composition: every port is a Mock*. Swap in real implementations after the spikes.
  init() {
    let model = MonitorViewModel(
      probe: MockLatencyProbe(),
      sampler: MockInterfaceTrafficSampler(),
      discovery: MockDeviceDiscovery(),
      pathObserver: MockNetworkPathObserver(),
      externalTarget: "198.51.100.1",
      sampleInterval: .seconds(2),
      sweepInterval: .seconds(5),
      notice: Strings.mockNotice,
    )
    model.start()
    _model = State(initialValue: model)
  }

  var body: some Scene {
    MenuBarExtra {
      PopoverView(model: model)
    } label: {
      Image(systemName: model.health.symbolName)
        .accessibilityLabel("\(Strings.appName): \(model.health.label)")
    }
    .menuBarExtraStyle(.window)
  }
}
