import SwiftUI

enum PanelTab: String, CaseIterable {
    case agents
    case files
    case notes

    var label: String {
        switch self {
        case .agents: return L10n.shared["tab_agents"]
        case .files:  return L10n.shared["tab_files"]
        case .notes:  return L10n.shared["tab_notes"]
        }
    }

    var icon: String {
        switch self {
        case .agents: return "rectangle.stack.fill"
        case .files:  return "tray.full.fill"
        case .notes:  return "note.text"
        }
    }

    /// Where the tab sits, so switching can slide the content the way the indicator moved.
    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// Icons for every tab, the name only on the chosen one, and a quiet highlight that slides
/// between them. Neutral on purpose: the panel's one colour is reserved for the agents.
struct PanelTabSelector: View {
    @AppStorage(SettingsKey.selectedPanelTab) private var selected: String = SettingsDefaults.selectedPanelTab
    @Namespace private var pill
    @State private var hovered: PanelTab?

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases, id: \.rawValue) { tab in
                let isSelected = selected == tab.rawValue
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { selected = tab.rawValue }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : .white.opacity(hovered == tab ? 0.6 : 0.35))
                        if isSelected {
                            Text(tab.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.8, anchor: .leading)),
                                    removal: .opacity
                                ))
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(.white.opacity(0.11))
                                .matchedGeometryEffect(id: "pill", in: pill)
                        } else if hovered == tab {
                            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(0.05))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(tab.label)
                .onHover { h in withAnimation(NotchAnimation.micro) { hovered = h ? tab : (hovered == tab ? nil : hovered) } }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.04)))
    }
}

struct PanelTabContent: View {
    var appState: AppState
    @AppStorage(SettingsKey.selectedPanelTab) private var selected: String = SettingsDefaults.selectedPanelTab
    @State private var previousOrder = 0

    private var tab: PanelTab { PanelTab(rawValue: selected) ?? .agents }

    var body: some View {
        // Slide the way the pill went: right for a tab further along, left for one before.
        let forward = tab.order >= previousOrder
        ZStack(alignment: .top) {
            switch tab {
            case .files:
                FilesTrayView().transition(slide(forward))
            case .notes:
                NotesView().transition(slide(forward))
            case .agents:
                SessionListView(appState: appState, onlySessionId: nil).transition(slide(forward))
            }
        }
        .clipped()
        .onChange(of: selected) { _, _ in
            DispatchQueue.main.async { previousOrder = tab.order }
        }
        .onAppear { previousOrder = tab.order }
    }

    private func slide(_ forward: Bool) -> AnyTransition {
        .asymmetric(
            insertion: .offset(x: forward ? 40 : -40).combined(with: .opacity),
            removal: .offset(x: forward ? -40 : 40).combined(with: .opacity)
        )
    }
}
