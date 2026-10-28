import Foundation

struct PresenceTracker: Sendable {
  static let staleAfterMissedSweeps = 3

  private(set) var devices: [NetworkDevice] = []
  private var missedSweeps: [UUID: Int] = [:]

  /// A host is "seen" in a sweep; it is `active` only if it also answers probes.
  /// Seen but silent to probes means `unknown`. Not seen for 3 sweeps means `stale`.
  mutating func recordSweep(_ hosts: [DiscoveredHost], at date: Date) {
    var seen = Set<UUID>()
    for host in hosts {
      if let index = devices.firstIndex(where: { isSameDevice($0, host) }) {
        devices[index] = merged(devices[index], with: host, at: date)
        seen.insert(devices[index].id)
      } else {
        let device = makeDevice(from: host, at: date)
        devices.append(device)
        seen.insert(device.id)
      }
    }
    for index in devices.indices where !seen.contains(devices[index].id) {
      let id = devices[index].id
      let missed = (missedSweeps[id] ?? 0) + 1
      missedSweeps[id] = missed
      if missed >= Self.staleAfterMissedSweeps {
        devices[index].presence = .stale
      }
    }
    for id in seen {
      missedSweeps[id] = 0
    }
  }

  // ponytail: identity is MAC, else IP. No hostname/Bonjour-service evidence yet; add after the discovery spike.
  private func isSameDevice(_ device: NetworkDevice, _ host: DiscoveredHost) -> Bool {
    if let mac = host.macAddress, let known = device.macAddress {
      return mac == known
    }
    return device.addresses.contains(host.address)
  }

  private func makeDevice(from host: DiscoveredHost, at date: Date) -> NetworkDevice {
    NetworkDevice(
      id: UUID(),
      displayName: host.name,
      addresses: [host.address],
      macAddress: host.macAddress,
      firstSeen: date,
      lastSeen: date,
      presence: host.respondsToProbes ? .active : .unknown,
      sources: [host.source],
    )
  }

  // ponytail: addresses grow on every IP change; prune when persistence lands.
  private func merged(_ device: NetworkDevice, with host: DiscoveredHost, at date: Date) -> NetworkDevice {
    var updated = device
    let alreadySeenThisSweep = device.lastSeen == date
    updated.lastSeen = date
    if host.respondsToProbes {
      updated.presence = .active
    } else if !alreadySeenThisSweep {
      updated.presence = .unknown
    }
    updated.displayName = host.name ?? device.displayName
    updated.macAddress = host.macAddress ?? device.macAddress
    updated.sources.insert(host.source)
    if !updated.addresses.contains(host.address) {
      updated.addresses.append(host.address)
    }
    return updated
  }
}
