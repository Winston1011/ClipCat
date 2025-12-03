import Foundation

// 设置存储：使用 Application Support 目录保存/加载应用设置
public final class SettingsStore: SettingsStoreProtocol {
    private let url: URL
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    public init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let app = dir.appendingPathComponent("ClipCat")
        try? FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        url = app.appendingPathComponent("settings.json")
    }
    public func load() -> AppSettings {
        // 若存在配置文件则解码返回，否则使用默认值
        if let d = try? Data(contentsOf: url), let s = try? decoder.decode(AppSettings.self, from: d) { return s }
        return AppSettings()
    }
    public func save(_ settings: AppSettings) throws {
        let d = try encoder.encode(settings)
        try d.write(to: url)
    }
}
