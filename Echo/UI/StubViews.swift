import SwiftUI

// MARK: - SearchView

struct MatchedChunk: Equatable {
    let document: String
    let kind: String
    let score: Float
}

struct SemanticSearchResult: Identifiable, Equatable {
    var id: UUID { session.id }
    let session: Session
    let score: Float?
    let matchedDocument: String?
    let matchedKind: String?
    let matchedChunks: [MatchedChunk]
    
    static func == (lhs: SemanticSearchResult, rhs: SemanticSearchResult) -> Bool {
        lhs.session.id == rhs.session.id
    }
}

struct SearchView: View {
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var appStore: AppStore
    @State private var query = ""
    @FocusState private var isFocused: Bool
    
    @State private var searchResults: [SemanticSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedCluster: WorkflowCluster? = nil

    private var filteredResults: [SemanticSearchResult] {
        if let selectedCluster {
            return searchResults.filter { $0.session.cluster == selectedCluster }
        }
        return searchResults
    }

    var body: some View {
        ZStack {
            EchoDesign.ambientBackground.ignoresSafeArea()
            AmbientGlowView()
                .opacity(0.45)

            VStack(alignment: .leading, spacing: 18) {
                // Header
                Text("Search Workflows")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.primary)
                    .padding(.bottom, 2)

                // Premium glassmorphic search bar
                HStack(spacing: 12) {
                    ZStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isFocused ? EchoPalette.glowBlue : .secondary)
                            .scaleEffect(isFocused ? 1.1 : 1.0)
                            .opacity(isSearching ? 0 : 1)

                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                            .opacity(isSearching ? 1 : 0)
                    }
                    .frame(width: 14, height: 14)
                    .animation(EchoDesign.subtle, value: isFocused)

                    TextField("Search your workflows…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .focused($isFocused)
                        .onAppear {
                            if appStore.isSearchPresented { query = "" }
                        }

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    RoundedRectangle(cornerRadius: EchoDesign.cardCornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.3))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                        .strokeBorder(isFocused ? EchoPalette.glowBlue.opacity(0.4) : EchoPalette.stroke, lineWidth: 1.0)
                        .animation(EchoDesign.subtle, value: isFocused)
                )
                .shadow(color: isFocused ? EchoPalette.glowBlue.opacity(0.08) : .clear, radius: 8, y: 2)
                .onChange(of: query) { oldValue, newValue in
                    runSearch(for: newValue)
                }
                .onAppear {
                    runSearch(for: query)
                }
                .onChange(of: sessionStore.recentSessions) { oldValue, newValue in
                    runSearch(for: query)
                }

                // Category Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CategoryPill(
                            label: "All",
                            icon: "square.grid.2x2",
                            isSelected: selectedCluster == nil,
                            color: EchoPalette.indigoSoft
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                selectedCluster = nil
                            }
                        }
                        
                        ForEach(WorkflowCluster.allCases, id: \.self) { cluster in
                            let colors = cluster.colors
                            CategoryPill(
                                label: cluster.label,
                                icon: cluster.icon,
                                isSelected: selectedCluster == cluster,
                                color: colors[0]
                            ) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    selectedCluster = cluster
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }

                if filteredResults.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundStyle(EchoPalette.indigo.opacity(0.35))
                        Text(selectedCluster != nil ? "No workflows in this category" : "No sessions match")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(selectedCluster != nil ? "Try clearing the filter or searching something else." : "Try searching for tags, app names, or titles.")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredResults) { result in
                                SearchResultCard(result: result) {
                                    appStore.openSessionDetail(result.session.id)
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
    }
    
    private func runSearch(for q: String) {
        searchTask?.cancel()
        
        let trimmed = q.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            self.searchResults = sessionStore.recentSessions.map {
                SemanticSearchResult(session: $0, score: nil, matchedDocument: nil, matchedKind: nil, matchedChunks: [])
            }
            self.isSearching = false
            return
        }
        
        self.isSearching = true
        searchTask = Task {
            let rawResults = await sessionStore.performSemanticSearch(query: trimmed)
            
            var mapped: [SemanticSearchResult] = []
            for res in rawResults {
                if let session = sessionStore.recentSessions.first(where: { $0.id == res.sessionId }) {
                    let chunks = res.matchedChunks.map { chunk in
                        MatchedChunk(document: chunk.document, kind: chunk.kind, score: chunk.score)
                    }
                    mapped.append(SemanticSearchResult(
                        session: session,
                        score: res.score,
                        matchedDocument: res.matchedDocument,
                        matchedKind: res.matchedKind,
                        matchedChunks: chunks
                    ))
                }
            }
            
            let lowerQ = trimmed.lowercased()
            for sess in sessionStore.recentSessions {
                if (sess.title ?? "").lowercased().contains(lowerQ) {
                    if !mapped.contains(where: { $0.session.id == sess.id }) {
                        mapped.append(SemanticSearchResult(
                            session: sess,
                            score: 0.5,
                            matchedDocument: nil,
                            matchedKind: "summary",
                            matchedChunks: []
                        ))
                    }
                }
            }
            
            mapped.sort { ($0.score ?? 0) > ($1.score ?? 0) }
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                self.searchResults = mapped
                self.isSearching = false
            }
        }
    }
}

