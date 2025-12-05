import SwiftUI
import AppKit

public struct SettingsView: View {
    @State private var settings = AppSettings()
    @AppStorage("historyLayoutStyle") private var layoutStyleRaw: String = "horizontal"
    @AppStorage("appLanguage") private var appLanguage: String = "zh-Hans"
    @AppStorage("panelPositionVertical") private var panelPositionVertical: Double = 0
    @AppStorage("panelPositionHorizontal") private var panelPositionHorizontal: Double = 0
    private let settingsStore = SettingsStore()
    private let store = IndexStore.shared
    public init() {}
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
            Text(L("settings.title"))
                .font(.system(size: 16, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                Text(L("settings.section.general"))
                    .font(.system(size: 13, weight: .medium))
                VStack(spacing: 6) {
                    HStack {
                        Text(L("settings.retentionDays"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Stepper(value: $settings.historyRetentionDays, in: 7...365) {
                            Text("\(settings.historyRetentionDays)")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 120)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    HStack {
                        Text(L("settings.maxItems"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Stepper(value: $settings.historyMaxItems, in: 50...500, step: 50) {
                            Text("\(settings.historyMaxItems)")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 120)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    HStack {
                        Text(L("settings.appLanguage"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Picker("", selection: $appLanguage) {
                            Text(L("language.zh")).tag("zh-Hans")
                            Text(L("language.en")).tag("en")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    HStack {
                        Text(L("settings.historyLayout"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Picker("", selection: Binding(get: { HistoryLayoutStyle(rawValue: layoutStyleRaw) ?? .horizontal }, set: { layoutStyleRaw = $0.rawValue })) {
                            Text(L("settings.historyLayout.horizontal")).tag(HistoryLayoutStyle.horizontal)
                            Text(L("settings.historyLayout.grid")).tag(HistoryLayoutStyle.grid)
                            Text(L("settings.historyLayout.vertical")).tag(HistoryLayoutStyle.vertical)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    HStack {
                        Text(L("settings.panelPosition"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        Group {
                            switch HistoryLayoutStyle(rawValue: layoutStyleRaw) ?? .horizontal {
                            case .grid:
                                Text(L("settings.panelPosition.unavailableForGrid"))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            case .horizontal:
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L("settings.panelPosition.vertical"))
                                        .font(.system(size: 12))
                                    Slider(value: $panelPositionVertical, in: -100...100, step: 1) {
                                        Text("")
                                    }
                                    .frame(width: 160)
                                }
                            case .vertical:
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L("settings.panelPosition.horizontal"))
                                        .font(.system(size: 12))
                                    Slider(value: $panelPositionHorizontal, in: -100...100, step: 1) {
                                        Text("")
                                    }
                                    .frame(width: 160)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
            .padding(10)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: AppTheme.shadowColor, radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(L("backup.title"))
                    .font(.system(size: 13, weight: .medium))
                VStack(spacing: 6) {
                    HStack {
                        Button(L("backup.export")) { exportBackup() }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button(L("backup.import")) { importBackup() }
                            .buttonStyle(.bordered)
                        Text(L("backup.importWarning"))
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
            .padding(10)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: AppTheme.shadowColor, radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(L("shortcuts.title"))
                    .font(.system(size: 13, weight: .medium))
                VStack(spacing: 6) {
                    HStack {
                        Text(L("shortcuts.panel"))
                            .font(.system(size: 13))
                            .frame(width: 80, alignment: .leading)
                        Spacer()
                        ShortcutRecorder(shortcut: Binding(get: { settings.shortcuts.showPanel }, set: { settings.shortcuts.showPanel = $0 }))
                            .frame(width: 160, height: 22)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
            .padding(10)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: AppTheme.shadowColor, radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(L("about.title"))
                    .font(.system(size: 13, weight: .medium))
                VStack(spacing: 6) {
                    HStack {
                        Text(L("about.text"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
            .padding(10)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius))
            .shadow(color: AppTheme.shadowColor, radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cornerRadius)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
            )
        }
        .padding(10)
        }
        .frame(width: 360)
        .background(AppTheme.panelBackground)
        .controlSize(.small)
        .onAppear { settings = settingsStore.load() }
        .onChange(of: appLanguage) { _ in }
        .onChange(of: settings) { s in
            try? settingsStore.save(s)
            HotkeyService.shared?.unregisterAll()
            HotkeyService.shared?.registerShowPanel()
            HotkeyService.shared?.registerStackToggle()
        }
        .onChange(of: panelPositionVertical) { _ in }
        .onChange(of: panelPositionHorizontal) { _ in }
    }
    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["json"]
        panel.nameFieldStringValue = "ClipCatBackup.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? store.exportBackup(to: url)
        }
    }
    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            try? store.importBackup(from: url)
        }
    }
}
