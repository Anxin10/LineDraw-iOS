import SwiftUI
import UniformTypeIdentifiers
import LineDrawCore

struct HistoryView:View{
    @EnvironmentObject var model:AppModel
    @State private var query=""
    var body:some View{NavigationStack{List{
        Section{HStack{Image(systemName:"person.crop.circle").foregroundStyle(.blue);Text(model.profile);Spacer();Text(model.area.title).foregroundStyle(.secondary)}}
        if model.recordList.isEmpty{ContentUnavailableView("從第一筆開始",systemImage:"clock.arrow.circlepath",description:Text("送出、已完成與待確認，會分開保存在這裡。"))}
        ForEach(model.recordList.filter{query.isEmpty || "\($0.product) \($0.store)".localizedCaseInsensitiveContains(query)}){record in
            Section{VStack(alignment:.leading,spacing:10){HStack{StatusBadge(text:record.title,color:record.status=="REVIEW" ? .orange:.blue);Spacer();Text(dateText(record.updatedAt)).font(.caption).foregroundStyle(.secondary)};Text(record.product).font(.headline);Text(record.store).font(.subheadline).foregroundStyle(.secondary);Text(record.evidence).font(.footnote).foregroundStyle(.secondary)
                if record.status=="MANUAL"{Button("撤銷手動完成"){model.undo(record)}.disabled(model.locked)}
                else if record.canMarkManually,let draw=model.allDraws.first(where:{$0.activityKey==record.id}){Button("標記已完成"){model.mark(draw)}.disabled(model.locked)}
            }.padding(.vertical,5)}
        }
    }.navigationTitle("紀錄").searchable(text:$query,prompt:"搜尋紀錄").scrollContentBackground(.hidden).background{AppBackdrop()}.refreshable{await model.poll()}}}
}
struct SettingsView:View{
    @EnvironmentObject var model:AppModel
    @State private var showProfile=false;@State private var profileName="";@State private var showImport=false;@State private var showUnpair=false
    var body:some View{NavigationStack{Form{
        Section{HStack(spacing:14){Image(systemName:"ticket.fill").font(.title).foregroundStyle(.white).frame(width:52,height:52).background(.blue.gradient,in:RoundedRectangle(cornerRadius:15));VStack(alignment:.leading,spacing:4){Text("LineDraw").font(.title3.bold());Text("公開原始碼 · 無需登入").font(.subheadline).foregroundStyle(.secondary)};Spacer();StatusBadge(text:AppVersion.display)}}
        Section{Picker("執行方式",selection:Binding(get:{model.deviceMode},set:{model.chooseMode($0)})){Text("手機自主模式").tag(true);Text("Mac 輔助模式").tag(false)}.disabled(model.locked)
            NavigationLink{DeviceSetupView()}label:{Label("手機自主模式設定",systemImage:"iphone.gen3.radiowaves.left.and.right")}.accessibilityIdentifier("deviceSetup")
        }header:{Text("抽選引擎")}footer:{Text("iOS 26 以上手機自主模式：簽署安裝 App 與 Runner 後，可在手機完成配對與準備 DDI。執行前請連上 Wi-Fi 並開啟 LocalDevVPN。")}
        Section{NavigationLink{PairingView()}label:{Label{HStack{Text("Mac 輔助程式");Spacer();Text(model.pairing == nil ? "尚未配對":model.companionOnline ? "已連線":"已配對").foregroundStyle(.secondary)}}icon:{Image(systemName:"laptopcomputer").foregroundStyle(.blue)}}
            if model.pairing != nil{Button("解除配對",role:.destructive){showUnpair=true}.disabled(model.locked)}
        }header:{Text("裝置連線")}footer:{Text("Mac 與 iPhone 連接同一 Wi-Fi；Mac 透過 USB 與 WDA 執行抽選。手機單獨使用時可同步、篩選及管理紀錄。")}
        Section{Picker("目前設定檔",selection:Binding(get:{model.profile},set:{model.chooseProfile($0)})){ForEach(model.data.settings.profiles,id:\.self){Text($0).tag($0)}}.disabled(model.locked)
            Button{showProfile=true}label:{Label("新增設定檔",systemImage:"plus.circle")}.disabled(model.locked)
        }header:{Text("本機紀錄")}footer:{Text("設定檔不是 LINE 帳號。更換 LINE 帳號時，請自行切換到另一份設定檔，避免沿用抽選紀錄。")}
        Section{Toggle("自動加入店家好友",isOn:setting(\.autoFriend)).disabled(model.locked);Toggle("接續網站新增活動",isOn:setting(\.autoContinue)).disabled(model.locked)
        }header:{Text("抽選輔助")}footer:{Text("本輪結束後同步，沿用開始時的篩選接續新增活動，最多額外 3 輪；未選項目、已有紀錄與本輪失敗項目不會自動重排。載入 30 秒後重開一次，斷網最多等 60 秒。")}
        Section{Picker("抽選畫面查詢",selection:Binding(get:{model.data.settings.batchLookupMode ?? "standard"},set:{value in model.settings{$0.batchLookupMode=value}})){
            Text("精簡決策查詢").tag("compact");Text("相容查詢").tag("standard")
        }.disabled(model.locked)
        }header:{Text("手機抽選查詢")}footer:{Text("精簡模式只讀取抽選決策需要的文字，保留換頁驗證與防重送。需要新版 DeviceRunner；舊版缺少端點時回退相容查詢。速度仍受 LINE 載入影響。")}
        Section{Picker("漏抽掃描查詢",selection:Binding(get:{model.data.settings.scanLookupMode ?? "xml"},set:{value in model.settings{$0.scanLookupMode=value}})){
            Text("精簡查詢（新版 Runner）").tag("compact")
            Text("原生 JSON").tag("json")
            Text("XML 相容模式").tag("xml")
        }.disabled(model.locked)}footer:{Text("僅影響唯讀漏抽檢查。舊 Runner 不支援精簡端點時會回退 XML，待確認不會當成已抽完。")}
        Section{Picker("外觀",selection:Binding(get:{model.data.settings.appearance},set:{value in model.settings{$0.appearance=value}})){Text("跟隨系統").tag("system");Text("淺色").tag("light");Text("深色").tag("dark")}
            Toggle("減少透明效果",isOn:setting(\.reduceTransparency));Toggle("減少動態效果",isOn:setting(\.reduceMotion))
        }header:{Text("外觀與輔助使用")}footer:{Text("使用原生 Liquid Glass 導覽與控制元件，並支援系統字體大小、VoiceOver 和減少透明效果。")}
        Section{Button{model.chooseArea(.test);model.notice="已切換至五連結測試，請回到抽選分頁。"}label:{Label("五連結測試區",systemImage:"testtube.2")}.disabled(model.locked).accessibilityIdentifier("enterTests")
            Button{showImport=true}label:{Label("匯入測試清單",systemImage:"square.and.arrow.down")}.disabled(model.locked)
            Button{model.chooseArea(.demo);model.notice="已切換至離線示範，請回到抽選分頁。"}label:{Label("離線示範",systemImage:"play.rectangle")}.disabled(model.locked).accessibilityIdentifier("enterDemo")
            if model.area != .website{Button("返回網站清單"){model.chooseArea(.website)}.disabled(model.locked)}
        }header:{Text("測試與示範")}footer:{Text("實機測試會操作 LINE；離線示範不會。兩者的清單與紀錄均與網站分開。測試活動過期後可匯入新的 JSON 清單。")}
        Section{NavigationLink{DiagnosticsView()}label:{Label("診斷紀錄",systemImage:"stethoscope")};NavigationLink{DeclarationView()}label:{Label("使用說明",systemImage:"doc.text")};NavigationLink{LicenseView()}label:{Label("授權與第三方元件",systemImage:"curlybraces")};Link(destination:CatalogParser.sourceURL){Label("查看來源網站",systemImage:"globe")}}
        Section{NavigationLink("版本修正紀錄"){List{
            Section("1.1.10（33） · 2026/10/09"){
                Text("配對成功但必要檔案準備中斷時，顯示配對已保存，無需重複輸入 PIN。")
            }
            Section("1.1.9（32） · 2026/10/09"){
                Text("公開來源識別碼改用 Anxin10，App、Runner、背景工作與 Keychain 設定同步更新；新識別碼需要重新簽署及配對。")
            }
            Section("1.1.8（31） · 2026/10/09"){
                Text("設定與診斷頁統一讀取 App 的實際版本，避免顯示舊版 1.0。授權條款版本維持 1.0.0。")
                Text("新增新手機安裝與 GitHub fork 發布手冊；其他手機需要適用的簽署與自己的配對。")
            }
            Section("1.1.7（30） · 2026/10/09"){
                Text("Runner 工作階段啟動失敗時，清理連線後最多重試一次；僅限抽獎開始前且 App 在前景。")
                Text("取消或已建立工作階段時不重試，執行中的抽獎不會因此重送。")
            }
            Section("1.1.6（29） · 2026/10/09"){
                Text("正式手機抽選新增精簡決策查詢選項；只讀取決策需要的文字，保留換頁、點擊前驗證與防重送。")
                Text("新版 Runner 減少畫面外文字及不相關文字的可見性檢查，診斷分開記錄快照與節點處理耗時。")
                Text("實測五筆均已送出，共 13.95 秒，四筆低於 3 秒；仍不保證所有活動與網路都能達標。")
            }
            Section("1.1.5（28） · 2026/10/09"){
                Text("漏抽掃描新增原生 JSON 與新版 Runner 精簡查詢選項，XML 維持預設相容路徑。")
                Text("精簡端點一次取得快照，只回傳可見文字、按鈕與座標；不會送出抽獎。新路徑秒數仍需實機確認。")
            }
            Section("1.1.4（25） · 2026/10/09"){
                Text("新增唯讀漏抽檢查，優先讀取 XML；依店家與商品資訊確認畫面，未知狀態保留待確認。")
                Text("同五筆 XML 優先實測 15.82 秒；截圖搭配 OCR 較慢。未保證所有手機、活動或抽選送出能達 3 秒。")
            }
            Section("1.1.3（19） · 2026/10/09"){
                Text("畫面查詢等待上限由 4 秒放寬至 12 秒，回應後立即繼續；整筆仍以 30 秒為限。")
                Text("停止原因與取消來源優先保存，耗時明細保留最近 20 筆；返回 App 可查看停止位置。")
                Text("系統取消或控制連線中斷仍可能停止任務，未確認的點擊不會自動重送。")
            }
            Section("1.1.2（18） · 2026/10/08"){
                Text("最低系統版本調整為 iOS 26.0，背景工作依系統版本使用對應 API；底層連線元件同步重建。")
                Text("iOS 26 的手機配對及自主抽選仍需實機驗證。")
            }
            Section("1.1.1（17） · 2026/10/08"){
                Text("Funbox：缺少網站 ID 的有效活動可正常同步。")
                Text("跨店共用活動連結會標示待確認並暫停操作，其餘資料正常同步；既有抽選紀錄保留。")
                Text("新增 Funbox／陀螺獵人雙來源切換，各自同步並共用活動紀錄。")
                Text("修正舊資料同步摘要造成啟動閃退，以及 Debug 編譯錯誤。")
                Text("XML 查詢加入次數與期限限制。每輪 3 秒目標仍待實機驗證。")
            }
        }.navigationTitle("版本修正紀錄")}}
        Section{Text("資料保存在本機與已配對的 Mac。一般診斷不記錄聊天內容、帳號、原始畫面或抽選網址。").font(.footnote).foregroundStyle(.secondary)}
    }.navigationTitle("設定").scrollContentBackground(.hidden).background{AppBackdrop()}
        .alert("新增設定檔",isPresented:$showProfile){TextField("名稱",text:$profileName);Button("建立"){model.addProfile(profileName);profileName=""};Button("取消",role:.cancel){profileName=""}}message:{Text("每個設定檔使用獨立的本機抽選紀錄。")}
        .confirmationDialog("解除與 Mac 的配對？",isPresented:$showUnpair,titleVisibility:.visible){Button("解除配對",role:.destructive){Task{await model.unpair()}};Button("取消",role:.cancel){}}
        .fileImporter(isPresented:$showImport,allowedContentTypes:[.json]){result in do{let url=try result.get();let allowed=url.startAccessingSecurityScopedResource();defer{if allowed{url.stopAccessingSecurityScopedResource()}};let values=try url.resourceValues(forKeys:[.fileSizeKey]);guard (values.fileSize ?? 0)<500_000 else{throw LineDrawError.message("檔案過大。")};model.importTests(try Data(contentsOf:url))}catch{model.error=error.localizedDescription}}
    }}
    func setting(_ key:WritableKeyPath<AppSettings,Bool>)->Binding<Bool>{Binding(get:{model.data.settings[keyPath:key]},set:{value in model.settings{$0[keyPath:key]=value}})}
}
struct PairingView:View{
    @EnvironmentObject var model:AppModel
    @State private var raw="";@State private var scanning=false
    var body:some View{List{
        Section{VStack(alignment:.leading,spacing:16){HStack{Image(systemName:"iphone");Image(systemName:"link").font(.title3);Image(systemName:"laptopcomputer")}.font(.largeTitle).foregroundStyle(.blue);Text("把控制權交給你的 Mac").font(.title2.bold());Text("在 Mac 控制台連接 WDA，再按「配對 iPhone App」。掃描 QR Code，即可從手機開始批次。").foregroundStyle(.secondary)}}
        if let pairing=model.pairing{Section("已配對"){LabeledContent("電腦",value:pairing.name);LabeledContent("狀態",value:model.companionOnline ? "連線正常":"等待 Mac 上線");Button("重新整理連線"){Task{await model.poll()}}}}
        Section{Button{scanning=true}label:{Label("掃描 Mac 配對 QR Code",systemImage:"qrcode.viewfinder")}.disabled(model.locked)
            TextField("或貼上配對連結",text:$raw,axis:.vertical).textInputAutocapitalization(.never).autocorrectionDisabled().lineLimit(2...4).privacySensitive().accessibilityIdentifier("pairingText")
            Button{Task{await model.pair(raw);if model.pairing != nil{raw=""}}}label:{if model.busy{ProgressView()}else{Text("配對這部 Mac")}}.disabled(raw.isEmpty || model.locked)
        }footer:{Text("配對碼五分鐘有效，只能使用一次。QR Code 內含 Mac 憑證指紋，連線會驗證此指紋；無需網站帳號。")}
        Section("使用前"){Label("iPhone 與 Mac 連接同一 Wi-Fi",systemImage:"wifi");Label("USB 連接 iPhone，並完成 WDA 設定",systemImage:"cable.connector");Label("開始後維持解鎖，Mac 不要休眠",systemImage:"sun.max")}
    }.navigationTitle("Mac 配對").navigationBarTitleDisplayMode(.inline).sheet(isPresented:$scanning){QRScanner{value in scanning=false;raw=value}onError:{message in scanning=false;model.error=message}}}
}
struct DiagnosticsView:View{
    @EnvironmentObject var model:AppModel
    var body:some View{List{Section{Text(model.diagnosticsText).font(.footnote.monospaced()).textSelection(.enabled)};Section{ShareLink(item:model.diagnosticsText){Label("分享診斷",systemImage:"square.and.arrow.up")};Button("清除診斷",role:.destructive){model.clearDiagnostics()}}}.navigationTitle("診斷紀錄").navigationBarTitleDisplayMode(.inline)}
}
struct DeclarationView:View{var body:some View{List{ForEach(UsageDeclaration.paragraphs,id:\.self){Text($0)};Text("說明版本 \(UsageDeclaration.version)").font(.footnote).foregroundStyle(.secondary)}.navigationTitle("使用說明").navigationBarTitleDisplayMode(.inline)}}
struct LicenseView:View{var body:some View{List{
    Section("LineDraw 原創程式碼"){Text("PolyForm Noncommercial 1.0.0").font(.headline);Text("公開原始碼、限非商業使用。商業用途需另行取得授權；本授權不改變第三方元件的原有條款。");Link("閱讀授權全文",destination:URL(string:"https://polyformproject.org/licenses/noncommercial/1.0.0")!)}
    Section("第三方元件"){Text("SwiftSoup / idevice · MIT");Text("Appium / XCUITest Driver / WebDriverAgent · 各自 Apache 2.0 授權，執行於 Mac／測試裝置");NavigationLink("閱讀第三方聲明"){LocalLicenseView(resource:"THIRD_PARTY_NOTICES",title:"第三方聲明")};NavigationLink("閱讀 Rust 元件授權"){LocalLicenseView(resource:"Rust-THIRD_PARTY_NOTICES",title:"Rust 元件授權")};NavigationLink("閱讀 LineDraw 授權全文"){LocalLicenseView(resource:"LineDraw-LICENSE",title:"LineDraw 授權")}}
}.navigationTitle("授權").navigationBarTitleDisplayMode(.inline)}}

struct LocalLicenseView:View{let resource:String;let title:String
    var body:some View{ScrollView{Text(Bundle.main.url(forResource:resource,withExtension:"txt").flatMap{try? String(contentsOf:$0,encoding:.utf8)} ?? "請參閱原始碼中的授權文件。").font(.footnote.monospaced()).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding()}.navigationTitle(title).navigationBarTitleDisplayMode(.inline)}
}
