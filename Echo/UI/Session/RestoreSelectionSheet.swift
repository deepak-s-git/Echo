import SwiftUI

struct RestoreSelectionSheet: View {
    @Binding var items: [RestoreWeighting.SelectableItem]
    let onRestore: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            // Obsidian Elevated Slate Background
            EchoPalette.graphiteElevated.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Resume Workflow")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Choose what to reopen. Items you focused on for 2+ minutes are pre-selected.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary.opacity(0.85))
                }
                .padding(.horizontal, 4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        categorySection("Applications", category: .application)
                        categorySection("Browser Tabs", category: .browserTab)
                        categorySection("Files & Documents", category: .file)
                        categorySection("Developer Projects", category: .workspace)
                        categorySection("Other Places", category: .other)
                    }
                    .padding(.horizontal, 2)
                }
                .frame(maxHeight: 380)

                Divider().opacity(0.35)

                HStack {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .echoPointingCursor()
                    
                    Spacer()
                    
                    let selected = items.filter(\.isSelected)
                    Button {
                        onRestore()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 11, weight: .bold))
                            Text(selected.isEmpty ? "Restore Selected" : "Restore \(selected.count) Items")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background {
                            if selected.isEmpty {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.12))
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(EchoPalette.premiumGradient)
                            }
                        }
                        .foregroundStyle(selected.isEmpty ? Color.secondary : Color.white)
                        .shadow(color: selected.isEmpty ? .clear : EchoPalette.indigo.opacity(0.2), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(selected.isEmpty)
                    .echoPointingCursor()
                }
                .padding(.horizontal, 4)
            }
            .padding(24)
        }
        .frame(width: 480, height: 530)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(EchoPalette.stroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func categorySection(
        _ title: String,
        category: RestoreWeighting.SelectableItem.Category
    ) -> some View {
        let group = items.enumerated().filter { $0.element.category == category }
        if !group.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(EchoPalette.indigoSoft)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .padding(.leading, 4)
                
                VStack(spacing: 6) {
                    ForEach(group, id: \.element.id) { index, item in
                        RestoreItemRow(
                            isSelected: binding(for: index),
                            label: item.item.label,
                            iconName: iconName(for: category)
                        )
                    }
                }
            }
        }
    }

    private func iconName(for category: RestoreWeighting.SelectableItem.Category) -> String {
        switch category {
        case .application: return "app.fill"
        case .browserTab: return "globe"
        case .file: return "doc.text.fill"
        case .workspace: return "macwindow"
        case .other: return "ellipsis.circle.fill"
        }
    }

    private func binding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { items[index].isSelected },
            set: { items[index].isSelected = $0 }
        )
    }
}

private struct RestoreItemRow: View {
    @Binding var isSelected: Bool
    let label: String
    let iconName: String
    
    @State private var hovering = false
    
    var body: some View {
        Button {
            withAnimation(EchoDesign.subtle) {
                isSelected.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? EchoPalette.live : Color.primary.opacity(0.35))
                    .scaleEffect(isSelected ? 1.05 : 1.0)
                    .animation(EchoDesign.subtle, value: isSelected)
                
                Image(systemName: iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(EchoPalette.indigoSoft)
                    .frame(width: 14)
                
                Text(label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.70))
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background {
                RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                    .fill(isSelected ? EchoPalette.indigo.opacity(0.08) : (hovering ? Color.white.opacity(0.03) : Color.clear))
            }
            .overlay(
                RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                    .strokeBorder(isSelected ? EchoPalette.indigo.opacity(0.35) : (hovering ? Color.white.opacity(0.12) : EchoPalette.stroke), lineWidth: 0.5)
            )
            .scaleEffect(hovering ? 1.006 : 1.0)
            .animation(EchoDesign.subtle, value: hovering)
            .echoHoverHighlight()
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
    }
}
