import SwiftUI

struct MenuView: View {
    @Bindable var model: CounterModel

    var body: some View {
        VStack(spacing: 12) {
            // Full total + offline dot
            HStack(spacing: 6) {
                Text(NumberFormat.full(model.total))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(.snappy, value: model.total)
                if model.offline {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                        .help("Couldn't reach the server — showing last known total")
                }
            }

            Button {
                Task { await model.click() }
            } label: {
                Text("Click")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canClickNow)

            VStack(spacing: 2) {
                Text("You've contributed \(model.yourClicks) click\(model.yourClicks == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CountdownText(nextClickAt: model.nextClickAt)
            }

            SparklineView(points: model.history)
                .padding(.horizontal, 2)

            Divider()

            Toggle("Milestone notifications (every 100K)", isOn: $model.notificationsEnabled)
                .font(.caption)
                .toggleStyle(.checkbox)

            Button("Quit") { NSApp.terminate(nil) }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 240)
        // MenuBarExtra(.window) content appears/disappears with the panel —
        // this is what flips the poll cadence between 60s and 10s.
        .onAppear {
            model.menuIsOpen = true
            Task { await model.refresh(includeHistory: true) }
        }
        .onDisappear { model.menuIsOpen = false }
    }
}

/// Live once-a-second countdown to the next allowed click.
/// TimelineView re-evaluates on a schedule without a manual Timer.
private struct CountdownText: View {
    let nextClickAt: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let next = nextClickAt, next > context.date {
                let s = Int(next.timeIntervalSince(context.date).rounded(.up))
                Text("Next click in \(s / 60):\(String(format: "%02d", s % 60))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("Ready to click!")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }
}
