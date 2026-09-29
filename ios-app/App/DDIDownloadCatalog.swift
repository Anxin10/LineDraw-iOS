import Foundation

// doronz88/DeveloperDiskImage mirror, pinned 2026-09-29. Apple payloads are not
// redistributed in the source archive. Cryptex integrity is checked before installation.
enum DDIDownloadCatalog {
    struct File {let name:String;let size:Int;let sha256:String}
    static let base=URL(string:"https://raw.githubusercontent.com/doronz88/DeveloperDiskImage/7e29c5905cf3c53870a26854127cce9496ec6480/PersonalizedImages/Xcode_iOS_DDI_Cryptex/")!
    static let files:[File]=[
        .init(name:"BuildManifest.plist",size:804946,sha256:"27385d7582b03b36bb3104e22b520aee0c47d72fecb4e8ecfe12ef5d966c7012"),
        .init(name:"Image.dmg",size:15895040,sha256:"873097f695a8b9734e2abc54f795a8874d40ff6fd11208ecb01ef29534c7c176"),
        .init(name:"Image.dmg.trustcache",size:1895,sha256:"f7f21986074eee03a215aca16ecfc78d6bf183600d8a0d2fb691f9896782e6f0"),
        .init(name:"Image.dmg.cryptex_info",size:430,sha256:"edf49aef55aacc063d4d7be05b713bb545ce2993b3f62bcc15eccd75e610ee6c"),
        .init(name:"Image.dmg.root_hash",size:229,sha256:"3543fad2805b88119695c417e12679380b3b5a2742994bbcc839c8e2de5d7302")
    ]
}
