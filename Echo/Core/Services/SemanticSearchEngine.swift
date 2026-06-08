import Foundation
import NaturalLanguage
import Accelerate

actor SemanticSearchEngine {
    static let shared = SemanticSearchEngine()

    private let embeddingModel: NLEmbedding? = {
        NLEmbedding.sentenceEmbedding(for: .english)
    }()

    private init() {}

    func generateChunks(session: Session, activities: [ActivityEvent]) -> [(kind: String, document: String)] {
        var chunks: [(kind: String, document: String)] = []

        // 1. Session Summary Chunk
        var summaryText = "Session Title: \(session.title ?? "Untitled Session")"
        if let cluster = session.workflowCluster {
            summaryText += "\nCluster: \(cluster)"
        }
        let apps = Set(activities.map(\.appName)).joined(separator: ", ")
        if !apps.isEmpty {
            summaryText += "\nApplications used: \(apps)"
        }
        chunks.append((kind: "summary", document: summaryText))

        // 2. Browser Tab Chunks
        var seenURLs = Set<String>()
        for event in activities {
            guard event.type == .browserTab || BrowserContextService.isBrowser(event.appBundleId) else { continue }
            guard let url = event.url, !url.isEmpty else { continue }
            let lowerURL = url.lowercased()
            guard seenURLs.insert(lowerURL).inserted else { continue }
            
            let title = event.windowTitle ?? URL(string: url)?.host ?? "Webpage"
            let text = "Webpage: \(title)\nURL: \(url)"
            chunks.append((kind: "browser", document: text))
        }

        // 3. Terminal Command Chunks
        var seenCommands = Set<String>()
        for event in activities {
            guard event.type == .terminalCommand || isTerminal(event.appBundleId) else { continue }
            guard let cmd = event.windowTitle, !cmd.isEmpty else { continue }
            guard seenCommands.insert(cmd).inserted else { continue }
            
            let text = "Terminal command: \(cmd)"
            chunks.append((kind: "terminal", document: text))
        }

        // 4. File Chunks
        var seenFiles = Set<String>()
        for event in activities {
            guard event.type == .fileAccess || event.appBundleId == "com.apple.Preview" else { continue }
            guard let path = event.url ?? event.windowTitle, !path.isEmpty else { continue }
            let lowerPath = path.lowercased()
            guard seenFiles.insert(lowerPath).inserted else { continue }
            
            let filename = (path as NSString).lastPathComponent
            let text = "File: \(filename)\nPath: \(path)"
            chunks.append((kind: "file", document: text))
        }

        return chunks
    }

    func computeEmbedding(for text: String) -> [Float]? {
        guard let model = embeddingModel else { return nil }
        return model.vector(for: text)?.map { Float($0) }
    }

    func cosineSimilarity(a: [Float], b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dotProduct: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        
        var magnitudeASquared: Float = 0
        vDSP_svesq(a, 1, &magnitudeASquared, vDSP_Length(a.count))
        
        var magnitudeBSquared: Float = 0
        vDSP_svesq(b, 1, &magnitudeBSquared, vDSP_Length(b.count))
        
        guard magnitudeASquared > 0, magnitudeBSquared > 0 else { return 0 }
        return dotProduct / (sqrt(magnitudeASquared) * sqrt(magnitudeBSquared))
    }

    func indexPendingSessions(repository: SessionRepository) async {
        do {
            let pendingIds = try await repository.fetchUnindexedSessionIds()
            guard !pendingIds.isEmpty else { return }
            print("[SemanticSearchEngine] Found \(pendingIds.count) unindexed sessions")
            
            for id in pendingIds {
                guard let session = try await repository.fetch(id: id) else { continue }
                let activities = try await repository.fetchActivities(sessionId: id)
                let chunks = generateChunks(session: session, activities: activities)
                
                var embeddings: [SessionEmbedding] = []
                for chunk in chunks {
                    if let vector = computeEmbedding(for: chunk.document) {
                        let embedding = SessionEmbedding(
                            id: UUID().uuidString,
                            sessionId: id.uuidString,
                            chunkKind: chunk.kind,
                            vector: vector,
                            document: chunk.document
                        )
                        embeddings.append(embedding)
                    }
                }
                
                if !embeddings.isEmpty {
                    try await repository.saveEmbeddings(embeddings)
                }
            }
            print("[SemanticSearchEngine] Indexing complete")
        } catch {
            print("[SemanticSearchEngine] Indexing failed: \(error)")
        }
    }

    func indexSession(_ session: Session, activities: [ActivityEvent], repository: SessionRepository) async {
        let chunks = generateChunks(session: session, activities: activities)
        var embeddings: [SessionEmbedding] = []
        for chunk in chunks {
            if let vector = computeEmbedding(for: chunk.document) {
                let embedding = SessionEmbedding(
                    id: UUID().uuidString,
                    sessionId: session.id.uuidString,
                    chunkKind: chunk.kind,
                    vector: vector,
                    document: chunk.document
                )
                embeddings.append(embedding)
            }
        }
        if !embeddings.isEmpty {
            try? await repository.saveEmbeddings(embeddings)
        }
    }

    struct SearchResult: Sendable, Identifiable {
        var id: UUID { sessionId }
        let sessionId: UUID
        let score: Float
        let matchedDocument: String
        let matchedKind: String
    }

    func search(query: String, repository: SessionRepository) async -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        guard let queryVector = computeEmbedding(for: query) else { return [] }
        
        do {
            let allEmbeddings = try await repository.fetchAllEmbeddings()
            var sessionBestMatch: [UUID: (score: Float, document: String, kind: String)] = [:]
            
            for emb in allEmbeddings {
                guard let sessionId = UUID(uuidString: emb.sessionId) else { continue }
                let vector = emb.floatVector()
                let score = cosineSimilarity(a: queryVector, b: vector)
                
                if score > 0.28 { // relevance threshold
                    if let existing = sessionBestMatch[sessionId] {
                        if score > existing.score {
                            sessionBestMatch[sessionId] = (score: score, document: emb.document, kind: emb.chunkKind)
                        }
                    } else {
                        sessionBestMatch[sessionId] = (score: score, document: emb.document, kind: emb.chunkKind)
                    }
                }
            }
            
            return sessionBestMatch.map { sessionId, match in
                SearchResult(
                    sessionId: sessionId,
                    score: match.score,
                    matchedDocument: match.document,
                    matchedKind: match.kind
                )
            }.sorted { $0.score > $1.score }
        } catch {
            print("[SemanticSearchEngine] Search failed: \(error)")
            return []
        }
    }

    private func isTerminal(_ bundleId: String) -> Bool {
        [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "co.zeit.hyper"
        ].contains(bundleId)
    }
}
