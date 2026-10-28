struct MockNetworkPathObserver: NetworkPathObserver {
  static let gatewayAddress = "192.0.2.1"

  func pathStates() -> AsyncStream<NetworkPathState> {
    AsyncStream { continuation in
      continuation.yield(
        NetworkPathState(
          interfaceName: "en0",
          networkName: "Mock Network",
          gatewayAddress: Self.gatewayAddress,
          isSatisfied: true,
        )
      )
      continuation.finish()
    }
  }
}
