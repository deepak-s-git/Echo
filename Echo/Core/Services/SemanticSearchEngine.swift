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
        var seenTerminalKeys = Set<String>()
        for event in activities {
            guard event.type == .terminalCommand || isTerminal(event.appBundleId) else { continue }
            
            var path = ""
            if let url = event.url, url.hasPrefix("file://") {
                path = URL(string: url)?.path ?? ""
            }
            
            let title = event.windowTitle ?? ""
            let key = "\(path):\(title)"
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            guard seenTerminalKeys.insert(key).inserted else { continue }
            
            var docParts: [String] = []
            if !title.isEmpty {
                let cleanTitle = title
                    .replacingOccurrences(of: " — -zsh — 120×30", with: "")
                    .replacingOccurrences(of: " — login — 120×30", with: "")
                    .replacingOccurrences(of: " -zsh", with: "")
                    .replacingOccurrences(of: " -login", with: "")
                docParts.append("Terminal: \(cleanTitle)")
            }
            
            if !path.isEmpty {
                let dirName = (path as NSString).lastPathComponent
                docParts.append("Directory: \(dirName)")
                docParts.append("Path: \(path)")
                
                let gitPath = (path as NSString).appendingPathComponent(".git")
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDir), isDir.boolValue {
                    docParts.append("Version Control: Git repository")
                }
            }
            
            if !docParts.isEmpty {
                let text = docParts.joined(separator: "\n")
                chunks.append((kind: "terminal", document: text))
            }
        }

        // 4. File Chunks
        var seenFiles = Set<String>()
        for event in activities {
            let isFile = event.type == .fileAccess ||
                         event.appBundleId == "com.apple.Preview" ||
                         (event.url?.hasPrefix("file://") == true) ||
                         isCodeEditorOrDocApp(event.appBundleId, windowTitle: event.windowTitle)
            
            guard isFile else { continue }
            
            let path = event.url ?? event.windowTitle
            guard let p = path, !p.isEmpty else { continue }
            
            let cleanPath: String
            if p.hasPrefix("file://"), let url = URL(string: p) {
                cleanPath = url.path
            } else {
                cleanPath = p
            }
            
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: cleanPath, isDirectory: &isDir), isDir.boolValue {
                continue
            }
            
            let lowerPath = cleanPath.lowercased()
            guard seenFiles.insert(lowerPath).inserted else { continue }
            
            let filename = (cleanPath as NSString).lastPathComponent
            let text = "File: \(filename)\nPath: \(cleanPath)"
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
                let vectorScore = cosineSimilarity(a: queryVector, b: vector)
                
                let finalScore = calculateHybridScore(query: query, document: emb.document, vectorScore: vectorScore)
                
                if finalScore > 0.28 { // relevance threshold
                    if let existing = sessionBestMatch[sessionId] {
                        if finalScore > existing.score {
                            sessionBestMatch[sessionId] = (score: finalScore, document: emb.document, kind: emb.chunkKind)
                        }
                    } else {
                        sessionBestMatch[sessionId] = (score: finalScore, document: emb.document, kind: emb.chunkKind)
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

    private func calculateHybridScore(query: String, document: String, vectorScore: Float) -> Float {
        let cleanQuery = query.lowercased()
        let cleanDoc = document.lowercased()
        
        let delimiters = CharacterSet.alphanumerics.inverted
        let queryWords = cleanQuery
            .components(separatedBy: delimiters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count >= 2 }
        
        let stopwords: Set<String> = [
            "a", "an", "the", "in", "on", "at", "for", "with",
            "where", "what", "was", "i", "did", "to", "under",
            "above", "of", "and", "or", "but", "how", "why", "who",
            "were", "is", "are", "am", "be", "been", "have", "has", "had"
        ]
        
        let searchTerms = queryWords.filter { !stopwords.contains($0) }
        guard !searchTerms.isEmpty else {
            return vectorScore
        }
        
        var matchCount = 0
        for term in searchTerms {
            if cleanDoc.contains(term) {
                matchCount += 1
            }
        }
        
        let keywordCoverage = Float(matchCount) / Float(searchTerms.count)
        
        let normalizedVector = max(0, vectorScore)
        var blended = (normalizedVector * 0.60) + (keywordCoverage * 0.40)
        
        if keywordCoverage == 1.0 {
            blended = max(blended, 0.90)
        }
        
        return min(max(blended, 0), 1.0)
    }

    private func isTerminal(_ bundleId: String) -> Bool {
        [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "dev.warp.Warp-Stable",
            "co.zeit.hyper"
        ].contains(bundleId)
    }

    private func isCodeEditorOrDocApp(_ bundleId: String, windowTitle: String?) -> Bool {
        let editors = [
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92", // Cursor
            "com.apple.dt.Xcode",
            "com.sublimetext.4",
            "com.apple.TextEdit",
            "com.jetbrains.",
            "org.vim.",
            "com.macromates.TextMate"
        ]
        let isEditor = editors.contains { bundleId.hasPrefix($0) }
        guard isEditor else { return false }
        
        guard let title = windowTitle else { return false }
        let ext = (title as NSString).pathExtension
        if !ext.isEmpty { return true }
        
        let parts = title.components(separatedBy: " — ")
        if let first = parts.first {
            let firstExt = (first as NSString).pathExtension
            if !firstExt.isEmpty { return true }
        }
        
        return false
    }
}