struct CategoryPill: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    @State private var hovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                if isSelected {
                    Capsule()
                        .fill(color.opacity(0.18))
                } else {
                    Capsule()
                        .fill(Color.black.opacity(0.3))
                }
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        isSelected ? color.opacity(0.5) : (hovering ? EchoPalette.strokeBright : EchoPalette.stroke),
                        lineWidth: 0.5
                    )
            }
            .foregroundStyle(isSelected ? color : (hovering ? .primary : .secondary))
            .scaleEffect(hovering ? 1.03 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: hovering)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct SearchResultCard: View {
    let result: SemanticSearchResult
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Category icon badge with gradient
                let cluster = result.session.cluster
                let colors = cluster.colors
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: colors[0].opacity(0.35), radius: 4, y: 2)
                    
                    Image(systemName: cluster.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 5) {
                    Text(result.session.title ?? "Untitled segment")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if !result.matchedChunks.isEmpty {
                        // Show up to 2 distinct chunk type snippets
                        let displayChunks = deduplicatedChunks(result.matchedChunks, maxCount: 2)
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(displayChunks.enumerated()), id: \.offset) { _, chunk in
                                HStack(spacing: 5) {
                                    Image(systemName: snippetIcon(kind: chunk.kind))
                                        .font(.system(size: 9))
                                        .foregroundStyle(badgeColor)
                                    Text(formatMatchedSnippet(document: chunk.document, kind: chunk.kind))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    } else if let doc = result.matchedDocument, let kind = result.matchedKind {
                        HStack(spacing: 5) {
                            Image(systemName: snippetIcon(kind: kind))
                                .font(.system(size: 9))
                                .foregroundStyle(badgeColor)
                            Text(formatMatchedSnippet(document: doc, kind: kind))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Text(result.session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                            
                            Text("·")
                                .foregroundStyle(.tertiary)
                            
                            Text(result.session.duration.shortLabel)
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                }

                Spacer()

                // Overlapping App Icon Stack from restore plan
                let appItems = result.session.restorePlan?.items.filter { $0.kind == .application } ?? []
                var seen = Set<String>()
                let bundleIds = appItems.compactMap { $0.bundleId }.filter { seen.insert($0).inserted }
                if !bundleIds.isEmpty {
                    HStack(spacing: -6) {
                        ForEach(Array(bundleIds.prefix(5).enumerated()), id: \.element) { index, bundleId in
                            AppIconView(bundleId: bundleId, size: 20)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(Color.black.opacity(0.2), lineWidth: 0.5)
                                )
                                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
                                .zIndex(Double(bundleIds.count - index))
                        }
                        if bundleIds.count > 5 {
                            Text("+\(bundleIds.count - 5)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                                .padding(.leading, 4)
                        }
                    }
                    .padding(.trailing, 4)
                } else if result.session.appCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 8))
                        Text("\(result.session.appCount) apps")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.04), in: Capsule())
                    .padding(.trailing, 4)
                }

                if let score = result.score {
                    Text("\(Int(score * 100))% Match")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background {
                            Capsule()
                                .fill(badgeColor.opacity(0.12))
                        }
                        .foregroundStyle(badgeColor)
                        .overlay {
                            Capsule()
                                .strokeBorder(badgeColor.opacity(0.24), lineWidth: 0.5)
                        }
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(hovering ? .secondary : .quaternary)
                        .offset(x: hovering ? 2 : 0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.5), value: hovering)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .echoCard()
            .scaleEffect(hovering ? 1.008 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
            .echoHoverHighlight()
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
    }

    private var badgeColor: Color {
        guard let score = result.score else { return EchoPalette.indigoSoft }
        if score >= 0.70 {
            return EchoPalette.glowBlue
        } else if score >= 0.45 {
            return EchoPalette.indigoSoft
        } else {
            return .secondary
        }
    }

    private func snippetIcon(kind: String) -> String {
        switch kind {
        case "browser": return "safari"
        case "terminal": return "terminal"
        case "file": return "doc.text"
        case "summary": return "sparkles"
        default: return "info.circle"
        }
    }

    private func formatMatchedSnippet(document: String, kind: String) -> String {
        let lines = document.components(separatedBy: "\n")
        if kind == "browser" {
            if let titleLine = lines.first(where: { $0.hasPrefix("Webpage: ") }) {
                return titleLine
            }
            if let urlLine = lines.first(where: { $0.hasPrefix("URL: ") }) {
                return urlLine
            }
        } else if kind == "file" {
            let filePart = lines.first(where: { $0.hasPrefix("File: ") }) ?? ""
            let editorPart = lines.first(where: { $0.hasPrefix("Editor: ") }) ?? ""
            if !filePart.isEmpty && !editorPart.isEmpty {
                return "\(filePart) — \(editorPart.replacingOccurrences(of: "Editor: ", with: ""))"
            }
            return filePart.isEmpty ? (lines.first ?? document) : filePart
        } else if kind == "terminal" {
            let termLine = lines.first(where: { $0.hasPrefix("Terminal: ") }) ?? ""
            let dirLine = lines.first(where: { $0.hasPrefix("Directory: ") }) ?? ""
            if !termLine.isEmpty && !dirLine.isEmpty {
                return "\(termLine) — \(dirLine.replacingOccurrences(of: "Directory: ", with: ""))"
            }
            return termLine.isEmpty ? (lines.first ?? document) : termLine
        } else if kind == "summary" {
            let titleLine = lines.first(where: { $0.hasPrefix("Session Title: ") }) ?? ""
            return titleLine.isEmpty ? (lines.first ?? document) : titleLine.replacingOccurrences(of: "Session Title: ", with: "Summary: ")
        }
        return lines.first ?? document
    }

    /// Deduplicate chunks by kind, keeping the highest-scoring one per kind.
    private func deduplicatedChunks(_ chunks: [MatchedChunk], maxCount: Int) -> [MatchedChunk] {
        var seen = Set<String>()
        var result: [MatchedChunk] = []
        for chunk in chunks {
            if seen.insert(chunk.kind).inserted {
                result.append(chunk)
                if result.count >= maxCount { break }
            }
        }
        return result
    }
}

