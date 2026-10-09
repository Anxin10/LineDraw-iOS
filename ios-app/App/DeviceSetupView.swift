import SwiftUI
import UniformTypeIdentifiers
import LineDrawCore

struct DeviceSetupView:View {
    @EnvironmentObject var model:AppModel
    @State private var pairingImport=false
    @State private var ddiImport=false
    @State private var ddiBuild=DDIManager.cachedBuild
    
    var body:some View{List{
        Section{Label("手機自主模式 · 實驗版",systemImage:"iphone.gen3.radiowaves.left.and.right").font(.headline);Text("iOS 26 以上可在手機完成配對與準備必要檔案。簽署並安裝 LineDraw 與 DeviceRunner 後，日常只需開啟 VPN、選活動、按開始。").foregroundStyle(.secondary)}
        Section("首次設定"){
            DisclosureGroup("簽署安裝後的準備步驟"){
            Label("開啟 iPhone 開發者模式",systemImage:"1.circle")
            Label("安裝並信任 LineDraw DeviceRunner",systemImage:"2.circle")
            Text("Runner 與原本 Mac 使用的 WDA 分開，避免影響已可用版本。").font(.footnote).foregroundStyle(.secondary)
            Label("連上 Wi-Fi 並開啟 LocalDevVPN",systemImage:"3.circle")
            Text("系統開發者模式、開發者信任與 VPN 授權需由你在設定確認；App 無法代按。首次開啟開發者模式可能需要重新啟動手機。").font(.footnote).foregroundStyle(.secondary)
            }
            LabeledContent("本機配對",value:model.hasDevicePairing ? "已保存":"尚未配對")
        }
        PhonePairingSection(pairing:model.phonePairing)
        Section("開發者磁碟映像 DDI"){
            LabeledContent("離線檔案",value:ddiBuild.map{"已就緒 · "+$0} ?? "啟動時自動準備")
            Button("準備必要檔案"){model.prepareDeviceFiles()}.disabled(model.locked).accessibilityIdentifier("prepareDeviceFiles")
            Text("啟動時自動驗證快取，缺檔優先載入隨附映像，再從固定版本的開發工具鏡像下載約 17 MB；驗證 iOS Cryptex 格式與完整性。下載失敗不會覆蓋原有檔案。掛載可能需要連網向 Apple 取得簽署。").font(.footnote).foregroundStyle(.secondary)
        }
        Section("進階與修復"){
            DisclosureGroup("手動匯入與移除"){
                Button("匯入本機配對檔"){
                    let doc=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
                    for name in ["device.plist","device.pairing"] {
                        let file=doc.appendingPathComponent(name)
                        if let data=try? Data(contentsOf:file), (try? DeviceSecrets.save(data)) != nil {
                            model.hasDevicePairing=true
                            model.notice="配對檔已直接匯入並保存！"
                            try? FileManager.default.removeItem(at:file)
                            return
                        }
                    }
                    pairingImport=true
                }.disabled(model.locked).accessibilityIdentifier("importDevicePairing")
                .fileImporter(isPresented:$pairingImport,allowedContentTypes:[.data,.xml,.propertyList]){result in do{let url=try result.get();let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}};guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)<1_000_000 else{throw LineDrawError.message("配對檔過大。")};model.importDevicePairing(try Data(contentsOf:url))}catch{model.error=error.localizedDescription}}
                Button("手動匯入 DDI"){ddiImport=true}.disabled(model.locked)
                .fileImporter(isPresented:$ddiImport,allowedContentTypes:[.data],allowsMultipleSelection:true){result in do{try DeviceSecrets.importDDI(result.get());ddiBuild=DDIManager.cachedBuild;model.notice="DDI 檔案已匯入；將在啟動時驗證相容性。"}catch{model.error=error.localizedDescription}}
                if model.hasDevicePairing{Button("移除本機配對檔",role:.destructive){model.clearDevicePairing()}.disabled(model.locked)}
            }
            Text("重開機後先解鎖、連上 Wi-Fi 並開啟 VPN，再按檢查啟動。配對失效時可直接在手機重新配對；不需要重新匯入電腦檔案。").font(.footnote).foregroundStyle(.secondary)
        }
        Section("目前狀態"){
            Text(model.deviceStage)
            Button("檢查啟動（不抽選）"){model.checkDeviceConnection()}.disabled(model.locked || !model.hasDevicePairing).accessibilityIdentifier("checkDeviceConnection")
            #if DEBUG
            Button("速度驗證（5 筆，不抽選）"){model.runDeviceSpeedProbe()}.disabled(model.locked || !model.hasDevicePairing)
            Button("離線實機驗證（20 筆，不抽選）"){model.runDeviceProbe()}.disabled(model.locked || !model.hasDevicePairing).accessibilityIdentifier("deviceOfflineProbe")
            Text("開發測試：可先拔除 USB 再按此按鈕。手機會自行開啟 Safari 本機測試頁，完成後回此頁查看結果。").font(.footnote).foregroundStyle(.secondary)
            #endif
            if model.busy{Button("取消準備或啟動",role:.destructive){model.cancelDeviceSetup()}}
            Text("設定完成後回抽選分頁開始。啟動過程不會自動試點座標；只有你選定的本輪活動會進入抽選。").font(.footnote).foregroundStyle(.secondary)
        }
        Section("執行與停止"){
            Text("請維持解鎖與 VPN 連線。切到 LINE 後，App 以 iOS 可取消的背景工作執行本輪佇列；工作被系統結束時立即停止，不會暗中重試。")
            Text("可在 iOS 工作進度取消，或回到 LineDraw 按停止。鎖屏、重開機、強制關閉 App 後不會自行繼續抽選。")
            Text("配對檔只保存在這支手機的鑰匙圈，不會進入診斷或分享檔案。").font(.footnote).foregroundStyle(.secondary)
        }
    }.onChange(of:model.busy){_,busy in if !busy{ddiBuild=DDIManager.cachedBuild}}
        .onChange(of:model.phonePairing.running){_,running in if !running{ddiBuild=DDIManager.cachedBuild}}
        .navigationTitle("手機自主模式").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !model.hasDevicePairing {
                let doc=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
                for name in ["device.plist","device.pairing"] {
                    let file=doc.appendingPathComponent(name)
                    if let data=try? Data(contentsOf:file), (try? DeviceSecrets.save(data)) != nil {
                        model.hasDevicePairing=true
                        model.notice="已自動載入本機配對檔！"
                        try? FileManager.default.removeItem(at:file)
                        break
                    }
                }
            }
        }
    }
}

