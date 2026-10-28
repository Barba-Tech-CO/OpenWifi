import AppKit
import SwiftUI

struct ActionsBar: View {
  let model: MonitorViewModel

  var body: some View {
    HStack {
      Button(Strings.refresh, systemImage: "arrow.clockwise") {
        model.refresh()
      }
      .accessibilityLabel(Strings.refresh)
      Button(
        model.isPaused ? Strings.resume : Strings.pause,
        systemImage: model.isPaused ? "play.fill" : "pause.fill"
      ) {
        model.togglePause()
      }
      .accessibilityLabel(model.isPaused ? Strings.resume : Strings.pause)
      Spacer()
      Button(Strings.quit, systemImage: "power") {
        NSApplication.shared.terminate(nil)
      }
      .accessibilityLabel(Strings.quit)
    }
    .labelStyle(.iconOnly)
    .buttonStyle(.borderless)
  }
}
