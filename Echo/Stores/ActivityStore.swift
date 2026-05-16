import SwiftUI
import Combine

@MainActor
final class ActivityStore: ObservableObject {

    // MARK: - Instant focus layer (never debounced)

    @Published private(set) var focusHeadline: String = "—"
    @Published private(set) var currentAppName: String?
    @Published private(set) var currentAppBundleId: String?
    @Published private(set) var currentSession: Session?
    @Published private(set) var isSessionActive: Bool = false
    @Published private(set) var isSessionPaused: Bool = false
    @Published private(set) var recordingState: WorkflowRecordingState = .idle

    var isRecording: Bool { recordingState == .recording || recordingState == .paused }
    @Published private(set) var liveFocusScore: Double = 0
    @Published private(set) var focusLabel: String = "Exploring"

    // MARK: - Stable workflow intelligence (debounced)

    @Published private(set) var workflowIdentity: String = "Your workflow"

    /// Stable identity for sidebar / menu bar / timeline banner.
    var workflowTitle: String { workflowIdentity }

    // MARK: - Display (feed immediate; timeline debounced)

    @Published private(set) var recentEvents: [ActivityEvent] = []
    @Published private(set) var timelineSegments: [TimelineSegment] = []
    @Published private(set) var focusIntensity: Double = 1

    @Published private(set) var sessionDuration: TimeInterval = 0
    @Published private(set) var threadAccumulatedDuration: TimeInterval = 0
    @Published private(set) var focusScore: Double = 0

    private var eventBuffer: [ActivityEvent] = []
    private var timelineRebuildTask: Task<Void, Never>?
    private var identitySettleTask: Task<Void, Never>?
    private var durationTask: Task<Void, Never>?
    private var lastDurationPublish: TimeInterval = 0
    private var lastIdentityChangeTime: Date = .distantPast

    init() {}

    deinit {
        timelineRebuildTask?.cancel()
        identitySettleTask?.cancel()
        durationTask?.cancel()
    }

    // MARK: - Session lifecycle

    func enterIdleMode() {
        identitySettleTask?.cancel()
        timelineRebuildTask?.cancel()
        durationTask?.cancel()
        durationTask = nil
        currentSession = nil
        isSessionActive = false
        isSessionPaused = false
        recordingState = .idle
        currentAppName = nil
        currentAppBundleId = nil
        focusHeadline = "—"
        workflowIdentity = "Your workflow"
        recentEvents = []
        timelineSegments = []
        eventBuffer = []
        threadAccumulatedDuration = 0
        focusScore = 0
        liveFocusScore = 0
        focusIntensity = 1
        lastDurationPublish = 0
    }

    func setRestoring(_ restoring: Bool) {
        recordingState = restoring ? .restoring : (isSessionPaused ? .paused : (isSessionActive ? .recording : .idle))
    }

    func sessionDidStart(_ session: Session, threadAccumulated: TimeInterval = 0) {
        currentSession = session
        isSessionActive = true
        isSessionPaused = false
        recordingState = .recording
        threadAccumulatedDuration = threadAccumulated
        seedWorkflowIdentity(from: session)
        eventBuffer.removeAll()
        recentEvents.removeAll()
        timelineSegments.removeAll()
        focusIntensity = 1
        liveFocusScore = 0
        focusLabel = "Exploring"
        sessionDuration = 0
        focusScore = 0
        focusHeadline = "—"
        currentAppName = nil
        currentAppBundleId = nil
        startDurationTimer()
    }

    func restore(session: Session, events: [ActivityEvent]) {
        currentSession = session
        isSessionActive = true
        isSessionPaused = session.lifecycleState == .paused
        recordingState = isSessionPaused ? .paused : .recording
        seedWorkflowIdentity(from: session)
        eventBuffer = normalize(events.suffix(EchoConfig.maxLiveEvents))
        sessionDuration = Date().timeIntervalSince(session.startedAt)
        focusScore = session.focusScore
        applyInstantFocusFromBuffer()
        recentEvents = eventBuffer
        publishTimelineNow()
        startDurationTimer()
    }

