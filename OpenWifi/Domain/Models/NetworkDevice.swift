import Foundation

struct NetworkDevice: Identifiable, Sendable, Equatable {
  let id: UUID
  var displayName: String?
  var addresses: [String]
  var macAddress: String?
  var firstSeen: Date
  var lastSeen: Date
  var presence: PresenceState
  var sources: Set<DataSource>
}
