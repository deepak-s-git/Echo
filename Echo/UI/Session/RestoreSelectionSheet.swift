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
                    VStack(alignment: .leading, spacing: 16) {
                        let groups = buildHierarchicalGroups()
                        ForEach(groups) { group in
                            AppGroupSection(
                                group: group,
                                isAppSelected: parentBinding(for: group),
                                childBinding: { index in childBinding(for: index, in: group) },
                                profileBinding: { profile in profileBinding(for: profile, in: group) },
                                items: $items
                            )
                        }
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

    // MARK: - Hierarchical Grouping Logic

    fileprivate struct HierarchicalGroup: Identifiable {
        let id: String
        let name: String
        let iconName: String
        let appIndex: Int?
        var profiles: [ProfileGroup]
    }

    fileprivate struct ProfileGroup: Identifiable {
        let id: String
        let name: String?
        var children: [ChildItem]
    }

    fileprivate struct ChildItem: Identifiable {
        let id: UUID
        let index: Int
        let label: String
        let kind: RestoreItem.RestoreKind
    }

    fileprivate struct SelectableItemWithIndex {
        let index: Int
        let item: RestoreWeighting.SelectableItem
    }

    private func setSelection(forIndex index: Int, isSelected: Bool) {
        let targetItem = items[index].item
        
        // Find all items that match the target item physically
        for i in 0..<items.count {
            let other = items[i].item
            var isMatch = false
            
            if targetItem.kind == .application && other.kind == .application {
                isMatch = targetItem.bundleId == other.bundleId
            } else if (targetItem.kind == .url || targetItem.kind == .browserPage) &&
                      (other.kind == .url || other.kind == .browserPage) {
                isMatch = targetItem.url == other.url
            } else if (targetItem.kind == .document || targetItem.kind == .folder || targetItem.kind == .workspace) &&
                      (other.kind == .document || other.kind == .folder || other.kind == .workspace) {
                isMatch = targetItem.path == other.path && targetItem.path != nil
            } else if targetItem.kind == .terminalDirectory && other.kind == .terminalDirectory {
                isMatch = targetItem.workingDirectory == other.workingDirectory && targetItem.workingDirectory != nil
            }
            
            if isMatch {
                items[i].isSelected = isSelected
            }
        }
    }

    private func buildHierarchicalGroups() -> [HierarchicalGroup] {
        var groups: [HierarchicalGroup] = []
        var groupedIndices = Set<Int>()
        
        // Find all bundleIds and their associated application items
        var appIndicesByBundleId: [String: Int] = [:]
        for (index, item) in items.enumerated() {
            if item.item.kind == .application, let bundleId = item.item.bundleId {
                appIndicesByBundleId[bundleId] = index
                groupedIndices.insert(index)
            }
        }
        
        // Also track all unique bundleIds from children
        var allBundleIds = Set<String>(appIndicesByBundleId.keys)
        for item in items {
            if let bundleId = item.item.bundleId {
                allBundleIds.insert(bundleId)
            }
        }
        
        // For each bundleId, create an App Group
        for bundleId in allBundleIds.sorted() {
            let appIndex = appIndicesByBundleId[bundleId]
            let name: String
            if let idx = appIndex {
                name = items[idx].item.label
            } else {
                name = appName(for: bundleId)
            }
            
            // Find all children (non-application items) belonging to this bundleId
            var children: [SelectableItemWithIndex] = []
            for (index, item) in items.enumerated() {
                if item.item.kind != .application, item.item.bundleId == bundleId {
                    children.append(SelectableItemWithIndex(index: index, item: item))
                    groupedIndices.insert(index)
                }
            }
            
            // Group these children by profileName
            var profileGroups: [ProfileGroup] = []
            let groupedByProfile = Dictionary(grouping: children, by: { $0.item.item.profileName })
            
            // Only show profile headers if there are multiple unique profiles (including nil/Other)
            let showProfileHeaders = groupedByProfile.keys.count > 1
            
            for (profileName, profileChildren) in groupedByProfile {
                let childItems = profileChildren.map { child in
                    ChildItem(
                        id: child.item.item.id,
                        index: child.index,
                        label: child.item.item.label,
                        kind: child.item.item.kind
                    )
                }
                let profileId = profileName ?? "no-profile"
                let profileNameLabel: String?
                if let pName = profileName {
                    profileNameLabel = showProfileHeaders ? "Profile: \(pName)" : nil
                } else {
                    profileNameLabel = showProfileHeaders ? "Other Tabs" : nil
                }
                profileGroups.append(ProfileGroup(id: profileId, name: profileNameLabel, children: childItems))
            }
            
            profileGroups.sort { a, b in
                if a.id == "no-profile" { return true }
                if b.id == "no-profile" { return false }
                return a.id < b.id
            }
            
            groups.append(HierarchicalGroup(
                id: "app:\(bundleId)",
                name: name,
                iconName: appIconName(for: bundleId),
                appIndex: appIndex,
                profiles: profileGroups
            ))
        }
        
        // 1. Files & Documents (folders and documents)
        let generalFiles = items.enumerated().filter { index, item in
            let matches = item.item.bundleId == nil && (item.item.kind == .document || item.item.kind == .folder)
            if matches { groupedIndices.insert(index) }
            return matches
        }
        if !generalFiles.isEmpty {
            let children = generalFiles.map { index, item in
                ChildItem(id: item.item.id, index: index, label: item.item.label, kind: item.item.kind)
            }
            groups.append(HierarchicalGroup(
                id: "general-files",
                name: "Files & Documents",
                iconName: "doc.text.fill",
                appIndex: nil,
                profiles: [ProfileGroup(id: "no-profile", name: nil, children: children)]
            ))
        }
        
        // 2. Developer Projects / Workspaces
        let generalWorkspaces = items.enumerated().filter { index, item in
            let matches = item.item.bundleId == nil && (item.item.kind == .workspace || item.item.kind == .terminalDirectory)
            if matches { groupedIndices.insert(index) }
            return matches
        }
        if !generalWorkspaces.isEmpty {
            let children = generalWorkspaces.map { index, item in
                ChildItem(id: item.item.id, index: index, label: item.item.label, kind: item.item.kind)
            }
            groups.append(HierarchicalGroup(
                id: "general-workspaces",
                name: "Developer Projects",
                iconName: "macwindow",
                appIndex: nil,
                profiles: [ProfileGroup(id: "no-profile", name: nil, children: children)]
            ))
        }

        // 3. Safety Net for any remaining orphans
        var orphanChildren: [SelectableItemWithIndex] = []
        for (index, item) in items.enumerated() {
            if !groupedIndices.contains(index) {
                orphanChildren.append(SelectableItemWithIndex(index: index, item: item))
                groupedIndices.insert(index)
            }
        }
        
        if !orphanChildren.isEmpty {
            let docs = orphanChildren.filter { $0.item.item.kind == .document || $0.item.item.kind == .folder }
            let wss = orphanChildren.filter { $0.item.item.kind == .workspace || $0.item.item.kind == .terminalDirectory }
            let tabs = orphanChildren.filter { $0.item.item.kind == .browserPage || $0.item.item.kind == .url }
            let apps = orphanChildren.filter { $0.item.item.kind == .application }
            
            if !docs.isEmpty {
                let children = docs.map { ChildItem(id: $0.item.item.id, index: $0.index, label: $0.item.item.label, kind: $0.item.item.kind) }
                if let idx = groups.firstIndex(where: { $0.id == "general-files" }) {
                    groups[idx].profiles[0].children.append(contentsOf: children)
                } else {
                    groups.append(HierarchicalGroup(
                        id: "general-files",
                        name: "Files & Documents",
                        iconName: "doc.text.fill",
                        appIndex: nil,
                        profiles: [ProfileGroup(id: "no-profile", name: nil, children: children)]
                    ))
                }
            }
            if !wss.isEmpty {
                let children = wss.map { ChildItem(id: $0.item.item.id, index: $0.index, label: $0.item.item.label, kind: $0.item.item.kind) }
                if let idx = groups.firstIndex(where: { $0.id == "general-workspaces" }) {
                    groups[idx].profiles[0].children.append(contentsOf: children)
                } else {
                    groups.append(HierarchicalGroup(
                        id: "general-workspaces",
                        name: "Developer Projects",
                        iconName: "macwindow",
                        appIndex: nil,
                        profiles: [ProfileGroup(id: "no-profile", name: nil, children: children)]
                    ))
                }
            }
            if !tabs.isEmpty {
                let children = tabs.map { ChildItem(id: $0.item.item.id, index: $0.index, label: $0.item.item.label, kind: $0.item.item.kind) }
                if let idx = groups.firstIndex(where: { $0.id == "app:com.apple.Safari" }) {
                    if let pIdx = groups[idx].profiles.firstIndex(where: { $0.id == "no-profile" }) {
                        groups[idx].profiles[pIdx].children.append(contentsOf: children)
                    } else {
                        groups[idx].profiles.append(ProfileGroup(id: "no-profile", name: nil, children: children))
                    }
                } else {
                    groups.append(HierarchicalGroup(
                        id: "app:com.apple.Safari",
                        name: "Safari",
                        iconName: "safari",
                        appIndex: nil,
                        profiles: [ProfileGroup(id: "no-profile", name: nil, children: children)]
                    ))
                }
            }
            if !apps.isEmpty {
                for app in apps {
                    let bId = app.item.item.bundleId ?? "unknown-app"
                    groups.append(HierarchicalGroup(
                        id: "app:\(bId)",
                        name: app.item.item.label,
                        iconName: "app.fill",
                        appIndex: app.index,
                        profiles: []
                    ))
                }
            }
        }
        
        return groups
    }

    private func appName(for bundleId: String) -> String {
        if bundleId.contains("Chrome") { return "Google Chrome" }
        if bundleId.contains("Safari") { return "Safari" }
        if bundleId.contains("Arc") { return "Arc" }
        if bundleId.contains("Brave") { return "Brave Browser" }
        if bundleId.contains("Finder") { return "Finder" }
        if bundleId.contains("Preview") { return "Preview" }
        return bundleId.components(separatedBy: ".").last?.capitalized ?? bundleId
    }

    private func appIconName(for bundleId: String) -> String {
        if bundleId.contains("Chrome") { return "globe" }
        if bundleId.contains("Safari") { return "safari" }
        if bundleId.contains("Finder") { return "folder.fill" }
        if bundleId.contains("Preview") { return "doc.text.fill" }
        return "app.fill"
    }

    // MARK: - Selection Bindings

    private func parentBinding(for group: HierarchicalGroup) -> Binding<Bool> {
        Binding(
            get: {
                if let idx = group.appIndex {
                    return items[idx].isSelected
                }
                let childrenIndices = group.profiles.flatMap { $0.children.map(\.index) }
                if childrenIndices.isEmpty { return false }
                return childrenIndices.allSatisfy { items[$0].isSelected }
            },
            set: { isSelected in
                if let idx = group.appIndex {
                    setSelection(forIndex: idx, isSelected: isSelected)
                }
                let childrenIndices = group.profiles.flatMap { $0.children.map(\.index) }
                for idx in childrenIndices {
                    setSelection(forIndex: idx, isSelected: isSelected)
                }
            }
        )
    }

    private func profileBinding(for profile: ProfileGroup, in group: HierarchicalGroup) -> Binding<Bool> {
        Binding(
            get: {
                let childrenIndices = profile.children.map(\.index)
                if childrenIndices.isEmpty { return false }
                return childrenIndices.allSatisfy { items[$0].isSelected }
            },
            set: { isSelected in
                let childrenIndices = profile.children.map(\.index)
                for idx in childrenIndices {
                    setSelection(forIndex: idx, isSelected: isSelected)
                }
                
                // If any tab in the group becomes selected, the parent application must be selected
                if isSelected, let idx = group.appIndex {
                    setSelection(forIndex: idx, isSelected: true)
                }
            }
        )
    }

    private func childBinding(for index: Int, in group: HierarchicalGroup) -> Binding<Bool> {
        Binding(
            get: { items[index].isSelected },
            set: { isSelected in
                setSelection(forIndex: index, isSelected: isSelected)
                
                // If we select a child, automatically select the parent application as well
                if isSelected, let idx = group.appIndex {
                    setSelection(forIndex: idx, isSelected: true)
                }
                
                // If all children in the group are now unselected, also uncheck the parent app
                if !isSelected, let idx = group.appIndex {
                    let childrenIndices = group.profiles.flatMap { $0.children.map(\.index) }
                    let anyChildSelected = childrenIndices.contains { items[$0].isSelected }
                    if !anyChildSelected {
                        setSelection(forIndex: idx, isSelected: false)
                    }
                }
            }
        )
    }
}