private struct PhonePairingSection:View {
    @EnvironmentObject var model:AppModel
    @ObservedObject var pairing:PhonePairing
    var body:some View {
        Section("在這支 iPhone 配對"){
            if !pairing.running {
                Button(model.hasDevicePairing ? "重新在手機配對":"開始手機配對"){model.startPhonePairing()}
                    .disabled(model.locked).accessibilityIdentifier("startPhonePairing")
                Text("開始後允許「本機網路」，再到「設定 → 隱私權與安全性 → 開發者模式」，選擇 Pair with LineDraw（與 LineDraw 配對）。").font(.footnote).foregroundStyle(.secondary)
                Text("PIN 會顯示在 App 與即時動態；在設定輸入即可。只有驗證成功才更新鑰匙圈，取消或失敗保留原本配對。").font(.footnote).foregroundStyle(.secondary)
            }
            Text(pairing.message).accessibilityIdentifier("phonePairingStatus")
            if pairing.running {
                if let pin=pairing.pin {
                    Text(pin).font(.largeTitle.monospacedDigit().bold()).frame(maxWidth:.infinity).padding().glassPanel().privacySensitive()
                        .accessibilityLabel("配對 PIN，"+pin.map(String.init).joined(separator:"，"))
                }
                if let end=pairing.expiresAt{HStack{Text("本次配對剩餘時間");Spacer();Text(timerInterval:Date()...max(Date(),end),countsDown:true).monospacedDigit().frame(width:64)}}
                if !pairing.liveActivityAvailable{Text("若未顯示即時動態，可切回 LineDraw 查看 PIN，再回設定輸入。").font(.footnote).foregroundStyle(.secondary)}
                Button("取消手機配對",role:.destructive){pairing.cancel()}.accessibilityIdentifier("cancelPhonePairing")
            }
        }
    }
}
