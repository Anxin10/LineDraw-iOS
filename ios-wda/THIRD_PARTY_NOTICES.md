# 第三方元件

LineDraw 原創程式碼使用 PolyForm Noncommercial 1.0.0；下列上游元件保留原授權，不在我們的再授權範圍。依賴未 vendoring 到來源發行包；安裝後 node_modules 中仍保留各元件授權。

| 元件 | 版本 | 授權 |
|---|---|---|
| Appium | 3.8.0 | Apache-2.0 |
| Cheerio | 1.1.2 | MIT |
| FastXMLParser | 5.11.1 | MIT |
| XCUITestDriver | 12.13.2 | Apache-2.0 |
| WebDriverAgent | 16.12.10 | Apache-2.0 |

完整間接依賴版本見 package-lock.json；執行 `npm ci` 時由上游套件附帶其授權。WDA 與 Driver 由 setup.sh 固定版本安裝。
此 ios-wda 目錄不含 StikDebug、StikPair、TouchSynthesis 或 idevice 程式碼。iPhone App 在 ../ios-app/DeviceBridge/vendor/idevice 另含 MIT 授權的 idevice，其授權與聲明隨來源保留。
