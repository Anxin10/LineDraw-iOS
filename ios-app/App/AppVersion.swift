import Foundation

enum AppVersion {
    static var display:String {
        let version=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "未知版本"
        let build=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
