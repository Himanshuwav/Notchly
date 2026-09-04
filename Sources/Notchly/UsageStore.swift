import Foundation
import Combine
import AppKit

@MainActor
final class UsageStore: ObservableObject {
    @Published var states: [ProviderID: ProviderState] = [:]
    @Published var expanded: Bool = false

    private var timer: Timer?
    private var providers: [UsageProvider]
    private var refreshInterval: TimeInterval

    init(refreshInterval: TimeInterval = 90) {
        self.refreshInterval = refreshInterval
        self.providers = [ClaudeProvider(), CodexProvider(), FactoryProvider(), GeminiProvider()]
        for id in ProviderID.allCases {
            states[id] = ProviderState(id: id, status: .reading)
        }
        restoreCachedReadings()
    }

    func start() {
        Task { await refreshAll() }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAll()
            }
        }
        // Refresh when the Mac wakes up.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: OperationQueue.main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refreshAll() {
        for provider in providers {
            let id = provider.id
            Task { [weak self] in
                let fresh = await provider.refresh()
                print("[Notchly] \(id.rawValue): status=\(fresh.status) windows=\(fresh.windows.map { "\($0.label) \(Int($0.usedPercent))%" }) note=\(fresh.note)")
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.states[id] = fresh
                    self.cacheReading(fresh)
                }
            }
        }
    }

    /// Keep the last good numbers around so a dead network still shows something.
    private func cacheReading(_ state: ProviderState) {
        guard state.status == .ok else { return }
        guard let data = try? JSONEncoder().encode(CachedReading(from: state)) else { return }
        UserDefaults.standard.set(data, forKey: "cached.\(state.id.rawValue)")
    }

    private func restoreCachedReadings() {
        for id in ProviderID.allCases {
            guard let data = UserDefaults.standard.data(forKey: "cached.\(id.rawValue)"),
                  let cached = try? JSONDecoder().decode(CachedReading.self, from: data) else { continue }
            var state = ProviderState(id: id, status: .ok)
            state.windows = cached.windows
            state.note = cached.note
            state.updatedAt = cached.updatedAt
            states[id] = state
        }
    }

    private struct CachedReading: Codable {
        var windows: [UsageWindow]
        var note: String
        var updatedAt: Date?

        init(from state: ProviderState) {
            self.windows = state.windows
            self.note = state.note
            self.updatedAt = state.updatedAt
        }
    }
}


