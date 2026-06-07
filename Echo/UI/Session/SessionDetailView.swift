import SwiftUI

struct SessionDetailView: View {
    let sessionId: UUID

    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var sessionDetailStore: SessionDetailStore
    @EnvironmentObject var sessionControl: SessionControlStore
    @State private var showDiagnostics = false

    var body: some View {
        ZStack {
            EchoDesign.ambientBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                detailHeader

            if sessionDetailStore.isLoading {
                Spacer()
                ProgressView("Recalling session…")
                Spacer()
            } else if let memory = sessionDetailStore.memory {
                ScrollView {
                    VStack(alignment: .leading, spacing: EchoDesign.sectionSpacing) {
                        if sessionDetailStore.loadState == .degraded {
                            degradedBanner
                        }
                        header(memory)
                        continuitySection(memory)
                        rhythmSection(memory)
                        if !memory.phases.isEmpty {
                            phasesSection(memory)
                        } else {
                            emptySection(
                                title: "Workflow phases",
                                icon: "rectangle.split.3x1",
                                message: "Not enough focus stretches to form phases yet."
                            )
                        }
                        if !memory.appTransitions.isEmpty {
                            transitionsSection(memory)
                        } else {
                            emptySection(
                                title: "App transitions",
                                icon: "arrow.left.arrow.right",
                                message: "No app transitions were recorded."
                            )
                        }
                        if !memory.browserContexts.isEmpty {
                            browserSection(memory)
                        }
                        if !memory.interruptions.isEmpty { interruptionsSection(memory) }
                        restoreSection(memory)
                        if let diagnostics = sessionDetailStore.diagnostics, !diagnostics.issues.isEmpty {
                            developerDiagnosticsFooter(diagnostics)
                        }
                    }
                    .padding(EchoDesign.containerRadius)
                    .padding(.bottom, 32)
                }
            } else {
                failedStateView
            }
            }
        }
        .task(id: sessionId) {
            await sessionDetailStore.load(sessionId: sessionId)
        }
        .onDisappear {
            sessionDetailStore.stopWatching()
        }
        .alert("Restore", isPresented: .init(
            get: { sessionDetailStore.restoreMessage != nil },
            set: { if !$0 { sessionDetailStore.clearRestoreMessage() } }
        )) {
            Button("OK") { sessionDetailStore.clearRestoreMessage() }
        } message: {
            Text(sessionDetailStore.restoreMessage ?? "")
        }
        .sheet(isPresented: $sessionDetailStore.showRestoreSelection) {
            RestoreSelectionSheet(
                items: $sessionDetailStore.selectableRestoreItems,
                onRestore: {
                    Task { await sessionDetailStore.restoreSelectedItems() }
                },
                onRestoreAndContinue: {
                    Task {
                        await sessionDetailStore.restoreSelectedItems()
                        if let threadId = sessionDetailStore.memory?.session.workflowThreadId {
                            await sessionControl.continueWorkflowThread(id: threadId, appStore: appStore)
                            appStore.popSessionDetail()
                        }
                    }
                },
                onCancel: {
                    sessionDetailStore.showRestoreSelection = false
                }
            )
        }
    }

    private func developerDiagnosticsFooter(_ diagnostics: SessionDetailDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(EchoDesign.subtle) { showDiagnostics.toggle() }
            } label: {
                Text(showDiagnostics ? "Hide diagnostics" : "Developer diagnostics")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            if showDiagnostics {
                diagnosticsSection(diagnostics)
            }
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
            Button {
                appStore.popSessionDetail()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Timeline")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if sessionDetailStore.memory?.session.isActive == true {
                SessionControlBar(compact: true)
            }
        }
        .padding(.horizontal, EchoDesign.containerRadius)
        .padding(.vertical, 12)
    }

    // MARK: - Load states

    private var degradedBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Partial memory")
                    .font(.system(size: 13, weight: .semibold))
                Text(sessionDetailStore.diagnostics?.summaryLine ?? "Some data was reconstructed.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
    }

    private var failedStateView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "memorychip")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(EchoPalette.indigo.opacity(0.35))

            Text("Memory could not be loaded")
                .font(.system(size: 18, weight: .semibold))

            if let error = sessionDetailStore.loadError {
                Text(error.localizedDescription)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            if let diagnostics = sessionDetailStore.diagnostics {
                diagnosticsSection(diagnostics)
            } else {
                Text("The session may not exist in storage, or the database is still initializing.")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }

            Button("Try again") {
                Task { await sessionDetailStore.load(sessionId: sessionId) }
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(maxWidth: 420, alignment: .leading)
    }

    private func diagnosticsSection(_ diagnostics: SessionDetailDiagnostics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(EchoDesign.subtle) { showDiagnostics.toggle() }
            } label: {
                HStack {
                    sectionTitle("Diagnostics", icon: "stethoscope")
                    Spacer()
                    Image(systemName: showDiagnostics ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if showDiagnostics {
                if !diagnostics.notes.isEmpty {
                    ForEach(Array(diagnostics.notes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                ForEach(diagnostics.issues, id: \.self) { issue in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: issue.isBlocking ? "xmark.circle.fill" : "info.circle")
                            .font(.system(size: 11))
                            .foregroundStyle(issue.isBlocking ? .red : .secondary)
                        Text(issue.userMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 16) {
                    diagnosticStat("Events", value: "\(diagnostics.mergedEventCount)")
                    diagnosticStat("Persisted", value: "\(diagnostics.persistedEventCount)")
                    diagnosticStat("Live", value: "\(diagnostics.liveEventCount)")
                    diagnosticStat("Snapshot", value: diagnostics.hasSnapshot ? "Yes" : "No")
                }
            } else {
                Text(diagnostics.summaryLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(EchoDesign.cardPadding)
        .echoCard(material: .thinMaterial)
    }

    private func diagnosticStat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.quaternary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
        }
    }

    private func emptySection(title: String, icon: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title, icon: icon)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .padding(EchoDesign.cardPadding)
        .echoCard()
    }

    // MARK: - Header

    private func appCountLabel(_ memory: WorkflowMemory) -> Int {
        let fromEvents = Set(memory.events.map(\.appBundleId)).count
        return max(fromEvents, memory.session.appCount)
    }

    private func header(_ memory: WorkflowMemory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: memory.cluster.icon)
                    .font(.system(size: 12, weight: .medium))
                Text(memory.cluster.label)
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .foregroundStyle(EchoPalette.indigoSoft)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(EchoPalette.indigo.opacity(0.1)))

            Text(memory.session.title ?? "Untitled memory")
                .font(.system(size: 28, weight: .semibold))
                .lineLimit(3)

            HStack(spacing: 16) {
                Label(memory.session.startedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                Label(memory.session.duration.shortLabel, systemImage: "clock")
                Label("\(appCountLabel(memory)) apps", systemImage: "square.grid.2x2")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Continuity

    private func continuitySection(_ memory: WorkflowMemory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Continuity", icon: "point.topleft.down.to.point.bottomright.curvepath")

            HStack(spacing: 20) {
                continuityMeter(score: memory.continuityScore, label: "Flow preserved")
                VStack(alignment: .leading, spacing: 8) {
                    Text(continuityNarrative(memory))
                        .font(.system(size: 14))
                        .foregroundStyle(.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(Int(memory.session.focusScore * 100))% focus · \(memory.interruptions.count) pauses")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(EchoDesign.cardPadding)
        .echoCard()
    }

    private func continuityNarrative(_ memory: WorkflowMemory) -> String {
        if memory.continuityScore >= 0.75 {
            return "This session held a clear thread of attention with few breaks."
        }
        if memory.interruptions.count >= 3 {
            return "Your attention fragmented across several pauses — a scattered but honest record."
        }
        return "A working memory with natural shifts between contexts."
    }

    private func continuityMeter(score: Double, label: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.06), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: score)
                    .stroke(
                        EchoPalette.premiumGradient,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Text("\(Int(score * 100))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
            .frame(width: 64, height: 64)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 72)
        }
    }

    // MARK: - Rhythm

    private func rhythmSection(_ memory: WorkflowMemory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Focus rhythm", icon: "waveform.path")
            if memory.events.isEmpty {
                Text("Activity timeline will appear once events are captured.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                MiniTimelineView(
                    segments: SessionTimelineBuilder.segments(from: memory.events),
                    focusIntensity: SessionTimelineBuilder.focusIntensity(from: memory.events)
                )
            }
        }
        .padding(EchoDesign.cardPadding)
        .echoCard()
    }

    // MARK: - Phases

    private func phasesSection(_ memory: WorkflowMemory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Workflow phases", icon: "rectangle.split.3x1")

            VStack(spacing: 0) {
                ForEach(Array(memory.phases.enumerated()), id: \.element.id) { index, phase in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(EchoPalette.indigo.opacity(0.55))
                                .frame(width: 8, height: 8)
                            if index < memory.phases.count - 1 {
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                EchoPalette.indigo.opacity(0.25),
                                                EchoPalette.indigo.opacity(0.05)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 2)
                            }
                        }
                        .frame(width: 10)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(phase.title)
                                .font(.system(size: 14, weight: .medium))
                            HStack(spacing: 8) {
                                Text(phase.duration.shortLabel)
                                Text("·")
                                Text(phase.startedAt, style: .time)
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(EchoDesign.cardPadding)
        .echoCard()
    }

    // MARK: - Transitions

    private func transitionsSection(_ memory: WorkflowMemory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("App transitions", icon: "arrow.left.arrow.right")

            ForEach(memory.appTransitions.prefix(20)) { t in
                AppTransitionRow(t: t)
            }
        }
        .padding(EchoDesign.cardPadding)
        .echoCard()
    }

    // MARK: - Browser

    private func browserSection(_ memory: WorkflowMemory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Web context", icon: "globe")
            FlowLayout(spacing: 8) {
                ForEach(memory.browserContexts) { ctx in
                    Text(ctx.domain)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.primary.opacity(0.05)))
                }
            }
        }
        .padding(EchoDesign.cardPadding)
        .echoCard()
    }

    // MARK: - Interruptions

    private func interruptionsSection(_ memory: WorkflowMemory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Interruptions", icon: "pause.circle")
            ForEach(memory.interruptions) { gap in
                HStack {
                    Text("Pause")
                        .font(.system(size: 13))
                    Spacer()
                    Text(gap.duration.shortLabel)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(EchoDesign.cardPadding)
        .echoCard()
    }

    // MARK: - Restore

    private func restoreSection(_ memory: WorkflowMemory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Continue this memory", icon: "arrow.uturn.backward.circle")

            Text("Reopen the apps and places that held your thread of thought.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            if memory.restorePlan.items.isEmpty {
                Text("No restore points were captured.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                let grouped = Dictionary(grouping: memory.restorePlan.items, by: \.kind)
                ForEach(RestoreItem.RestoreKind.allCases, id: \.self) { kind in
                    if let items = grouped[kind], !items.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(restoreGroupTitle(kind))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                            ForEach(items.prefix(6)) { item in
                                HStack(spacing: 10) {
                                    Image(systemName: restoreIcon(item.kind))
                                        .frame(width: 16)
                                        .foregroundStyle(EchoPalette.indigoSoft)
                                    Text(item.label)
                                        .font(.system(size: 13))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                if sessionDetailStore.isRestoring {
                    ProgressView(value: sessionDetailStore.restoreProgress)
                        .tint(EchoPalette.indigo)
                }

                Button {
                    sessionDetailStore.prepareRestoreSelection()
                } label: {
                    HStack {
                        if sessionDetailStore.isRestoring {
                            ProgressView().scaleEffect(0.7)
                        }
                        Text("Resume Workflow")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(sessionDetailStore.isRestoring)
            }
        }
        .padding(EchoDesign.cardPadding)
        .echoCard()
    }

    private func restoreGroupTitle(_ kind: RestoreItem.RestoreKind) -> String {
        switch kind {
        case .application: return "Applications"
        case .url, .browserPage: return "Browser"
        case .folder: return "Folders"
        case .document: return "Documents"
        case .terminalDirectory: return "Terminal"
        case .workspace: return "Projects"
        }
    }

    private func restoreIcon(_ kind: RestoreItem.RestoreKind) -> String {
        switch kind {
        case .application: return "app"
        case .url, .browserPage: return "globe"
        case .folder: return "folder"
        case .document: return "doc"
        case .terminalDirectory: return "terminal"
        case .workspace: return "macwindow"
        }
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(EchoPalette.indigoSoft)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
        }
    }
}

private struct AppTransitionRow: View {
    let t: AppTransition
    @State private var hovering = false
    
    var body: some View {
        HStack(spacing: 10) {
            AppIconView(bundleId: t.toBundleId, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                if let from = t.fromApp, from != t.toApp {
                    HStack(spacing: 6) {
                        Text(from)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(EchoPalette.indigoSoft)
                        Text(t.toApp)
                    }
                    .font(.system(size: 13, weight: .semibold))
                } else {
                    Text(t.toApp)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(t.timestamp, style: .time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.04) : Color.primary.opacity(0.01))
        )
        .echoPointingCursor()
        .onHover { hovering = $0 }
    }
}

// MARK: - Simple flow layout for domain chips

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? 400
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}