// MARK: - LaunchView

struct LaunchView: View {
    var body: some View {
        ZStack {
            EchoPalette.graphite
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Starting Echo…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}



// MARK: - ErrorView

struct ErrorView: View {
    let error: Error

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(.red)
            Text("Echo couldn't start")
                .font(.system(size: 18, weight: .semibold))
            Text(error.localizedDescription)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - PermissionsView

struct PermissionsView: View {
    @EnvironmentObject var permissionsManager: PermissionsManager
    
    @State private var gridOpacity: Double = 0.0
    @State private var cardOpacity: Double = 0.0
    @State private var cardOffset: CGFloat = 25.0
    @State private var isHovered = false
    
    private let brandCopper = Color(red: 0.85, green: 0.42, blue: 0.18)
    private let brandAmber = Color(red: 0.95, green: 0.65, blue: 0.15)
    private let brandGold = Color(red: 0.82, green: 0.74, blue: 0.55)

    var body: some View {
        ZStack {
            // Deep obsidian charcoal background
            Color(red: 0.05, green: 0.05, blue: 0.055)
                .ignoresSafeArea()
            
            // Background dotted grid & constellation (warm gold accents)
            SwiftUI.TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                
                BackgroundConstellationView(
                    time: time,
                    accentColor: brandGold
                )
                .opacity(gridOpacity)
            }
            .allowsHitTesting(false)
            
            // Centered glassmorphic container
            VStack(spacing: 0) {
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(brandCopper.opacity(0.12))
                            .frame(width: 72, height: 72)
                            .shadow(color: brandCopper.opacity(0.15), radius: 8)
                        
                        Image(systemName: "lock.shield")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(brandCopper)
                    }
                    .padding(.top, 10)
                    
                    Text("Accessibility Access Required")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("Echo uses Accessibility to detect which apps you use and how long you use them. No keystrokes or content is ever recorded.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .frame(maxWidth: 360)
                    
                    Text("Toggle the switch for **Echo** (or **Xcode** if running in debug mode) in Privacy & Security → Accessibility.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                        .padding(.top, 4)
                    
                    Button {
                        permissionsManager.requestAccessibility()
                    } label: {
                        Text("Open System Settings")
                            .font(.system(size: 13, weight: .bold))
                              .foregroundStyle(.white)
                            .frame(width: 240)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [brandCopper, brandAmber],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(.white.opacity(0.24), lineWidth: 0.5)
                            )
                            .shadow(color: brandCopper.opacity(isHovered ? 0.38 : 0.16), radius: isHovered ? 14 : 7, y: 3)
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.75)) {
                            isHovered = hovering
                        }
                    }
                    .padding(.top, 12)
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.015))
                        .background(Color.black.opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
                )
                .frame(width: 440)
                .opacity(cardOpacity)
                .offset(y: cardOffset)
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.6)) {
                gridOpacity = 1.0
            }
            withAnimation(.spring(response: 0.8, dampingFraction: 0.76)) {
                cardOpacity = 1.0
                cardOffset = 0
            }
        }
    }
}

