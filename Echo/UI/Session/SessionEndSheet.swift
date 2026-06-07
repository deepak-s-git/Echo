import SwiftUI

struct SessionEndSheet: View {
    let request: SessionEndRequest

    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var sessionControl: SessionControlStore
    @State private var title: String = ""
    @State private var tagsText: String = ""
    @State private var showDeleteConfirm = false
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("End session")
                .font(.system(size: 18, weight: .semibold))

            Text("Name this session, add tags, or delete it permanently.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            TextField("Session Name", text: $title)
                .textFieldStyle(.roundedBorder)
                .disabled(isWorking)

            TextField("Tags (comma separated)", text: $tagsText)
                .textFieldStyle(.roundedBorder)
                .disabled(isWorking)

            HStack {
                Button("Cancel") {
                    appStore.dismissEndSession()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isWorking)

                Button("Delete Session", role: .destructive) {
                    showDeleteConfirm = true
                }
                .disabled(isWorking)

                Spacer()

                Button("Save & End") {
                    Task { await saveAndEnd() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear { title = request.suggestedTitle }
        .confirmationDialog(
            "Delete this memory permanently?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteSession() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Activities, snapshots, and restore data will be removed.")
        }
    }

    private func saveAndEnd() async {
        isWorking = true
        defer { isWorking = false }
        let tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        sessionControl.confirmEndSession(
            title: title.isEmpty ? request.suggestedTitle : title,
            tags: tags,
            appStore: appStore
        )
    }

    private func deleteSession() async {
        isWorking = true
        defer { isWorking = false }
        await sessionControl.deleteSession(id: request.sessionId, appStore: appStore)
    }
}

struct SessionRenameSheet: View {
    let draft: SessionRenameDraft

    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var sessionControl: SessionControlStore
    @State private var title: String = ""
    @State private var tagsText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Rename memory")
                .font(.system(size: 18, weight: .semibold))

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextField("Tags (comma separated)", text: $tagsText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { appStore.renameSessionDraft = nil }
                Spacer()
                Button("Save") {
                    Task {
                        let tags = tagsText
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        await sessionControl.renameSession(
                            id: draft.sessionId,
                            title: title,
                            tags: tags
                        )
                        appStore.renameSessionDraft = nil
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            title = draft.title
            tagsText = draft.tags.joined(separator: ", ")
        }
    }
}

struct WorkflowThreadRenameSheet: View {
    let draft: WorkflowThreadRenameDraft

    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var sessionControl: SessionControlStore
    @State private var title: String = ""
    @State private var tagsText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Rename workflow")
                .font(.system(size: 18, weight: .semibold))

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextField("Tags (comma separated)", text: $tagsText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { appStore.renameThreadDraft = nil }
                Spacer()
                Button("Save") {
                    Task {
                        let tags = tagsText
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        await sessionControl.renameWorkflowThread(
                            id: draft.threadId,
                            title: title,
                            tags: tags
                        )
                        appStore.renameThreadDraft = nil
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 400)
        .onAppear {
            title = draft.title
            tagsText = draft.tags.joined(separator: ", ")
        }
    }
}
