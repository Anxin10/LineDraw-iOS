import XCTest
final class LineDrawUITests:XCTestCase {
    var app:XCUIApplication!
    override func setUp(){continueAfterFailure=false;app=XCUIApplication()}
    func launch(_ options:[String]=[]){app.launchArguments=["--ui-testing","-AppleLanguages","(zh-Hant)","-AppleLocale","zh_TW"]+options;app.launch()}
    func screenshot(_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    func reveal(_ element:XCUIElement){for _ in 0..<8{if element.isHittable{return};app.swipeUp()}}
    func testConsentDeclineLocksAndAcceptOpensApp(){
        launch(["--consent-test"])
        let decline=app.buttons["declineConsent"];reveal(decline);decline.tap()
        XCTAssertTrue(app.staticTexts["consentDeclined"].exists);XCTAssertFalse(app.tabBars.buttons["抽選"].exists)
        app.buttons["acceptConsent"].tap();XCTAssertTrue(app.buttons["openFilters"].waitForExistence(timeout:5))
    }
    func testMultipleFiltersAndManualUndo(){
        launch();app.buttons["openFilters"].tap()
        app.buttons["filterStatus:ready"].tap();app.buttons["filterStatus:notStarted"].tap()
        let taipei=app.buttons["filterCity:台北市"];reveal(taipei);taipei.tap();app.buttons["filterCity:台中市"].tap();screenshot("multi-select-filters");app.buttons["doneFilters"].tap()
        let detail=app.buttons["detail:demo:0"];reveal(detail);detail.tap()
        let mark=app.buttons["markManual"];reveal(mark);mark.tap();reveal(app.buttons["undoManual"]);XCTAssertTrue(app.buttons["undoManual"].waitForExistence(timeout:5));screenshot("manual-complete")
        app.buttons["undoManual"].tap();XCTAssertTrue(app.buttons["markManual"].exists);app.buttons["closeDetail"].tap()
        reveal(app.buttons["select:demo:0"]);XCTAssertTrue(app.buttons["select:demo:0"].isEnabled)
    }
    func testOfflineBatchAndHistory(){
        launch();app.buttons["selectAll"].tap();screenshot("catalog-selected-light")
        app.buttons["startBatch"].tap();app.buttons["confirmStart"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["示範完成，沒有操作 LINE。"].waitForExistence(timeout:15))
        app.tabBars.buttons["紀錄"].tap();XCTAssertTrue(app.staticTexts["已送出"].firstMatch.waitForExistence(timeout:5));screenshot("history-light")
    }
    func testDeviceSetupShowsRequirementsWithoutStartingAutomation(){
        launch();app.tabBars.buttons["設定"].tap();app.buttons["deviceSetup"].tap()
        XCTAssertTrue(app.staticTexts["手機自主模式 · 實驗版"].waitForExistence(timeout:5))
        reveal(app.buttons["startPhonePairing"]);XCTAssertTrue(app.buttons["startPhonePairing"].isEnabled);screenshot("device-setup-glass")
        let probe=app.buttons["deviceOfflineProbe"];reveal(probe)
        XCTAssertTrue(probe.exists);XCTAssertFalse(probe.isEnabled)
        XCTAssertFalse(app.buttons["checkDeviceConnection"].isEnabled)
    }
    func testPhonePairingCanCancelWithoutCreatingCredentials(){
        launch();app.tabBars.buttons["設定"].tap();app.buttons["deviceSetup"].tap()
        let start=app.buttons["startPhonePairing"];reveal(start);start.tap()
        let cancel=app.buttons["cancelPhonePairing"];reveal(cancel)
        XCTAssertTrue(cancel.waitForExistence(timeout:5));screenshot("phone-pairing-waiting")
        cancel.tap();XCTAssertTrue(start.waitForExistence(timeout:5));XCTAssertTrue(start.isEnabled)
        XCTAssertTrue(app.staticTexts["配對已取消，未建立連線或更動憑證。"].exists)
        let check=app.buttons["checkDeviceConnection"];reveal(check);XCTAssertFalse(check.isEnabled)
    }
    func testDarkLargeTextSettings(){
        launch(["--dark","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"])
        screenshot("catalog-dark-accessibility")
        app.tabBars.buttons["設定"].tap();XCTAssertTrue(app.staticTexts["LineDraw"].waitForExistence(timeout:5));screenshot("settings-dark-accessibility")
        XCTAssertFalse(app.buttons["登入"].exists)
    }
}