// MARK: - MenuBarView

struct MenuBarView: View {
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var sessionStore: SessionStore
    @EnvironmentObject var sessionControl: SessionControlStore

    @State private var newWorkflowName: String = ""
    @State private var restoringSessionId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Brand & Live Pulse
            HStack(spacing: 8) {
                Image("butterfly_logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                
                Text("ECHO")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(EchoPalette.premiumGradient)
                
                Spacer()
                
                // Live Status Indicator — fixed width so status text change doesn't resize the header
                HStack(spacing: 5) {
                    if activityStore.isSessionActive && !activityStore.isSessionPaused {
                        EchoLiveDot(isActive: true)
                        Text("RECORDING")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(EchoPalette.live)
                    } else if activityStore.isSessionPaused {
                        Circle()
                            .fill(EchoPalette.warning)
                            .frame(width: 8, height: 8)
                        Text("PAUSED")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(EchoPalette.warning)
                    } else {
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 8, height: 8)
                        Text("IDLE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 82, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
            }
            .padding(.bottom, 2)

            // Main Active Recording/Capture Card
            ZStack(alignment: .top) {
                // ── ACTIVE branch ──────────────────────────────────────
                VStack(alignment: .center, spacing: 10) {
                    VStack(spacing: 4) {
                        Text(activityStore.sessionDuration.sessionDurationFormatted)
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                            .foregroundStyle(activityStore.isSessionPaused ? EchoPalette.warning : EchoPalette.indigoSoft)
                            .shadow(color: (activityStore.isSessionPaused ? EchoPalette.warning : EchoPalette.indigoSoft).opacity(0.15), radius: 6)
                        
                        Text(activityStore.workflowTitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    
                    Divider().opacity(0.3)
                    
                    // Current Application Focus Row
                    HStack(spacing: 8) {
                        Image(systemName: activityStore.isSessionPaused ? "pause.circle.fill" : "sparkles")
                            .font(.system(size: 12))
                            .foregroundStyle(activityStore.isSessionPaused ? EchoPalette.warning : EchoPalette.indigoSoft)
                        
                        Text(activityStore.isSessionPaused ? "Recording Paused" : activityStore.focusHeadline)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(activityStore.focusLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.04), in: Capsule())
                            .opacity(activityStore.isSessionPaused ? 0 : 1)
                    }
                    .padding(.horizontal, 4)
                    
                    // Recording Controls
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                if activityStore.isSessionPaused {
                                    await sessionControl.resumeSession()
                                } else {
                                    await sessionControl.pauseSession()
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: activityStore.isSessionPaused ? "play.fill" : "pause.fill")
                                Text(activityStore.isSessionPaused ? "Resume" : "Pause")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(activityStore.isSessionPaused ? EchoPalette.live : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            appStore.showMainWindow()
                            sessionControl.requestEndSession(
                                appStore: appStore,
                                activityStore: activityStore,
                                sessionStore: sessionStore
                            )
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.fill")
                                Text("Stop")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(EchoPalette.destructive)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(EchoPalette.destructive.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(EchoPalette.destructive.opacity(0.25), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .opacity(activityStore.isSessionActive ? 1 : 0)
                .allowsHitTesting(activityStore.isSessionActive)

                // ── IDLE branch ────────────────────────────────────────
                VStack(alignment: .leading, spacing: 10) {
                    Text("Start Workflow Recording")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 8) {
                        TextField("Enter workflow name...", text: $newWorkflowName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                        
                        Button {
                            Task {
                                let name = newWorkflowName.isEmpty ? "Quick Workflow" : newWorkflowName
                                await sessionControl.startNewSession(workflowName: name, appStore: appStore)
                                newWorkflowName = ""
                            }
                        } label: {
                            Image(systemName: "record.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.red.opacity(0.2), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach([
                                ("Coding", "Coding"),
                                ("Research", "Research"),
                                ("Design", "Design"),
                                ("Writing", "Writing")
                            ], id: \.1) { label, name in
                                Button {
                                    Task {
                                        await sessionControl.startNewSession(workflowName: name, appStore: appStore)
                                    }
                                } label: {
                                    Text(label)
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.primary.opacity(0.04), in: Capsule())
                                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .opacity(activityStore.isSessionActive ? 0 : 1)
                .allowsHitTesting(!activityStore.isSessionActive)
            }
            .padding(12)
            .frame(height: 156, alignment: .top)
            .clipped()
            .background(EchoPalette.graphiteElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(EchoPalette.stroke, lineWidth: 0.5)
            )

            // Card 3: Recent Memories list
            let recentMemories = sessionStore.recentSessions.prefix(3)
            VStack(alignment: .leading, spacing: 8) {
                Text("RECENT MEMORIES")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
                
                ZStack(alignment: .top) {
                    VStack(spacing: 8) {
                        ForEach(recentMemories) { session in
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.primary.opacity(0.04))
                                        .frame(width: 26, height: 26)
                                    Image(systemName: session.cluster.icon)
                                        .font(.system(size: 11))
                                        .foregroundStyle(EchoPalette.indigoSoft)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title ?? "Untitled segment")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    
                                    HStack(spacing: 5) {
                                        Text(relativeTimeString(for: session.startedAt))
                                            .foregroundStyle(.secondary)
                                        Text("·")
                                            .foregroundStyle(.tertiary)
                                        Text(session.duration.shortLabel)
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.system(size: 9))
                                }
                                
                                Spacer()
                                
                                Button {
                                    restoreSession(session)
                                } label: {
                                    ZStack {
                                        if restoringSessionId == session.id {
                                            ProgressView()
                                                .scaleEffect(0.6)
                                        } else {
                                            Image(systemName: "arrow.uturn.backward")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.primary.opacity(0.7))
                                        }
                                    }
                                    .frame(width: 24, height: 24)
                                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(restoringSessionId != nil)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                        }
                    }
                    .padding(6)
                    .opacity(recentMemories.isEmpty ? 0 : 1)

                    VStack(spacing: 4) {
                        Text("No Recent Workflows")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Your recorded sessions will appear here.")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(recentMemories.isEmpty ? 1 : 0)
                }
                .frame(height: 145, alignment: .top)
                .clipped()
                .background(Color.primary.opacity(0.015), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(EchoPalette.stroke, lineWidth: 0.5))
            }

            Divider().opacity(0.3)

            // Card 4: Footer quick actions
            HStack {
                Button("Open Echo") {
                    appStore.showMainWindow()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                
                Spacer()
                
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .padding(16)
        .frame(width: 320, height: 450, alignment: .top)
        .fixedSize(horizontal: true, vertical: true)
        .clipped()
        .background {
            ZStack {
                EchoPalette.graphite

            }
        }
    }

    private func relativeTimeString(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func restoreSession(_ session: Session) {
        guard let plan = session.restorePlan else { return }
        restoringSessionId = session.id
        Task {
            let engine = WorkflowRestoreEngine()
            _ = await engine.restore(plan: plan)
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                restoringSessionId = nil
            }
        }
    }
}

// MARK: - MenuBarLabel

struct MenuBarLabel: View {
    var body: some View {
        Image("menubar_butterfly")
    }
}

// MARK: - Placeholder helper

private struct EchoPlaceholder: View {
    let title: String
    let icon: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(Color.accentColor.opacity(0.5))
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EchoDesign.ambientBackground)
    }
}
