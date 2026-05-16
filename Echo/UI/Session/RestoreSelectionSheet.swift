import SwiftUI

struct RestoreSelectionSheet: View {
    @Binding var items: [RestoreWeighting.SelectableItem]
    let onRestore: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resume workflow")
                .font(.system(size: 18, weight: .semibold))
            Text("Choose what to reopen. Items you focused on for 2+ minutes are pre-selected.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    categorySection("Apps", category: .application)
                    categorySection("Tabs", category: .browserTab)
                    categorySection("Files", category: .file)
                    categorySection("Projects", category: .workspace)
                    categorySection("Other", category: .other)
                }
            }
            .frame(maxHeight: 360)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Restore selected") { onRestore() }
                    .buttonStyle(.borderedProminent)
                    .disabled(items.filter(\.isSelected).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480, height: 520)
    }

    @ViewBuilder
    private func categorySection(
        _ title: String,
        category: RestoreWeighting.SelectableItem.Category
    ) -> some View {
        let group = items.enumerated().filter { $0.element.category == category }
        if !group.isEmpty {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
            ForEach(group, id: \.element.id) { index, item in
                Toggle(isOn: binding(for: index)) {
                    Text(item.item.label)
                        .font(.system(size: 13))
                        .lineLimit(1)
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private func binding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { items[index].isSelected },
            set: { items[index].isSelected = $0 }
        )
    }
}
