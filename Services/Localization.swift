import Foundation

public func L(_ key: String) -> String {
    let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "zh-Hans"
    let code = (lang == "en") ? "en" : "zh_CN"
    if let path = Bundle.main.path(forResource: code, ofType: "lproj"), let b = Bundle(path: path) {
        return b.localizedString(forKey: key, value: nil, table: nil)
    }
    return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}
