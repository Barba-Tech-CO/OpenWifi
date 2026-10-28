struct NetworkPathState: Sendable, Equatable {
  let interfaceName: String?
  let networkName: String?
  let gatewayAddress: String?
  let isSatisfied: Bool
}
