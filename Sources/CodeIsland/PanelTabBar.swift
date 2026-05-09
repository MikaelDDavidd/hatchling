import SwiftUI

enum PanelTab: String, CaseIterable {
    case agents
    case files
    case notes

    var label: String {
        switch self {
        case .agents: return "AGENTS"
        case .files:  return "FILES"
        case .notes:  return "NOTES"
        }
    }
}

struct PanelTabSelector: View {
    @AppStorage(SettingsKey.selectedPanelTab) private var selected: String = SettingsDefaults.selectedPanelTab

    var body: some View {
        HStack(spacing: 1) {
            ForEach(PanelTab.allCases, id: \.rawValue) { tab in
                let isSelected = selected == tab.rawValue
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selected = tab.rawValue }
                } label: {
                    PixelText(
                        text: tab.label,
                        color: isSelected ? Color(red: 0.3, green: 0.85, blue: 0.4) : .white.opacity(0.3),
                        pixelSize: 1.3
                    )
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4)
                    .background(
                        Rectangle().fill(isSelected ? .white.opacity(0.1) : .clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .background(Rectangle().fill(.white.opacity(0.05)))
        .overlay(Rectangle().stroke(.white.opacity(0.1), lineWidth: 1))
    }
}

struct PanelTabContent: View {
    var appState: AppState
    @AppStorage(SettingsKey.selectedPanelTab) private var selected: String = SettingsDefaults.selectedPanelTab

    var body: some View {
        Group {
            switch selected {
            case PanelTab.files.rawValue:
                FilesTrayView()
            case PanelTab.notes.rawValue:
                NotesView()
            default:
                SessionListView(appState: appState, onlySessionId: nil)
            }
        }
    }
}
