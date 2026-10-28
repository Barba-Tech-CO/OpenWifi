# OpenWifi

Native, privacy-first macOS menu bar network monitor (Swift + SwiftUI, macOS 14+).

## Status

M0 skeleton, mock data. The popover layout is real; every network capability (latency probes, interface counters, device discovery, path observer) is a `Mock*` behind a protocol. Nothing probes your network yet. Router integration is a protocol only.

The pure logic is real and unit-tested: presence tracking, RTT/loss window, byte-counter deltas (reset, interface switch, rollover).

## Build

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate && xcodebuild -scheme OpenWifi -destination 'platform=macOS' build test
```

`OpenWifi.xcodeproj` is generated from `project.yml` and not committed.

## Privacy

Local-first: no account, no backend, no analytics, no telemetry. OpenWifi will talk only to your local network and to connectivity-check targets you configure. Router integration, when it exists, is optional and read-only.

## License

MIT, see [LICENSE](LICENSE).
