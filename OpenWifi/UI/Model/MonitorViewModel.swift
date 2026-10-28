import Foundation
import Observation

@MainActor
@Observable
final class MonitorViewModel {
  private(set) var path: NetworkPathState?
  private(set) var health = NetworkHealth.unknown
  private(set) var gatewayStats = LatencyStats.empty
  private(set) var externalStats = LatencyStats.empty
  private(set) var traffic: TrafficRate?
  private(set) var devices: [NetworkDevice] = []
  private(set) var lastUpdate: Date?
  private(set) var isPaused = false
  let notice: String?

  @ObservationIgnored private let probe: any LatencyProbe
  @ObservationIgnored private let sampler: any InterfaceTrafficSampler
  @ObservationIgnored private let discovery: any DeviceDiscovery
  @ObservationIgnored private let pathObserver: any NetworkPathObserver
  @ObservationIgnored private let externalTarget: String
  @ObservationIgnored private let sampleInterval: Duration
  @ObservationIgnored private let sweepInterval: Duration
  @ObservationIgnored private var gatewayWindow = LatencyWindow(capacity: 30)
  @ObservationIgnored private var externalWindow = LatencyWindow(capacity: 30)
  @ObservationIgnored private var trafficCalculator = TrafficRateCalculator()
  @ObservationIgnored private var presenceTracker = PresenceTracker()
  @ObservationIgnored private var tasks: [Task<Void, Never>] = []

  init(
    probe: any LatencyProbe,
    sampler: any InterfaceTrafficSampler,
    discovery: any DeviceDiscovery,
    pathObserver: any NetworkPathObserver,
    externalTarget: String,
    sampleInterval: Duration,
    sweepInterval: Duration,
    notice: String?,
  ) {
    self.probe = probe
    self.sampler = sampler
    self.discovery = discovery
    self.pathObserver = pathObserver
    self.externalTarget = externalTarget
    self.sampleInterval = sampleInterval
    self.sweepInterval = sweepInterval
    self.notice = notice
  }

  func start() {
    guard tasks.isEmpty else { return }
    isPaused = false
    tasks = [
      Task { await observePath() },
      Task { await repeatForever(every: sampleInterval) { await self.sampleOnce() } },
      Task { await repeatForever(every: sweepInterval) { await self.sweepOnce() } },
    ]
  }

  func togglePause() {
    if isPaused {
      start()
    } else {
      tasks.forEach { $0.cancel() }
      tasks = []
      isPaused = true
    }
  }

  func refresh() {
    Task {
      await sampleOnce()
      await sweepOnce()
    }
  }

  private func observePath() async {
    for await state in pathObserver.pathStates() {
      path = state
    }
  }

  private func repeatForever(every interval: Duration, _ work: () async -> Void) async {
    while !Task.isCancelled {
      await work()
      try? await Task.sleep(for: interval)
    }
  }

  private func sampleOnce() async {
    if let gateway = path?.gatewayAddress {
      gatewayWindow.add(await probe.measureRoundTrip(to: gateway))
      gatewayStats = gatewayWindow.stats
    }
    externalWindow.add(await probe.measureRoundTrip(to: externalTarget))
    externalStats = externalWindow.stats
    health = NetworkHealth(gateway: gatewayStats, external: externalStats)

    do {
      let counters = try await sampler.readCounters()
      traffic = trafficCalculator.recordCounters(counters) ?? traffic
    } catch {
      traffic = nil
    }
    lastUpdate = Date()
  }

  private func sweepOnce() async {
    presenceTracker.recordSweep(await discovery.sweep(), at: Date())
    devices = presenceTracker.devices
  }
}