// MARK: - Subviews

private struct AppGroupSection: View {
    let group: RestoreSelectionSheet.HierarchicalGroup
    @Binding var isAppSelected: Bool
    let childBinding: (Int) -> Binding<Bool>
    let profileBinding: (RestoreSelectionSheet.ProfileGroup) -> Binding<Bool>
    @Binding var items: [RestoreWeighting.SelectableItem]

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Application Group Header Row
            HStack(spacing: 8) {
                Button {
                    withAnimation(EchoDesign.subtle) {
                        isAppSelected.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isAppSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isAppSelected ? EchoPalette.live : Color.primary.opacity(0.35))
                            .scaleEffect(isAppSelected ? 1.05 : 1.0)
                        
                        Image(systemName: group.iconName)
                            .font(.system(size: 12))
                            .foregroundStyle(EchoPalette.indigoSoft)
                            .frame(width: 14)
                        
                        Text(group.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isAppSelected ? Color.primary : Color.primary.opacity(0.75))
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background {
                        RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                            .fill(isAppSelected ? EchoPalette.indigo.opacity(0.04) : Color.white.opacity(0.01))
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: EchoDesign.pillRadius, style: .continuous)
                            .strokeBorder(isAppSelected ? EchoPalette.indigo.opacity(0.20) : EchoPalette.stroke, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .echoPointingCursor()

                if hasSubItems {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .echoPointingCursor()
                }
            }

            // Children & Profiles List (Indented & Collapsible)
            if isExpanded && hasSubItems {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(group.profiles) { profile in
                        if let profileName = profile.name {
                            // Profile Sub-Header
                            VStack(alignment: .leading, spacing: 4) {
                                Button {
                                    withAnimation(EchoDesign.subtle) {
                                        let currentVal = profileBinding(profile).wrappedValue
                                        profileBinding(profile).wrappedValue = !currentVal
                                    }
                                } label: {
                                    let isProfileSelected = profileBinding(profile).wrappedValue
                                    HStack(spacing: 8) {
                                        Image(systemName: isProfileSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(isProfileSelected ? EchoPalette.live : Color.primary.opacity(0.3))
                                        
                                        Image(systemName: "person.crop.circle")
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color.secondary)
                                        
                                        Text(profileName)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(Color.secondary)
                                        
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 8)
                                    .background(Color.white.opacity(0.015), in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .echoPointingCursor()
                                .padding(.leading, 8)
                                
                                // Tabs/Children under Profile
                                VStack(spacing: 4) {
                                    ForEach(profile.children) { child in
                                        RestoreItemRow(
                                            isSelected: childBinding(child.index),
                                            label: child.label,
                                            iconName: iconName(for: child.kind)
                                        )
                                    }
                                }
                                .padding(.leading, 24)
                            }
                            .padding(.vertical, 2)
                        } else {
                            // Direct Children (No Profile Name)
                            VStack(spacing: 4) {
                                ForEach(profile.children) { child in
                                    RestoreItemRow(
                                        isSelected: childBinding(child.index),
                                        label: child.label,
                                        iconName: iconName(for: child.kind)
                                    )
                                }
                            }
                            .padding(.leading, 18)
                        }
                    }
                }
                .padding(.leading, 6)
            }
        }
    }

    private var hasSubItems: Bool {
        for profile in group.profiles {
            if !profile.children.isEmpty {
                return true
            }
        }
        return false
    }

    private func iconName(for kind: RestoreItem.RestoreKind) -> String {
        switch kind {
        case .application: return "app.fill"
        case .url, .browserPage: return "globe"
        case .folder: return "folder.fill"
        case .document: return "doc.text.fill"
        case .terminalDirectory: return "terminal.fill"
        case .workspace: return "macwindow"
        }
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
