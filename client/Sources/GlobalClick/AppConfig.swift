import Foundation

enum AppConfig {
    /// The one place to swap servers.
    /// Local dev:  http://localhost:8787   (npx wrangler dev in /server)
    /// Production: https://global-click-counter.<your-subdomain>.workers.dev
    static let baseURL = URL(string: "http://localhost:8787")!

    /// Poll cadence, seconds.
    static let pollClosed: Duration = .seconds(60)
    static let pollOpen: Duration = .seconds(10)

    /// Fire a notification each time the global total crosses a multiple of this.
    static let milestoneStep = 100_000
}
