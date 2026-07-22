import SwiftUI

@main
struct GlobalClickApp: App {
    @State private var model = CounterModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            // The abbreviated global total lives right in the menu bar.
            Text(NumberFormat.abbreviated(model.total))
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}
