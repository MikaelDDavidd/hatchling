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
                    PhonePanel.shared.close()
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { selected = tab.rawValue }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : .white.opacity(hovered == tab ? 0.6 : 0.38))
                        if isSelected {
                            Text(tab.label)
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(0.1)
                                .foregroundStyle(.white)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.8, anchor: .leading)),
                                    removal: .opacity
                                ))
                        }
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 20)
                    .background {
                        // Concentric with the selector: 9 outside, 3 inset, 6 inside.
                        if isSelected {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(.white.opacity(0.12))
                                .matchedGeometryEffect(id: "pill", in: pill)
                        } else if hovered == tab {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.05))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(tab.label)
                .onHover { h in withAnimation(NotchAnimation.micro) { hovered = h ? tab : (hovered == tab ? nil : hovered) } }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.05)))
    }
}

struct PanelTabContent: View {
    var appState: AppState
    @AppStorage(SettingsKey.selectedPanelTab) private var selected: String = SettingsDefaults.selectedPanelTab
    @State private var previousOrder = 0

    @ObservedObject private var phonePanel = PhonePanel.shared
    private var tab: PanelTab { PanelTab(rawValue: selected) ?? .agents }

    var body: some View {
        // Slide the way the pill went: right for a tab further along, left for one before.
        let forward = tab.order >= previousOrder
        ZStack(alignment: .top) {
            if phonePanel.open {
                PhonePairingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
            } else {
            switch tab {
            case .files:
                FilesTrayView().transition(slide(forward))
            case .notes:
                NotesView().transition(slide(forward))
            case .agents:
                VStack(spacing: 0) {
                    HatchStage(appState: appState)
                    SessionListView(appState: appState, onlySessionId: nil)
                }
                .transition(slide(forward))
            }
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
