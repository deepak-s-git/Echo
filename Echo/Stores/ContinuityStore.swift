import SwiftUI
import Combine

@MainActor
final class ContinuityStore: ObservableObject {

    @Published private(set) var interruptedSessions: [Session] = []
    @Published private(set) var previousSession: Session?

    private var repository: SessionRepository?

    func configure(repository: SessionRepository) {
        self.repository = repository
    }

    func refresh(activeSession: Session?, recent: [Session]) async {
        guard let repository else { return }
        do {
            interruptedSessions = try await repository.fetchInterrupted()
        } catch {
            interruptedSessions = []
        }

        previousSession = recent
            .filter { !$0.isActive && $0.id != activeSession?.id }
            .first
    }

    func canResumeCurrent(active: Session?) -> Bool {
        active?.isActive == true
    }
}
