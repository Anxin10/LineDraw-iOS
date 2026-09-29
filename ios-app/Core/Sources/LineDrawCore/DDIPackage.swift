import Foundation
import CryptoKit

/// Integrity and compatibility checks shared by automatic and manual DDI setup.
/// Apple still authorizes/personalizes the image when the device mounts it.
public enum DDIPackage {
    public static let payloads=["Image.dmg":"Cryptex1,GenericDmg", "Image.dmg.trustcache":"Cryptex1,GenericTrustCache", "Image.dmg.cryptex_info":"Cryptex1,CryptexInfoPlist", "Image.dmg.root_hash":"Cryptex1,GenericVolume"]
    public static let filenames=["BuildManifest.plist"]+payloads.keys.sorted()
    public struct Info:Sendable {public let build:String;public let models:[String]}
    public static func validate(_ directory:URL)throws->Info {
        guard try directory.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink != true else{throw LineDrawError.message("DDI 目錄不合法。")}
        func read(_ name:String)throws->Data{
            let url=directory.appendingPathComponent(name)
            let a=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            let limit=name=="Image.dmg" ? 100_000_000:2_000_000
            guard a.isRegularFile==true,a.isSymbolicLink != true,let size=a.fileSize,size>0,size<=limit else{throw LineDrawError.message("DDI 檔案不完整或大小不正確。")}
            return try Data(contentsOf:url,options:.mappedIfSafe)
        }
        guard let manifest=try PropertyListSerialization.propertyList(from:read("BuildManifest.plist"),format:nil) as? [String:Any],
              let identities=manifest["BuildIdentities"] as? [[String:Any]],let build=manifest["ProductBuildVersion"] as? String,
              let models=manifest["SupportedProductTypes"] as? [String] else{throw LineDrawError.message("DDI 描述檔不完整。")}
        let matches=identities.filter{(($0["Info"] as? [String:Any])?["Variant"] as? String)?.hasSuffix("Developer Disk Image Cryptex")==true}
        guard matches.count==1,let parts=matches[0]["Manifest"] as? [String:[String:Any]] else{throw LineDrawError.message("DDI 不是支援的 Cryptex 映像。")}
        // Cryptex DDI is generic (ioscryptexap), not selected from the legacy
        // SupportedProductTypes list. Apple's personalization/mount is authoritative.
        guard matches[0]["Ap,TargetType"] as? String == "ioscryptex",
              (matches[0]["Info"] as? [String:Any])?["DeviceClass"] as? String == "ioscryptexap" else{throw LineDrawError.message("DDI 不屬於 iOS Cryptex 平台。")}
        for (name,key) in payloads {
            guard let expected=parts[key]?["Digest"] as? Data,expected.count==48,Data(SHA384.hash(data:try read(name)))==expected else{throw LineDrawError.message("DDI \(name) 驗證失敗；原本檔案已保留。")}
        }
        return Info(build:build,models:models)
    }
    /// Commit only a completely validated package; never merge partial downloads into a working cache.
    public static func install(_ source:URL,to destination:URL)throws{
        _=try validate(source)
        let fm=FileManager.default,parent=destination.deletingLastPathComponent()
        try fm.createDirectory(at:parent,withIntermediateDirectories:true)
        let staging=parent.appendingPathComponent("DDI-stage-"+UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:staging,withIntermediateDirectories:false);defer{try? fm.removeItem(at:staging)}
        for name in filenames{try fm.copyItem(at:source.appendingPathComponent(name),to:staging.appendingPathComponent(name))}
        _=try validate(staging)
        #if os(iOS)
        for name in filenames{try fm.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:staging.appendingPathComponent(name).path)}
        #endif
        var values=URLResourceValues();values.isExcludedFromBackup=true;var stage=staging;try stage.setResourceValues(values)
        if fm.fileExists(atPath:destination.path){_=try fm.replaceItemAt(destination,withItemAt:staging)}else{try fm.moveItem(at:staging,to:destination)}
    }
}
