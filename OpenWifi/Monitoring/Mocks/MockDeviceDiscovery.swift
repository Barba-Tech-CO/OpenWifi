/// Deterministic fake: the phone is present in the first two sweeps only,
/// so "no response" shows up after three more sweeps.
actor MockDeviceDiscovery: DeviceDiscovery {
  private var sweeps = 0

  func sweep() -> [DiscoveredHost] {
    sweeps += 1
    var hosts = [
      DiscoveredHost(
        address: "192.0.2.10",
        macAddress: "02:00:00:00:00:10",
        name: "Mock Laptop",
        source: .bonjour,
        respondsToProbes: true,
      ),
      DiscoveredHost(
        address: "192.0.2.20",
        macAddress: "02:00:00:00:00:20",
        name: "Mock Printer",
        source: .bonjour,
        respondsToProbes: true,
      ),
      DiscoveredHost(
        address: "192.0.2.30",
        macAddress: "02:00:00:00:00:30",
        name: nil,
        source: .arp,
        respondsToProbes: false,
      ),
    ]
    if sweeps <= 2 {
      hosts.append(
        DiscoveredHost(
          address: "192.0.2.40",
          macAddress: "02:00:00:00:00:40",
          name: "Mock Phone",
          source: .arp,
          respondsToProbes: true,
        )
      )
    }
    return hosts
  }
}
