extension NetworkHealth {
  var symbolName: String {
    switch self {
    case .normal: "wifi"
    case .degraded: "wifi.exclamationmark"
    case .offline: "wifi.slash"
    case .unknown: "questionmark.circle"
    }
  }

  var label: String {
    switch self {
    case .normal: Strings.healthNormal
    case .degraded: Strings.healthDegraded
    case .offline: Strings.healthOffline
    case .unknown: Strings.healthUnknown
    }
  }
}

extension PresenceState {
  var label: String {
    switch self {
    case .active: Strings.detected
    case .unknown: Strings.unknown
    case .stale: Strings.noResponse
    }
  }
}

extension ProbeMethod {
  var label: String {
    switch self {
    case .icmp: "ICMP"
    case .tcp: "TCP"
    }
  }
}
