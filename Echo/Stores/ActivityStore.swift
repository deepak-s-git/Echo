import SwiftUI
import Combine

@MainActor
final class ActivityStore: ObservableObject {

    @Published private(set) var currentSession: Session?
    @Published private(set) var recentEvents: [ActivityEvent] = []
    @Published private(set) var sessionDuration: TimeInterval = 0
    @Published private(set) var focusScore: Double = 0

    private var durationTask: Task<Void, Never>?

    init() {}

    deinit { durationTask?.cancel() }

    func sessionDidStart(_ session: Session) {
        currentSession = session
        recentEvents.removeAll()
        sessionDuration = 0
        focusScore = 0
        startDurationTimer()
    }

    func sessionDidEnd(_ session: Session) {
        durationTask?.cancel()
        durationTask = nil
        currentSession = nil
        focusScore = session.focusScore
    }

    func append(_ event: ActivityEvent) {
        recentEvents.append(event)
        if recentEvents.count > EchoConfig.maxLiveEvents {
            recentEvents.removeFirst()
        }
    }

    private func startDurationTimer() {
        durationTask?.cancel()
        durationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let session = self?.currentSession else { continue }
                self?.sessionDuration = Date().timeIntervalSince(session.startedAt)
            }
        }
    }
}
