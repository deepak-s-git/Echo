import SwiftUI

/// UI-facing store for session list state.
/// Does not hold a database reference; receives updates from SessionEngine and loads via repository.
@MainActor
final class SessionStore: ObservableObject {

    @Published private(set) var recentSessions: [Session] = []
    @Published private(set) var selectedSession: Session?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var loadError: Error?

    private let repository: SessionRepository

    init(repository: SessionRepository) {
        self.repository = repository
    }

    // MARK: - Load

    func loadRecent() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            recentSessions = try await repository.fetchRecent()
        } catch {
            loadError = error
        }
    }

    // MARK: - Selection

    func select(_ session: Session) { selectedSession = session }
    func deselect() { selectedSession = nil }

    // MARK: - Engine callbacks (called by SessionEngine)

    func sessionDidStart(_ session: Session) {
        recentSessions.insert(session, at: 0)
    }

    func sessionDidEnd(_ session: Session) {
        if let idx = recentSessions.firstIndex(where: { $0.id == session.id }) {
            recentSessions[idx] = session
        }
    }
}
