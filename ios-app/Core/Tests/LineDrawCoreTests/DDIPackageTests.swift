import XCTest
import CryptoKit
@testable import LineDrawCore

final class DDIPackageTests:XCTestCase {
    var root:URL!
    override func setUpWithError()throws{root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)}
    override func tearDownWithError()throws{try FileManager.default.removeItem(at:root)}
    func package(_ name:String,build:String="test1")throws->URL{
        let folder=root.appendingPathComponent(name);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var parts=[String:Any]()
        for (file,key) in DDIPackage.payloads {
            let data=Data((build+file).utf8);try data.write(to:folder.appendingPathComponent(file));parts[key]=["Digest":Data(SHA384.hash(data:data))]
        }
        let manifest:[String:Any]=["ProductBuildVersion":build,"SupportedProductTypes":["TestPhone"],"BuildIdentities":[["Ap,TargetType":"ioscryptex","Info":["Variant":"Developer Disk Image Cryptex","DeviceClass":"ioscryptexap"],"Manifest":parts]]]
        try PropertyListSerialization.data(fromPropertyList:manifest,format:.xml,options:0).write(to:folder.appendingPathComponent("BuildManifest.plist"));return folder
    }
    func testValidInstallAndAtomicReplacement()throws{
        let one=try package("one"),two=try package("two",build:"test2"),cache=root.appendingPathComponent("cache")
        try DDIPackage.install(one,to:cache)
        try DDIPackage.install(two,to:cache)
        XCTAssertEqual(try DDIPackage.validate(cache).build,"test2")
    }
    func testCorruptOrPartialUpdateKeepsWorkingCache()throws{
        let one=try package("one"),bad=try package("bad",build:"test2"),cache=root.appendingPathComponent("cache")
        try DDIPackage.install(one,to:cache)
        try Data("corrupt".utf8).write(to:bad.appendingPathComponent("Image.dmg"))
        XCTAssertThrowsError(try DDIPackage.install(bad,to:cache))
        try FileManager.default.removeItem(at:bad.appendingPathComponent("Image.dmg.root_hash"))
        XCTAssertThrowsError(try DDIPackage.install(bad,to:cache))
        XCTAssertEqual(try DDIPackage.validate(cache).build,"test1")
    }
    func testWrongPlatformRejectedBeforeInstall()throws{
        let source=try package("source"),cache=root.appendingPathComponent("cache"),file=source.appendingPathComponent("BuildManifest.plist")
        let text=try String(contentsOf:file).replacingOccurrences(of:"ioscryptex",with:"tvoscryptex")
        try Data(text.utf8).write(to:file)
        XCTAssertThrowsError(try DDIPackage.install(source,to:cache))
        XCTAssertFalse(FileManager.default.fileExists(atPath:cache.path))
    }
    func testSymlinkPayloadRejected()throws{
        let source=try package("source"),payload=source.appendingPathComponent("Image.dmg"),outside=root.appendingPathComponent("outside")
        try FileManager.default.moveItem(at:payload,to:outside)
        try FileManager.default.createSymbolicLink(at:payload,withDestinationURL:outside)
        XCTAssertThrowsError(try DDIPackage.validate(source))
    }
}
