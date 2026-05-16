import SwiftUI
import Combine

/// UI-facing store for session list state.
/// Does not hold a database reference; receives updates from SessionEngine and loads via repository.
@MainActor
final class SessionStore: ObservableObject {

    @Published private(set) var recentSessions: [Session] = []
    @Published private(set) var selectedSession: Session?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: Error?

    private var repository: SessionRepository?

    var activeSession: Session? {
        recentSessions.first(where: \.isActive)
    }

    init() {}

    func configure(repository: SessionRepository) {
        self.repository = repository
    }

    func loadRecent() async {
        guard let repository else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            recentSessions = try await repository.fetchRecent()
        } catch {
            loadError = error
        }
    }

    func select(_ session: Session) { selectedSession = session }
    func deselect() { selectedSession = nil }

    func sessionDidStart(_ session: Session) {
        recentSessions.removeAll { $0.id == session.id }
        recentSessions.insert(session, at: 0)
    }

    func sessionDidResume(_ session: Session) {
        recentSessions.removeAll { $0.id == session.id }
        recentSessions.insert(session, at: 0)
    }

    func sessionDidUpdate(_ session: Session) {
        if let idx = recentSessions.firstIndex(where: { $0.id == session.id }) {
            recentSessions[idx] = session
        }
    }

    func sessionDidEnd(_ session: Session) {
        if let idx = recentSessions.firstIndex(where: { $0.id == session.id }) {
            recentSessions[idx] = session
        }
    }
}
