import Foundation
import NaturalLanguage
import Accelerate

actor SemanticSearchEngine {
    static let shared = SemanticSearchEngine()

    private let embeddingModel: NLEmbedding? = {
        NLEmbedding.sentenceEmbedding(for: .english)
    }()

    private init() {}

    // MARK: - Chunk Generation

    func generateChunks(session: Session, activities: [ActivityEvent]) -> [(kind: String, document: String)] {
        // Exclude Echo itself from indexing
        let selfBundleId = "com.deepaks.EchoTest2"
        let activities = activities.filter { $0.appBundleId != selfBundleId }

        var chunks: [(kind: String, document: String)] = []

        // 1. Session Summary Chunk
        var summaryText = "Session Title: \(session.title ?? "Untitled Session")"
        if let cluster = session.workflowCluster {
            summaryText += "\nCluster: \(cluster)"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy h:mm a"
        let dateString = dateFormatter.string(from: session.startedAt)
        summaryText += "\nDate: \(dateString)"

        let apps = Set(activities.map(\.appName)).sorted()
        if !apps.isEmpty {
            summaryText += "\nApplications used: \(apps.joined(separator: ", "))"
        }

        let windowTitles = Array(
            Set(
                activities.compactMap(\.windowTitle)
                    .filter { !$0.isEmpty }
            )
        ).prefix(10)
        if !windowTitles.isEmpty {
            summaryText += "\nWindows: \(windowTitles.joined(separator: ", "))"
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
            var text = "Webpage: \(title)\nURL: \(url)\nBrowser: \(event.appName)"
            if let profile = event.profileName, !profile.isEmpty {
                text += "\nProfile: \(profile)"
            }
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
            docParts.append("App: \(event.appName)")

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

            if docParts.count > 1 {
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
            var text = "File: \(filename)\nPath: \(cleanPath)\nEditor: \(event.appName)"

            let ext = (filename as NSString).pathExtension
            if !ext.isEmpty {
                text += "\nType: \(ext)"
            }

            chunks.append((kind: "file", document: text))
        }

        return chunks
    }

    // MARK: - Embedding

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

    // MARK: - Indexing

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

    // MARK: - Search

    struct SearchResult: Sendable, Identifiable {
        var id: UUID { sessionId }
        let sessionId: UUID
        let score: Float
        let matchedDocument: String
        let matchedKind: String
        let matchedChunks: [(document: String, kind: String, score: Float)]
    }

    func search(query: String, repository: SessionRepository) async -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        guard let queryVector = computeEmbedding(for: query) else { return [] }

        do {
            let allEmbeddings = try await repository.fetchAllEmbeddings()

            // Collect ALL matching chunks per session (threshold 0.15)
            var sessionChunks: [UUID: [(document: String, kind: String, score: Float)]] = [:]

            for emb in allEmbeddings {
                guard let sessionId = UUID(uuidString: emb.sessionId) else { continue }
                let vector = emb.floatVector()
                let vectorScore = cosineSimilarity(a: queryVector, b: vector)

                let finalScore = calculateHybridScore(query: query, document: emb.document, vectorScore: vectorScore)

                if finalScore > 0.15 {
                    sessionChunks[sessionId, default: []].append(
                        (document: emb.document, kind: emb.chunkKind, score: finalScore)
                    )
                }
            }

            // Aggregate per-session scores
            var results: [SearchResult] = []

            for (sessionId, chunks) in sessionChunks {
                let sorted = chunks.sorted { $0.score > $1.score }
                let topChunks = Array(sorted.prefix(3))

                let bestScore = topChunks[0].score
                let secondBestScore = topChunks.count > 1 ? topChunks[1].score : Float(0)
                let thirdBestScore = topChunks.count > 2 ? topChunks[2].score : Float(0)

                var aggregatedScore = bestScore * 0.65 + secondBestScore * 0.25 + thirdBestScore * 0.10

                // Diversity bonus: if matching chunks span different kinds
                let uniqueKinds = Set(sorted.map(\.kind))
                if uniqueKinds.count > 1 {
                    aggregatedScore += 0.08
                }

                aggregatedScore = min(aggregatedScore, 1.0)

                let best = topChunks[0]
                results.append(SearchResult(
                    sessionId: sessionId,
                    score: aggregatedScore,
                    matchedDocument: best.document,
                    matchedKind: best.kind,
                    matchedChunks: topChunks
                ))
            }

            // Dynamic threshold
            let topScore = results.map(\.score).max() ?? 0
            let dynamicThreshold = max(Float(0.20), topScore * 0.35)

            return results
                .filter { $0.score >= dynamicThreshold }
                .sorted { $0.score > $1.score }
        } catch {
            print("[SemanticSearchEngine] Search failed: \(error)")
            return []
        }
    }

    // MARK: - Hybrid Scoring

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
            "were", "is", "are", "am", "be", "been", "have", "has", "had",
            "when", "which"
        ]

        let questionWords: Set<String> = [
            "what", "where", "when", "how", "why", "which", "who", "did", "was"
        ]

        let searchTerms = queryWords.filter { !stopwords.contains($0) }
        guard !searchTerms.isEmpty else {
            return vectorScore
        }

        // Tokenize document into words for word-boundary matching
        let docWords = cleanDoc
            .components(separatedBy: delimiters)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // TF-IDF-inspired term weighting
        func termWeight(_ term: String) -> Float {
            if term.count >= 6 { return 1.5 }
            if term.count >= 4 { return 1.2 }
            return 1.0
        }

        // Check if a term is "technical" (contains dots, slashes, or mixed case)
        func isTechnicalTerm(_ term: String) -> Bool {
            if term.contains(".") || term.contains("/") { return true }
            // Check for camelCase in the ORIGINAL query (before lowercasing)
            let originalTerms = query
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty && $0.count >= 2 }
            for original in originalTerms {
                if original.lowercased() == term {
                    let hasLower = original.contains(where: { $0.isLowercase })
                    let hasUpper = original.contains(where: { $0.isUppercase })
                    if hasLower && hasUpper { return true }
                }
            }
            return false
        }

        // Word-boundary matching with TF-IDF weighting
        var totalWeight: Float = 0
        var matchedWeight: Float = 0
        var allWordBoundaryMatch = true

        for term in searchTerms {
            let weight = termWeight(term)
            totalWeight += weight

            // Word-boundary match using regex
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: term))\\b"
            let wordBoundaryMatch: Bool
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(cleanDoc.startIndex..., in: cleanDoc)
                wordBoundaryMatch = regex.firstMatch(in: cleanDoc, range: range) != nil
            } else {
                wordBoundaryMatch = false
            }

            if wordBoundaryMatch {
                matchedWeight += weight
            } else {
                allWordBoundaryMatch = false
                // Substring fallback for technical terms (0.7x weight)
                if isTechnicalTerm(term) && cleanDoc.contains(term) {
                    matchedWeight += weight * 0.7
                }
            }
        }

        let keywordCoverage = matchedWeight / totalWeight

        // Phrase proximity bonus
        var proximityBonus: Float = 0
        if searchTerms.count >= 2 {
            for i in 0..<(searchTerms.count - 1) {
                let termA = searchTerms[i]
                let termB = searchTerms[i + 1]
                if termsAreProximate(termA: termA, termB: termB, inWords: docWords, windowSize: 5) {
                    proximityBonus += 0.12
                }
            }
        }

        // Adaptive blending
        let hasQuestionWords = queryWords.contains(where: { questionWords.contains($0) })
        let semanticWeight: Float
        let keywordWeight: Float

        if searchTerms.count <= 2 && allWordBoundaryMatch {
            // Exact match mode
            semanticWeight = 0.25
            keywordWeight = 0.75
        } else if searchTerms.count >= 4 || hasQuestionWords {
            // Semantic mode
            semanticWeight = 0.70
            keywordWeight = 0.30
        } else {
            // Default balanced
            semanticWeight = 0.50
            keywordWeight = 0.50
        }

        let normalizedVector = max(0, vectorScore)
        var blended = (normalizedVector * semanticWeight) + (keywordCoverage * keywordWeight) + proximityBonus

        // Full-match boost
        if allWordBoundaryMatch && !searchTerms.isEmpty {
            blended = max(blended, 0.85)
        }

        return min(max(blended, 0), 1.0)
    }

    private func termsAreProximate(termA: String, termB: String, inWords words: [String], windowSize: Int) -> Bool {
        var positionsA: [Int] = []
        var positionsB: [Int] = []

        for (index, word) in words.enumerated() {
            if word == termA { positionsA.append(index) }
            if word == termB { positionsB.append(index) }
        }

        for posA in positionsA {
            for posB in positionsB {
                if abs(posA - posB) <= windowSize {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Utility

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
            "com.macromates.TextMate",
            "com.google.antigravity-ide",
            "com.google.antigravity"
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
