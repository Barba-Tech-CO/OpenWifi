protocol NetworkPathObserver: Sendable {
  func pathStates() -> AsyncStream<NetworkPathState>
}