    /// Persists session metadata + stable identity from SessionEngine (not instant layer).
    func applyPersistedSession(_ session: Session) {
        currentSession = session
        if let title = session.title, !title.isEmpty {
            commitWorkflowIdentity(title, force: false)
        }
    }

    func sessionDidPause() {
        isSessionPaused = true
        recordingState = .paused
        durationTask?.cancel()
        durationTask = nil
    }

    func sessionDidResumeCapture() {
        isSessionPaused = false
        recordingState = .recording
        startDurationTimer()
    }

    func sessionDidEnd(_ session: Session) {
        enterIdleMode()
    }

    /// Recording armed — no segment in DB until first meaningful activity.
    func beginRecording(threadTitle: String?, threadAccumulated: TimeInterval) {
        currentSession = nil
        isSessionActive = true
        isSessionPaused = false
        recordingState = .recording
        threadAccumulatedDuration = threadAccumulated
        workflowIdentity = threadTitle ?? "Your workflow"
        focusHeadline = "—"
        currentAppName = nil
        currentAppBundleId = nil
        eventBuffer.removeAll()
        recentEvents.removeAll()
        timelineSegments.removeAll()
        sessionDuration = 0
        lastDurationPublish = 0
        liveFocusScore = 0
        focusScore = 0
        focusLabel = "Exploring"
        focusIntensity = 1
        durationTask?.cancel()
        durationTask = nil
    }

    /// First meaningful event created a segment — start block timer at zero.
    func segmentDidStart(_ session: Session) {
        currentSession = session
        sessionDuration = 0
        lastDurationPublish = 0
        if let title = session.title, !title.isEmpty {
            workflowIdentity = title
        }
        startDurationTimer()
    }

    // MARK: - Hot path

    func applyLiveEvent(_ event: ActivityEvent) {
        let normalized = normalizedEvent(event)

        if shouldMergeWindowEnrichment(normalized) {
            mergeWindowEnrichment(normalized)
            return
        }

        eventBuffer.append(normalized)
        trimBuffer()
        recentEvents = eventBuffer

        switch normalized.type {
        case .appFocus:
            applyInstantFocus(normalized)
            scheduleWorkflowIdentityRecompute()
        case .appSwitch:
            applyFocusMetricsQuick()
        default:
            break
        }

        scheduleTimelineRebuild()
    }

    func ingest(_ event: ActivityEvent) { applyLiveEvent(event) }
    func append(_ event: ActivityEvent) { applyLiveEvent(event) }

    /// Events for the live session buffer when reconstructing session detail.
    func liveEvents(for sessionId: UUID) -> [ActivityEvent] {
        guard currentSession?.id == sessionId else { return [] }
        return eventBuffer
    }

    /// Stable identity suggestion for SessionEngine persistence.
    func computeStableWorkflowIdentity(startedAt: Date) -> String {
        StableWorkflowTitleGenerator.generate(
            from: eventBuffer,
            startedAt: startedAt,
            anchorBundleId: currentAppBundleId,
            previousIdentity: workflowIdentity
        )
    }

    // MARK: - Instant focus

    private func applyInstantFocus(_ event: ActivityEvent) {
        currentAppName = event.appName
        currentAppBundleId = event.appBundleId
        focusHeadline = LiveTitleFormatter.instantHeadline(
            bundleId: event.appBundleId,
            appName: event.appName,
            windowTitle: event.windowTitle
        )
        applyFocusMetricsQuick()
    }

    private func applyInstantFocusFromBuffer() {
        if let focus = eventBuffer.last(where: { $0.type == .appFocus }) {
            applyInstantFocus(focus)
        } else {
            applyFocusMetricsQuick()
        }
    }

    // MARK: - Stable workflow identity

