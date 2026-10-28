import Foundation
import Testing
@testable import OpenWifi

struct PresenceTrackerTests {
  private let start = Date(timeIntervalSince1970: 1_000_000)

  private func host(
    _ address: String = "192.0.2.10",
    mac: String? = nil,
    name: String? = nil,
    source: DataSource = .arp,
    responds: Bool = true,
  ) -> DiscoveredHost {
    DiscoveredHost(
      address: address,
      macAddress: mac,
      name: name,
      source: source,
      respondsToProbes: responds,
    )
  }

  private func at(_ sweep: Int) -> Date {
    start.addingTimeInterval(Double(sweep) * 60)
  }

  @Test func newRespondingHostIsActiveWithFirstSeenEqualLastSeen() {
    var tracker = PresenceTracker()
    tracker.recordSweep([host()], at: at(0))

    #expect(tracker.devices.count == 1)
    #expect(tracker.devices[0].presence == .active)
    #expect(tracker.devices[0].firstSeen == at(0))
    #expect(tracker.devices[0].lastSeen == at(0))
  }

  @Test func seenAgainKeepsFirstSeenAndMovesLastSeen() {
    var tracker = PresenceTracker()
    tracker.recordSweep([host()], at: at(0))
    tracker.recordSweep([host()], at: at(1))

    #expect(tracker.devices.count == 1)
    #expect(tracker.devices[0].firstSeen == at(0))
    #expect(tracker.devices[0].lastSeen == at(1))
  }

  @Test func staysActiveForTwoMissedSweepsAndGoesStaleOnThird() {
    var tracker = PresenceTracker()
    tracker.recordSweep([host()], at: at(0))
    tracker.recordSweep([], at: at(1))
    tracker.recordSweep([], at: at(2))
    #expect(tracker.devices[0].presence == .active)

    tracker.recordSweep([], at: at(3))
    #expect(tracker.devices[0].presence == .stale)
    #expect(tracker.devices[0].lastSeen == at(0))
  }

  @Test func staleDeviceBecomesActiveAgainAndMissCounterResets() {
    var tracker = PresenceTracker()
    tracker.recordSweep([host()], at: at(0))
    for sweep in 1...3 {
      tracker.recordSweep([], at: at(sweep))
    }
    tracker.recordSweep([host()], at: at(4))
    #expect(tracker.devices[0].presence == .active)

    tracker.recordSweep([], at: at(5))
    #expect(tracker.devices[0].presence == .active)
  }

  @Test func hostThatFiltersProbesIsUnknownNotActive() {
    var tracker = PresenceTracker()
    tracker.recordSweep([host(responds: false)], at: at(0))
    tracker.recordSweep([host(responds: false)], at: at(1))

    #expect(tracker.devices[0].presence == .unknown)
    #expect(tracker.devices[0].lastSeen == at(1))
  }

  @Test func activeDeviceThatStartsFilteringBecomesUnknown() {
    var tracker = PresenceTracker()
    tracker.recordSweep([host()], at: at(0))
    tracker.recordSweep([host(responds: false)], at: at(1))

    #expect(tracker.devices[0].presence == .unknown)
  }

  @Test func ipChangeWithSameMacIsOneDeviceWithBothAddresses() {
    var tracker = PresenceTracker()
    tracker.recordSweep([host("192.0.2.10", mac: "02:00:00:00:00:01")], at: at(0))
    tracker.recordSweep([host("192.0.2.77", mac: "02:00:00:00:00:01")], at: at(1))

    #expect(tracker.devices.count == 1)
    #expect(tracker.devices[0].addresses == ["192.0.2.10", "192.0.2.77"])
  }

  @Test func sameMacFromTwoSourcesInOneSweepIsOneDeviceWithMergedSources() {
    var tracker = PresenceTracker()
    tracker.recordSweep(
      [
        host(mac: "02:00:00:00:00:01", source: .arp),
        host(mac: "02:00:00:00:00:01", name: "Printer", source: .bonjour),
      ],
      at: at(0),
    )

    #expect(tracker.devices.count == 1)
    #expect(tracker.devices[0].sources == [.arp, .bonjour])
    #expect(tracker.devices[0].displayName == "Printer")
  }

  @Test func differentAddressesWithoutMacAreDifferentDevices() {
    var tracker = PresenceTracker()
    tracker.recordSweep([host("192.0.2.10"), host("192.0.2.11")], at: at(0))

    #expect(tracker.devices.count == 2)
  }

  @Test func laterNameDoesNotGetLostWhenNextSweepHasNoName() {
    var tracker = PresenceTracker()
    tracker.recordSweep([host(name: "Laptop")], at: at(0))
    tracker.recordSweep([host()], at: at(1))

    #expect(tracker.devices[0].displayName == "Laptop")
  }
}
