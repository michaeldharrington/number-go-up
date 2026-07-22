import AppKit
import Observation
import SwiftUI
import UserNotifications

@MainActor
@Observable
final class CounterModel {
    // MARK: State

    private(set) var total: Int
    private(set) var yourClicks: Int
    private(set) var nextClickAt: Date?
    private(set) var history: [HistoryPoint] = []
    /// True when the most recent fetch failed — drives the offline dot.
    private(set) var offline = false
    /// True while a click is in flight (button disabled).
    private(set) var clicking = false

    var menuIsOpen = false { didSet { restartPolling() } }

    var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "notificationsEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "notificationsEnabled")
            if newValue { requestNotificationPermission() }
        }
    }

    var canClickNow: Bool {
        guard !clicking else { return false }
        guard let next = nextClickAt else { return true }
        return next <= Date()
    }

    private let api = APIClient()
    private var pollTask: Task<Void, Never>?
    /// System asleep / session inactive — polling fully paused.
    private var suspended = false

    // MARK: Lifecycle

    init() {
        // Seed from the last known value so the menu bar isn't blank while
        // the first fetch is in flight (or the network is down).
        total = UserDefaults.standard.integer(forKey: "lastTotal")
        yourClicks = UserDefaults.standard.integer(forKey: "lastYourClicks")
        observeSleepWake()
        restartPolling()
    }

    // MARK: Polling

    /// One long-lived task; cadence depends on whether the menu is open.
    /// Cancelled and rebuilt whenever open-state or suspend-state changes.
    private func restartPolling() {
        pollTask?.cancel()
        guard !suspended else { pollTask = nil; return }
        let interval = menuIsOpen ? AppConfig.pollOpen : AppConfig.pollClosed
        let wantHistory = menuIsOpen
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(includeHistory: wantHistory)
                try? await Task.sleep(for: interval)
            }
        }
    }

    func refresh(includeHistory: Bool = false) async {
        do {
            let res = try await api.fetchCount()
            apply(res)
            if includeHistory {
                history = try await api.fetchHistory()
            }
            offline = false
        } catch {
            offline = true
        }
    }

    /// Menu bar apps never "background" like windowed apps do, so the
    /// closest meaningful signal is system sleep / fast-user-switching:
    /// nobody can see the title, stop polling entirely.
    private func observeSleepWake() {
        let ws = NSWorkspace.shared.notificationCenter
        let setSuspended = { [weak self] (value: Bool) in
            Task { @MainActor in
                self?.suspended = value
                self?.restartPolling()
            }
        }
        let pause: @Sendable (Notification) -> Void = { _ in _ = setSuspended(true) }
        let resume: @Sendable (Notification) -> Void = { _ in _ = setSuspended(false) }
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil, using: pause)
        ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: nil, using: pause)
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil, using: resume)
        ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: nil, using: resume)
    }

    // MARK: Clicking

    /// Optimistic update: bump the displayed number immediately, then
    /// reconcile with whatever the server says.
    ///   - success  → server response wins outright (it may be higher than
    ///     our +1 if others clicked in the meantime; never "snaps down"
    ///     visually because the server total already includes our click).
    ///   - 429      → our optimistic +1 was wrong; refetch /count and let
    ///     the server value replace it, and show the countdown.
    ///   - network error → also refetch; if that fails too, roll back the
    ///     +1 locally so we never display a phantom click.
    func click() async {
        guard canClickNow else { return }
        clicking = true
        let optimisticTotal = total
        total += 1
        defer { clicking = false }

        do {
            switch try await api.click() {
            case .success(let res):
                apply(res)
                offline = false
            case .rateLimited(let next):
                nextClickAt = next
                await refresh() // snap back to the authoritative total
            }
        } catch {
            offline = true
            total = optimisticTotal // roll back; refresh() may fix it later
            await refresh()
        }
    }

    // MARK: Reconciliation + milestones

    private func apply(_ res: CountResponse) {
        maybeNotifyMilestone(old: total, new: res.total)
        total = res.total
        yourClicks = res.yourClicks
        nextClickAt = res.nextClickAt
        UserDefaults.standard.set(res.total, forKey: "lastTotal")
        UserDefaults.standard.set(res.yourClicks, forKey: "lastYourClicks")
    }

    private func maybeNotifyMilestone(old: Int, new: Int) {
        guard notificationsEnabled,
              new / AppConfig.milestoneStep > old / AppConfig.milestoneStep,
              // UNUserNotificationCenter aborts outside a real .app bundle
              // (e.g. `swift run`), so guard on bundle identity.
              Bundle.main.bundleIdentifier != nil
        else { return }
        let milestone = (new / AppConfig.milestoneStep) * AppConfig.milestoneStep
        let content = UNMutableNotificationContent()
        content.title = "Milestone!"
        content.body = "The global counter just passed \(NumberFormat.full(milestone))."
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "milestone-\(milestone)",
                                  content: content, trigger: nil))
    }

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