    private func scheduleWorkflowIdentityRecompute() {
        identitySettleTask?.cancel()
        let anchoredBundle = currentAppBundleId
        identitySettleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(EchoConfig.workflowIdentitySettleInterval))
            guard !Task.isCancelled else { return }
            guard let self, self.currentAppBundleId == anchoredBundle else { return }
            self.recomputeWorkflowIdentity()
        }
    }

    private func recomputeWorkflowIdentity() {
        guard let session = currentSession else { return }
        let title = StableWorkflowTitleGenerator.generate(
            from: eventBuffer,
            startedAt: session.startedAt,
            anchorBundleId: currentAppBundleId,
            previousIdentity: workflowIdentity
        )
        commitWorkflowIdentity(title, force: false)
    }

    private func commitWorkflowIdentity(_ title: String, force: Bool) {
        guard title != workflowIdentity else { return }
        let now = Date()
        if !force,
           workflowIdentity != "Your workflow",
           now.timeIntervalSince(lastIdentityChangeTime) < EchoConfig.workflowIdentityMinChangeInterval {
            return
        }
        workflowIdentity = title
        lastIdentityChangeTime = now
    }

    private func seedWorkflowIdentity(from session: Session) {
        if let title = session.title, !title.isEmpty {
            workflowIdentity = title
            lastIdentityChangeTime = Date()
        } else {
            workflowIdentity = "Your workflow"
        }
    }

    // MARK: - Helpers

    private func normalizedEvent(_ event: ActivityEvent) -> ActivityEvent {
        var copy = event
        copy.appName = AppMetadataResolver.displayName(
            bundleId: event.appBundleId,
            rawName: event.appName
        )
        return copy
    }

    private func shouldMergeWindowEnrichment(_ event: ActivityEvent) -> Bool {
        guard event.type == .appFocus,
              let title = event.windowTitle, !title.isEmpty
        else { return false }
        guard let lastIdx = eventBuffer.indices.last else { return false }
        let last = eventBuffer[lastIdx]
        return last.type == .appFocus
            && last.appBundleId == event.appBundleId
            && last.windowTitle == nil
    }

    private func mergeWindowEnrichment(_ event: ActivityEvent) {
        guard let lastIdx = eventBuffer.indices.last else { return }
        eventBuffer[lastIdx].windowTitle = event.windowTitle
        recentEvents = eventBuffer
        applyInstantFocus(eventBuffer[lastIdx])
        scheduleTimelineRebuild()
    }

    private func normalize(_ events: ArraySlice<ActivityEvent>) -> [ActivityEvent] {
        events.map { normalizedEvent($0) }
    }

    private func trimBuffer() {
        if eventBuffer.count > EchoConfig.maxLiveEvents {
            eventBuffer.removeFirst(eventBuffer.count - EchoConfig.maxLiveEvents)
        }
    }

    private func scheduleTimelineRebuild() {
        timelineRebuildTask?.cancel()
        timelineRebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(EchoConfig.timelineRebuildInterval))
            guard !Task.isCancelled else { return }
            self?.publishTimelineNow()
        }
    }

    private func publishTimelineNow() {
        timelineSegments = SessionTimelineBuilder.segments(from: eventBuffer)
        focusIntensity = SessionTimelineBuilder.focusIntensity(from: eventBuffer)
    }

    private func applyFocusMetricsQuick() {
        liveFocusScore = computeLiveFocusScore()
        focusLabel = label(for: liveFocusScore)
    }

    private func computeLiveFocusScore() -> Double {
        guard !eventBuffer.isEmpty else { return focusScore }
        let window = eventBuffer.suffix(min(16, eventBuffer.count))
        let switches = window.filter { $0.type == .appSwitch }.count
        let rate = Double(switches) / Double(window.count)
        return min(max(1 - rate, 0), 1)
    }

    private func label(for score: Double) -> String {
        switch score {
        case 0.75...: return "Deep focus"
        case 0.5..<0.75: return "Steady flow"
        case 0.3..<0.5: return "Context switching"
        default: return "Exploring"
        }
    }

    private func startDurationTimer() {
        durationTask?.cancel()
        durationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let session = self.currentSession else { continue }
                let duration = Date().timeIntervalSince(session.startedAt)
                let rounded = floor(duration)
                guard rounded != self.lastDurationPublish else { continue }
                self.lastDurationPublish = rounded
                self.sessionDuration = duration
            }
        }
    }
}
