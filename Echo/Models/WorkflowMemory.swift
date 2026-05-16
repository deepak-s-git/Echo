import Foundation

// MARK: - Workflow cluster

nonisolated enum WorkflowCluster: String, Codable, CaseIterable, Sendable {
    case coding
    case research
    case writing
    case design
    case communication
    case mixed

    var label: String {
        switch self {
        case .coding: return "Coding"
        case .research: return "Research"
        case .writing: return "Writing"
        case .design: return "Design"
        case .communication: return "Communication"
        case .mixed: return "Mixed workflow"
        }
    }

    var icon: String {
        switch self {
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .research: return "globe"
        case .writing: return "doc.text"
        case .design: return "paintbrush"
        case .communication: return "bubble.left.and.bubble.right"
        case .mixed: return "square.grid.2x2"
        }
    }
}

// MARK: - Session memory (derived, not persisted as blob)

nonisolated struct WorkflowMemory: Sendable {
    let session: Session
    let events: [ActivityEvent]
    let cluster: WorkflowCluster
    let phases: [WorkflowPhase]
    let appTransitions: [AppTransition]
    let browserContexts: [BrowserContextEntry]
    let interruptions: [WorkflowInterruption]
    let continuityScore: Double
    let restorePlan: WorkflowRestorePlan
}

nonisolated struct WorkflowPhase: Identifiable, Sendable, Equatable {
    let id: UUID
    let title: String
    let appName: String
    let bundleId: String
    let startedAt: Date
    let endedAt: Date
    let duration: TimeInterval
}

nonisolated struct AppTransition: Identifiable, Sendable, Equatable {
    let id: UUID
    let fromApp: String?
    let toApp: String
    let toBundleId: String
    let timestamp: Date
    let duration: TimeInterval
}

nonisolated struct BrowserContextEntry: Identifiable, Sendable, Equatable {
    let id: UUID
    let domain: String
    let title: String
    let urlHost: String
    let browser: String
    let capturedAt: Date
}

nonisolated struct WorkflowInterruption: Identifiable, Sendable, Equatable {
    let id: UUID
    let startedAt: Date
    let duration: TimeInterval
}

// MARK: - Restore

nonisolated struct WorkflowRestorePlan: Codable, Sendable, Equatable {
    var items: [RestoreItem]
    var createdAt: Date

    static let empty = WorkflowRestorePlan(items: [], createdAt: Date())

    static func decode(fromJSON json: String) -> WorkflowRestorePlan? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WorkflowRestorePlan.self, from: data)
    }
}

nonisolated struct RestoreItem: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var kind: RestoreKind
    var label: String
    var bundleId: String?
    var url: String?
    var path: String?
    var workingDirectory: String?

    nonisolated enum RestoreKind: String, Codable, Sendable {
        case application
        case url
        case folder
        case terminalDirectory
        case workspace
    }
}

nonisolated struct RestoreResult: Sendable {
    let succeeded: [RestoreItem]
    let failed: [(RestoreItem, String)]
}
