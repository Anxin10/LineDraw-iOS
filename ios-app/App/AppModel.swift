import SwiftUI
import Combine
import LineDrawCore

@MainActor final class AppModel:ObservableObject{
    @Published var data=DatabaseSnapshot();@Published var area:DrawArea = .website;@Published var filter=CatalogFilter();@Published var selected=Set<String>()
    @Published var busy=false;@Published var syncing=false;@Published var error:String?;@Published var notice:String?;@Published var pairing:PairingCredential?;@Published var companion:CompanionStatus?
    @Published var companionOnline=false;@Published var now=Date();@Published var fatalStorage=false;@Published var demoRunning=false;@Published var demoPaused=false;@Published var demoIndex=0;@Published var demoTotal=0
    private var db:LocalDatabase?;private let network=CatalogNetwork();private var client:CompanionClient?;private var polling=false;private var demoTask:Task<Void,Never>?;private var remoteEvents=Set<String>();private var syncTask:Task<[Draw],Error>?
    @Published var deviceMode=true
    @Published var deviceProgress=DeviceBatchProgress()
    @Published var deviceStage="尚未啟動"
    @Published var hasDevicePairing=false
    let phonePairing=PhonePairing()
    private var phonePairingUpdates:AnyCancellable?
    private var deviceRuntime:DeviceRuntime?
    private var deviceBatch:DeviceBatch?
    private var deviceTask:Task<Void,Never>?
    var isUITest=false
    init(){
        phonePairingUpdates=phonePairing.objectWillChange.sink{[weak self] in self?.objectWillChange.send()}
        phonePairing.onSaved={[weak self] in self?.hasDevicePairing=true}
        #if DEBUG
        isUITest=ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #endif
        do{
            let support=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent(isUITest ? "LineDraw-UITests":"LineDraw",isDirectory:true)
            var database=try LocalDatabase(file:support.appendingPathComponent("state.json"))
            if isUITest {
                try database.update{$0=DatabaseSnapshot();$0.consentVersion=ProcessInfo.processInfo.arguments.contains("--consent-test") ? 0:UsageDeclaration.version}
                try database.merge(TestCatalog.demo(),area:.demo)
                area = .demo
                if ProcessInfo.processInfo.arguments.contains("--dark"){try database.update{$0.settings.appearance="dark"}}
            }
            // A previous process may have died between dispatch and acknowledgement.
            try database.update{snapshot in
                for key in Array(snapshot.records.keys) where snapshot.records[key]!.status.hasSuffix("_INTENT") {
                    snapshot.records[key]!.status="REVIEW";snapshot.records[key]!.evidence="上次操作中斷，結果未確認；不會自動重送。"
                }
            }
            if !isUITest{try database.refreshBuiltInTests()}
            db=database;data=database.snapshot
            if !isUITest{deviceMode=UserDefaults.standard.string(forKey:"executionMode") != "mac";hasDevicePairing=(try? DeviceSecrets.load()) != nil}
            if !isUITest {pairing=try KeychainStore.read();if let pairing{client=try CompanionClient(pairing)}}
            #if DEBUG
            if !isUITest,ProcessInfo.processInfo.arguments.contains("--import-device-setup") {
                let incoming=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("device-pairing.mobiledevicepairing")
                try DeviceSecrets.save(Data(contentsOf:incoming));try FileManager.default.removeItem(at:incoming);hasDevicePairing=true
            }
            if !isUITest,ProcessInfo.processInfo.arguments.contains("--device-check"){Task{try? await Task.sleep(for:.seconds(2));self.checkDeviceConnection()}}
            if !isUITest,ProcessInfo.processInfo.arguments.contains("--device-speed"){Task{try? await Task.sleep(for:.seconds(2));self.runDeviceSpeedProbe()}}
            // Explicit developer launch only; uses normal persistence/repeat guards.
            // No automatic draw is started by a normal app launch or release build.
            if !isUITest,ProcessInfo.processInfo.arguments.contains("--device-test-batch"){Task{
                try? await Task.sleep(for:.seconds(2))
                guard self.accepted,!self.locked,self.deviceMode else{return}
                self.chooseArea(.test)
                guard Set(self.allDraws.filter{!$0.archived}.map(\.id))==Set(TestCatalog.five().map(\.id)) else{return}
                self.selectAll();await self.start()
            }}
            if !isUITest,ProcessInfo.processInfo.arguments.contains("--device-review"){Task{try? await Task.sleep(for:.seconds(2));self.runDeviceProbe(review:true)}}
            if !isUITest,ProcessInfo.processInfo.arguments.contains("--device-probe"){Task{try? await Task.sleep(for:.seconds(2));self.runDeviceProbe()}}
            if !isUITest,ProcessInfo.processInfo.arguments.contains("--import-device-ddi") {
                let staging=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("device-ddi",isDirectory:true)
                try DeviceSecrets.importDDI(DeviceSecrets.filenames.map{staging.appendingPathComponent($0)})
                try FileManager.default.removeItem(at:staging)
            }
            #endif
        }catch{fatalStorage=true;self.error="本機資料無法讀取；原檔已保留，請勿移除 App。"}
    }
    var accepted:Bool{data.consentVersion==UsageDeclaration.version && !fatalStorage}
    var profile:String{data.settings.profile}
    var records:[String:ParticipationRecord]{db?.records(profile:profile,area:area) ?? [:]}
    var catalogSource:CatalogSource{data.catalog}
    var catalogInfo:CatalogSync{data.syncInfo(for:catalogSource)}
    var allDraws:[Draw]{data.draws.filter{$0.area==area && (area != .website || catalogSource.owns($0))}.sorted{$0.ordinal<$1.ordinal}}
    var visible:[Draw]{allDraws.filter{filter.matches($0,recorded:records[$0.activityKey]?.blocksRepeat==true,now:now)}}
    var cities:[String]{Array(Set(allDraws.filter{!$0.archived}.map(\.city))).sorted()}
    var runnable:[Draw]{visible.filter{$0.runnable(at:now) && records[$0.activityKey]?.blocksRepeat != true}}
    var selectedDraws:[Draw]{runnable.filter{selected.contains($0.id)}}
    var locked:Bool{phonePairing.running || busy || demoRunning || deviceProgress.locked || companion?.engine.locked==true}
    var hasRemoteBatch:Bool{companion?.engine.locked==true}
    var readyCount:Int{allDraws.filter{$0.runnable(at:now) && records[$0.activityKey]?.blocksRepeat != true}.count}
    var recordList:[ParticipationRecord]{records.values.sorted{$0.updatedAt>$1.updatedAt}}
    var colorScheme:ColorScheme?{data.settings.appearance=="dark" ? .dark:data.settings.appearance=="light" ? .light:nil}
    func change(_ action:(inout DatabaseSnapshot)throws->Void){do{guard db != nil else{throw LineDrawError.message("本機資料不可用。")};try db!.update(action);data=db!.snapshot}catch{self.error=error.localizedDescription}}
    func accept(){change{$0.consentVersion=UsageDeclaration.version}}
    func decline(){change{$0.consentVersion=0};notice="尚未同意使用說明，功能保持關閉。"}
    func settings(_ action:(inout AppSettings)->Void){change{action(&$0.settings)}}
    func clearSelection(){selected=[]}
    func selectAll(){guard !locked else{return};selected=Set(runnable.map(\.id))}
    func toggle(_ draw:Draw){guard !locked,draw.runnable(at:now),records[draw.activityKey]?.blocksRepeat != true else{return};if selected.contains(draw.id){selected.remove(draw.id)}else{selected.insert(draw.id)}}
    func chooseArea(_ area:DrawArea){guard !locked else{return};self.area=area;filter=CatalogFilter();selected=[];companion=nil
        if area == .test && !data.draws.contains(where:{$0.area == .test}){do{try db!.merge(TestCatalog.five(),area:.test);data=db!.snapshot}catch{self.error=error.localizedDescription}}
        if area == .demo && !data.draws.contains(where:{$0.area == .demo}){do{try db!.merge(TestCatalog.demo(),area:.demo);data=db!.snapshot}catch{self.error=error.localizedDescription}}
    }
    func chooseProfile(_ value:String){guard !locked else{return};settings{$0.profile=value};selected=[];companion=nil}
    func addProfile(_ name:String){let name=name.trimmingCharacters(in:.whitespacesAndNewlines);guard !locked,!name.isEmpty,name.count<=40,!name.hasPrefix("__") else{return};settings{if !$0.profiles.contains(name){$0.profiles.append(name)};$0.profile=name};selected=[];companion=nil}
    func sync(source:CatalogSource?=nil)async{
        guard accepted,!locked else{return};busy=true;syncing=true;defer{busy=false;syncing=false;syncTask=nil}
        do{
            let selectedArea=area;let selectedSource=source ?? catalogSource
            let task=Task{switch selectedArea{case .website:return try await fetchCatalog(selectedSource);case .test:return TestCatalog.five();case .demo:return TestCatalog.demo()}}
            syncTask=task;let rows=try await task.value;try Task.checkCancellation();if task.isCancelled{throw CancellationError()}
            try db!.merge(rows,area:selectedArea,source:selectedSource,selectSource:true)
            if source != nil{filter=CatalogFilter();companion=nil}
            try? db!.log("SYNC","\(selectedArea == .website ? selectedSource.title:selectedArea.title)同步完成，\(rows.count) 筆。")
            data=db!.snapshot;selected=[];notice=area == .website ? catalogInfo.summary:"已載入\(area.title)"
        }catch{if syncTask?.isCancelled==true{notice="已取消同步，保留前次清單。";return};self.error=error.localizedDescription;try? db?.log("SYNC_FAILED","同步失敗，保留前次資料。");if let db{data=db.snapshot}}
    }
    private func fetchCatalog(_ source:CatalogSource)async throws->[Draw]{
        #if DEBUG
        if isUITest{
            if ProcessInfo.processInfo.arguments.contains("--catalog-failure"),source == .beybladeHunter{throw LineDrawError.message("測試來源同步失敗，保留前次清單。")}
            var rows=TestCatalog.demo();for i in rows.indices{rows[i].area = .website;rows[i].id=(source == .funbox ? "fixture:":CatalogSource.hunterPrefix)+String(i)}
            return rows
        }
        #endif
        return try await network.fetch(source:source)
    }
    func cancelSync(){syncTask?.cancel()}
    func mark(_ draw:Draw){guard accepted,!locked else{return};guard draw.canonicalURL != nil else{error="連結尚未解析，請先同步後再標記完成。";return};do{try db!.manual(draw,profile:profile);data=db!.snapshot;selected.remove(draw.id)}catch{self.error=error.localizedDescription}}
    func undo(_ record:ParticipationRecord){guard accepted,!locked else{return};do{try db!.undo(activityKey:record.id,profile:profile,area:area);data=db!.snapshot}catch{self.error=error.localizedDescription}}
    func open(_ draw:Draw)async{
        guard accepted,!locked,area != .demo else{return};busy=true;defer{busy=false}
        do{let raw=try await network.resolve(draw.url);guard let url=URL(string:raw) else{return};let opened=await UIApplication.shared.open(url);if !opened{error="無法開啟 LINE，請確認已安裝並登入 LINE。"}else{notice="已開啟活動；尚未標記完成。"}}catch{self.error=error.localizedDescription}
    }
    func pair(_ raw:String)async{
        guard accepted,!locked else{return};busy=true;defer{busy=false}
        do{let invitation=try PairingInvitation(raw:raw);let credential=try await CompanionClient.pair(invitation);try KeychainStore.save(WireJSON.encoder().encode(credential));pairing=credential;client=try CompanionClient(credential);notice="已配對 Mac";await poll()}catch{self.error=error.localizedDescription}
    }
    func unpair()async{
        guard !locked else{return}
        if let client{do{try await client.unpair()}catch{self.error="Mac 無法連線，本機配對已移除；請在 Mac 控制台撤銷舊配對。"}}
        KeychainStore.clear();pairing=nil;client=nil;companion=nil;companionOnline=false
    }
    func flushOutbox()async throws{
        guard let client,!data.bridgeOutbox.isEmpty else{return};let pending=data.bridgeOutbox;try await client.mutate(pending)
        let ids=Set(pending.map(\.id));try db!.update{$0.bridgeOutbox.removeAll{ids.contains($0.id)}};data=db!.snapshot
    }
    func poll()async{
        guard accepted,!deviceMode,let client,!polling,area != .demo else{return};polling=true;defer{polling=false}
        let requestedProfile=profile;let requestedArea=area
        do{
            var status=try await client.status(profile:requestedProfile,area:requestedArea)
            guard profile==requestedProfile,area==requestedArea else{return}
            if !status.engine.locked && !data.bridgeOutbox.isEmpty{try await flushOutbox();status=try await client.status(profile:requestedProfile,area:requestedArea)}
            guard profile==requestedProfile,area==requestedArea else{return}
            companionOnline=true;companion=status
            for event in status.diagnostics{let key=WireJSON.date(event.at)+event.code+String(event.index ?? -1);if remoteEvents.insert(key).inserted{try db!.log("MAC_"+event.code,"佇列位置 \(event.index.map{String($0+1)} ?? "—")",now:event.at)}}
            try db!.importRecords(status.records.map(\.local),profile:status.profile,area:DrawArea(rawValue:status.area) ?? area);data=db!.snapshot
        }catch{companionOnline=false}
    }
    func start()async{
        guard accepted,!locked,!selectedDraws.isEmpty else{return}
        if area == .demo{startDemo();return}
        if deviceMode{startDeviceBatch();return}
        guard let client else{error="請先在設定配對 Mac，再開始抽選。";return}
        busy=true;defer{busy=false}
        do{
            try await flushOutbox()
            if area == .website,catalogSource != .funbox{
                let status=try await client.status(profile:profile,area:area)
                guard status.catalogSources?.contains(catalogSource.rawValue)==true else{throw LineDrawError.message("請先更新 Mac 輔助程式，才能使用陀螺獵人來源。")}
            }
            let request=CompanionStart(profile:profile,area:area,rows:allDraws.filter{!$0.archived},selectedIDs:selectedDraws.map(\.id),records:Array(records.values),filter:filter,autoFriend:data.settings.autoFriend,autoContinue:area == .website && data.settings.autoContinue,catalogSource:catalogSource)
            // One request only. A transport timeout is reconciled through status, never automatically resent.
            companion=try await client.start(request);companionOnline=true;selected=[]
            try db!.log("BATCH_STARTED","使用者開始批次，\(request.selectedIDs.count) 筆。");data=db!.snapshot
        }catch{self.error="開始請求未確認：\(error.localizedDescription) 請重新整理進度，避免重複開始。";await poll()}
    }
    func control(_ action:String)async{
        if area == .demo{if action=="pause"{demoPaused=true};if action=="resume"{demoPaused=false};if action=="stop"{demoTask?.cancel();demoRunning=false;demoPaused=false};return}
        if deviceMode {
            if action=="pause"{deviceBatch?.pause()}
            if action=="resume"{deviceBatch?.resume()}
            if action=="skip"{deviceBatch?.skipCurrent()}
            if action=="stop"{deviceRuntime?.noteUserCancellation();deviceBatch?.stop();deviceTask?.cancel()}
            return
        }
        guard let client else{return}
        do{companion=try await client.control(action,profile:profile,area:area);companionOnline=true;await poll()}catch{self.error=error.localizedDescription}
    }
    func startDemo(){let rows=selectedDraws;let profile=profile;demoRunning=true;demoPaused=false;demoIndex=0;demoTotal=rows.count;selected=[]
        demoTask=Task{for row in rows{while demoPaused && !Task.isCancelled{try? await Task.sleep(for:.milliseconds(300))};guard !Task.isCancelled else{break};try? await Task.sleep(for:.milliseconds(1100));guard !Task.isCancelled else{break}
            do{try db!.importRecords([ParticipationRecord(id:row.activityKey,product:row.product,store:row.store,status:"SUBMITTED",evidence:"離線示範，沒有開啟 LINE 或送出真實抽選。")],profile:profile,area:.demo);data=db!.snapshot;demoIndex+=1}catch{self.error=error.localizedDescription;break}
        };demoRunning=false;demoPaused=false;notice=Task.isCancelled ? "示範已停止，沒有操作 LINE。":"示範完成，沒有操作 LINE。"}
    }
    func importTests(_ raw:Data){guard accepted,!locked else{return};do{
        struct Row:Decodable{var title:String;var url:String;var startsAt:Date;var endsAt:Date}
        let input=try WireJSON.decoder().decode([Row].self,from:raw);guard (1...500).contains(input.count) else{throw LineDrawError.message("請匯入 1～500 筆測試資料。")}
        let rows=try input.enumerated().map{i,r->Draw in guard let url=LinkPolicy.canonical(r.url),r.endsAt>r.startsAt,!r.title.isEmpty else{throw LineDrawError.message("需提供完整 LIFF 連結與有效起訖時間。")};return Draw(id:"test:"+LinkPolicy.key(url),activityKey:LinkPolicy.key(url),store:"自訂測試",city:"實機測試",product:r.title,url:url,canonicalURL:url,timeLabel:"自訂測試期間",startsAt:r.startsAt,endsAt:r.endsAt,ordinal:i,area:.test)}
        guard Set(rows.map(\.activityKey)).count==rows.count else{throw LineDrawError.message("測試活動重複。")};try db!.merge(rows,area:.test);data=db!.snapshot;chooseArea(.test);notice="已匯入 \(rows.count) 筆測試，既有紀錄保留。"
    }catch{self.error=error.localizedDescription}}
    func chooseMode(_ local:Bool){guard !locked else{return};deviceMode=local;companion=nil;UserDefaults.standard.set(local ? "device":"mac",forKey:"executionMode")}
    func startPhonePairing(){guard accepted,!locked else{return};phonePairing.start(simulated:isUITest)}
    func importDevicePairing(_ bytes:Data){guard !locked else{return};do{try DeviceSecrets.save(bytes);hasDevicePairing=true;notice="配對檔已安全儲存在這支手機。"}catch{self.error=error.localizedDescription}}
    func clearDevicePairing(){guard !locked else{return};DeviceSecrets.clear();hasDevicePairing=false}
    func cancelDeviceSetup(){deviceRuntime?.noteUserCancellation();deviceBatch?.stop();deviceTask?.cancel()}
    func prepareDeviceFiles(){
        guard accepted,!locked else{return};busy=true
        deviceTask=Task{
            do{try await DDIManager.prepare{self.deviceStage=$0};notice=deviceStage}
            catch{deviceStage=error is CancellationError ? "已取消準備；原有檔案保留。":error.localizedDescription;if !(error is CancellationError){self.error=deviceStage}}
            busy=false;deviceTask=nil
        }
    }
    func checkDeviceConnection(){
        guard accepted,!locked else{return};busy=true;deviceStage="準備檢查…"
        deviceTask=Task{
            let runtime=deviceRuntime ?? DeviceRuntime();deviceRuntime=runtime
            runtime.onExpired={[weak self] in self?.deviceTask?.cancel()}
            do{
                _=try await runtime.start{[weak self] in self?.deviceStage=$0}
                try Task.checkCancellation();await runtime.stop(success:true)
                deviceStage="WDA 啟動成功，已結束檢查；沒有執行抽選。";notice=deviceStage
            }catch{await runtime.stop(success:false);deviceStage=error is CancellationError ? runtime.cancellationMessage:error.localizedDescription;if !(error is CancellationError){self.error=deviceStage}}
            #if DEBUG
            let report:[String:Any]=["at":ISO8601DateFormatter().string(from:Date()),"passed":deviceStage.hasPrefix("WDA 啟動成功"),"stage":deviceStage,"runtimeCode":runtime.lastCode,"build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown"]
            let reportURL=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("device-check-report.json")
            if let bytes=try? JSONSerialization.data(withJSONObject:report,options:.sortedKeys){try? bytes.write(to:reportURL,options:[.atomic,.completeFileProtection])}
            #endif
            busy=false;deviceTask=nil
        }
    }
    func startDeviceBatch(){
        let rows=selectedDraws;let original=allDraws;let frozenProfile=profile;let frozenArea=area;let frozenSource=catalogSource;let frozenFilter=filter;let autoFriend=data.settings.autoFriend;let autoContinue=frozenArea == .website && data.settings.autoContinue
        guard !rows.isEmpty else{return};busy=true;deviceStage="準備啟動…";selected=[]
        deviceTask=Task{[self] in
            let runtime=deviceRuntime ?? DeviceRuntime();deviceRuntime=runtime
            runtime.onExpired={[weak self] in self?.deviceBatch?.stop();self?.deviceTask?.cancel();self?.deviceStage="iOS 已結束背景工作。"}
            #if DEBUG
            let reportBegan=ProcessInfo.processInfo.systemUptime
            @MainActor func saveBatchReport(){
                guard ProcessInfo.processInfo.arguments.contains("--device-test-batch"),frozenArea == .test else{return}
                let records=db?.records(profile:frozenProfile,area:frozenArea) ?? [:]
                let body:[String:Any]=["build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown","time":WireJSON.date(Date()),"state":deviceProgress.state,"reason":deviceProgress.reason,"completed":deviceProgress.index,"total":deviceProgress.total,"elapsed":ProcessInfo.processInfo.systemUptime-reportBegan,"statuses":rows.map{records[$0.activityKey]?.status ?? "PENDING"},"wdaTimings":runtime.driver?.timings ?? [:],"lookupMode":runtime.driver?.lookupMode ?? "stopped","phaseTimings":runtime.driver?.phaseTimings ?? [:],"navigationCounts":runtime.driver?.navigationCounts ?? [:],"items":self.deviceBatch?.itemTimings.map{["index":$0.index,"total":$0.total,"open":$0.open,"read":$0.read,"reads":$0.reads,"tap":$0.tap,"save":$0.save,"status":$0.status] as [String:Any]} ?? []]
                let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("device-test-batch.json")
                if let bytes=try? JSONSerialization.data(withJSONObject:body,options:.prettyPrinted){try? bytes.write(to:url,options:.atomic)}
            }
            #endif
            do{
                let driver=try await runtime.start{[weak self] stage in self?.deviceStage=stage}
                driver.onRequestFailure={[weak self] message in try? self?.db?.log("WDA_REQUEST_FAILED",message)}
                try Task.checkCancellation()
                let batch=DeviceBatch(driver:driver,read:{[weak self] key in self?.db?.records(profile:frozenProfile,area:frozenArea)[key]},write:{[weak self] row,record in
                    guard let self else{throw CancellationError()};guard self.db != nil else{throw LineDrawError.message("本機資料不可用。")}
                    try self.db!.update{$0.records[LocalDatabase.scope(profile:frozenProfile,area:frozenArea)+"\n"+row.activityKey]=record};self.data=self.db!.snapshot
                },update:{[weak self] progress in
                    self?.deviceProgress=progress;runtime.report(progress)
                    #if DEBUG
                    saveBatchReport()
                    #endif
                },fetch:{[weak self] in
                    guard let self else{throw CancellationError()};let incoming=try await self.fetchCatalog(frozenSource);try Task.checkCancellation();try self.db!.merge(incoming,area:.website,source:frozenSource);self.data=self.db!.snapshot;return incoming
                })
                deviceBatch=batch;driver.canAct={[weak self] in self?.deviceProgress.state=="RUNNING" && !Task.isCancelled}
                busy=false;deviceStage="手機自主執行中"
                let queueBegan=ProcessInfo.processInfo.systemUptime
                await batch.run(rows,allInitial:original,filter:frozenFilter,autoFriend:autoFriend,autoContinue:autoContinue)
                let duration=ProcessInfo.processInfo.systemUptime-queueBegan
                let source=driver.timings["GET source"] ?? [:]
                try? db?.log("DEVICE_TIMING","佇列 \(String(format:"%.2f",duration)) 秒；讀取畫面 \(Int(source["count"] ?? 0)) 次／\(String(format:"%.2f",source["seconds"] ?? 0)) 秒。")
                for item in batch.itemTimings {
                    try? db?.log("DEVICE_ITEM_TIMING","第 \(item.index) 筆 \(item.status)：總計 \(String(format:"%.2f",item.total)) 秒；開網址 \(String(format:"%.2f",item.open))；讀取 \(item.reads) 次／\(String(format:"%.2f",item.read))；點擊 \(String(format:"%.2f",item.tap))；保存 \(String(format:"%.2f",item.save))。")
                }
                let phases=driver.phaseTimings.keys.sorted().map{key in let value=driver.phaseTimings[key]!;return "\(key)=\(Int(value["count"] ?? 0))/\(String(format:"%.2f",value["seconds"] ?? 0))s"}.joined(separator:"；")
                try? db?.log("DEVICE_PHASE_TIMING",phases)
                try? db?.log("DEVICE_LOOKUP",driver.lookupMode+"；直接開頁 \(driver.navigationCounts["directOpen",default:0])；畫面就緒 \(driver.navigationCounts["ready:settled",default:0]+driver.navigationCounts["ready:document",default:0])")
                busy=true;deviceStage=deviceProgress.reason
                try db!.log("DEVICE_BATCH_FINISHED","手機端批次結束；完成位置 \(deviceProgress.index) / \(deviceProgress.total)。\(deviceProgress.reason)");data=db!.snapshot
                await runtime.stop(success:deviceProgress.state=="COMPLETED")
            }catch{
                await runtime.stop(success:false);deviceStage=error is CancellationError ? runtime.cancellationMessage:error.localizedDescription
                if !(error is CancellationError){self.error=deviceStage}
            }
            busy=false;deviceBatch=nil;deviceTask=nil
        }
    }
    #if DEBUG
    /// Uses the production queue engine but an isolated Safari fixture/database.
    func runDeviceSpeedProbe(){
        guard accepted,!locked else{return};busy=true
        deviceTask=Task{
            let runtime=deviceRuntime ?? DeviceRuntime();deviceRuntime=runtime
            runtime.onExpired={[weak self] in self?.deviceTask?.cancel()}
            let fixture=DeviceProbeServer();defer{fixture.stop()}
            let document=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
            let report=document.appendingPathComponent("device-speed.json")
            let began=Date();var queueSeconds:Double=0;var startupSeconds:Double=0;var phase="preparingFixture"
            var stages=[String]();var records=[String:ParticipationRecord]();var measuredBatch:DeviceBatch?
            let args=ProcessInfo.processInfo.arguments
            let faultMode=args.contains("--fixture-timeout-once") ? "timeoutOnce":args.contains("--fixture-cancel-read") ? "cancelRead":"none"
            var faultInjected=false
            @MainActor func save(_ status:String,_ details:String=""){
                let attempts=runtime.driver?.requestAttempts.map{a->[String:Any] in
                    var value:[String:Any]=["operation":a.operation,"attempt":a.attempt,"seconds":a.seconds,"timedOut":a.timedOut]
                    if let code=a.errorCode{value["errorCode"]=code};return value
                } ?? []
                let body:[String:Any]=["schema":3,"build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown","phase":phase,"runtimeCode":runtime.lastCode,"cancellationSource":status=="cancelled" ? runtime.cancellationSource:"none","faultMode":faultMode,"faultInjected":faultInjected,"inFlightOperation":runtime.driver?.inFlightOperation ?? "none","coldSafari":args.contains("--cold-fixture"),"requestAttempts":attempts,"fixtureRequests":fixture.requests,"status":status,"details":details,"elapsed":Date().timeIntervalSince(began),"startupSeconds":startupSeconds,"queueSeconds":queueSeconds,"completed":records.values.filter{$0.status=="SUBMITTED"}.count,"statuses":records.values.map(\.status),"acknowledged":fixture.acknowledged.sorted(),"acknowledgementCounts":fixture.acknowledgementCounts,"stages":stages,"wdaTimings":runtime.driver?.timings ?? [:],"lookupMode":runtime.driver?.lookupMode ?? "stopped","phaseTimings":runtime.driver?.phaseTimings ?? [:],"navigationCounts":runtime.driver?.navigationCounts ?? [:],"items":measuredBatch?.itemTimings.map{["index":$0.index,"total":$0.total,"open":$0.open,"read":$0.read,"reads":$0.reads,"tap":$0.tap,"save":$0.save,"status":$0.status] as [String:Any]} ?? [],"time":WireJSON.date(Date())]
                if let bytes=try? JSONSerialization.data(withJSONObject:body,options:.prettyPrinted){try? bytes.write(to:report,options:.atomic)}
            }
            save("running")
            do{
                // Use the normal cached/bundled/download-on-demand path in runtime.start.
                // Speed measurement must not force an unrelated 17 MB download on every run.
                deviceStage="準備本機速度測試頁…"
                let fixtureURL=try await fixture.start()
                phase="startingRunner";save("running")
                let driver=try await runtime.start{if stages.last != $0{stages.append($0);save("running")};self.deviceStage=$0}
                driver.expectedBundle="com.apple.mobilesafari";driver.fixtureBaseURL=fixtureURL
                driver.onDiagnosticChange={save("running")}
                if faultMode != "none" {
                    // Debug-only, Safari loopback fixture, after first navigation.
                    // Inject a timeout or invoke the same stop handler as the App UI.
                    driver.fixtureReadFault={
                        faultInjected=true;save("running")
                        if faultMode=="cancelRead"{self.cancelDeviceSetup();try Task.checkCancellation()}
                        try await Task.sleep(for:.seconds(18))
                        throw URLError(.timedOut)
                    }
                }
                if ProcessInfo.processInfo.arguments.contains("--cold-fixture"){phase="restartSafari";try await driver.prepareColdFixture()}
                let rows=(0..<5).map{i->Draw in var row=TestCatalog.five()[i];row.startsAt=Date().addingTimeInterval(-60);row.endsAt=Date().addingTimeInterval(3600);row.canonicalURL="https://liff.line.me/linedraw-fixture/c/speed\(i)";return row}
                let batch=DeviceBatch(driver:driver,expectedBundle:driver.expectedBundle,read:{records[$0]},write:{records[$0.activityKey]=$1},update:{runtime.report($0);if phase != $0.reason{phase=$0.reason;save("running")};self.deviceStage="速度驗證："+$0.reason})
                measuredBatch=batch
                driver.canAct={batch.progress.state=="RUNNING" && !Task.isCancelled}
                startupSeconds=Date().timeIntervalSince(began);let started=Date();phase="runningQueue";save("running")
                await batch.run(rows,allInitial:rows,filter:CatalogFilter(),autoFriend:true,autoContinue:false)
                queueSeconds=Date().timeIntervalSince(started)
                try Task.checkCancellation()
                // Observe fixture acknowledgements only after the batch; the production engine never waits for results.
                for _ in 0..<20 where fixture.acknowledged.count<5{try await Task.sleep(for:.milliseconds(100))}
                guard batch.progress.state=="COMPLETED",records.count==5,records.values.allSatisfy({$0.status=="SUBMITTED"}),fixture.acknowledged==Set((0..<5).map{"speed\($0)"}),fixture.acknowledgementCounts.values.allSatisfy({$0==1}) else{throw LineDrawError.message("速度驗證未全部完成：\(batch.progress.reason)")}
                driver.onDiagnosticChange=nil;driver.fixtureReadFault=nil
                phase="complete";save("passed");await runtime.stop(success:true);deviceStage="速度驗證通過：5 筆本機操作 \(String(format:"%.2f",queueSeconds)) 秒。"
            }catch{
                runtime.driver?.onDiagnosticChange=nil;runtime.driver?.fixtureReadFault=nil
                let message=error is CancellationError ? runtime.cancellationMessage:error.localizedDescription
                save(error is CancellationError ? "cancelled":"failed",message);await runtime.stop(success:false)
                deviceStage=message;if !(error is CancellationError){self.error=deviceStage}
            }
            busy=false;deviceTask=nil
        }
    }
    // Developer-only smoke test. Uses an isolated fixture, never LINE or real coupon URLs.
    func runDeviceProbe(review:Bool=false){
        guard accepted,!locked else{return};busy=true
        deviceTask=Task{
            let runtime=deviceRuntime ?? DeviceRuntime();deviceRuntime=runtime
            runtime.onExpired={[weak self] in self?.deviceTask?.cancel()}
            let report=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent(review ? "device-review.json":"device-probe.json")
            let inspectNavigation=review && ProcessInfo.processInfo.arguments.contains("--inspect-navigation")
            var reviewObservations=[[String:Any]]()
            var step="starting";var completed=0;var findings=[String]();let began=Date();var finalTimings=[String:[String:Double]]();var finalPhaseTimings=[String:[String:Double]]();var finalLookupMode="unknown";var finalNavigationCounts=[String:Int]()
            let fixture=DeviceProbeServer()
            @MainActor func save(_ status:String){let body:[String:Any]=["status":status,"step":step,"observations":reviewObservations,"completed":completed,"fixtureRequests":fixture.requests,"findings":findings,"elapsed":Date().timeIntervalSince(began),"time":WireJSON.date(Date()),"wdaTimings":runtime.driver?.timings ?? finalTimings,"lookupMode":runtime.driver?.lookupMode ?? finalLookupMode,"phaseTimings":runtime.driver?.phaseTimings ?? finalPhaseTimings,"navigationCounts":runtime.driver?.navigationCounts ?? finalNavigationCounts];if let bytes=try? JSONSerialization.data(withJSONObject:body,options:.prettyPrinted){try? bytes.write(to:report,options:.atomic)}}
            save("running")
            defer{fixture.stop()}
            do{
                var urls=[String]();var fixtureURL:String?
                if review {
                    let file=report.deletingLastPathComponent().appendingPathComponent("device-review-input.json")
                    urls=try JSONDecoder().decode([String].self,from:Data(contentsOf:file))
                    guard !urls.isEmpty,urls.count<=15,urls.allSatisfy({LinkPolicy.canonical($0)==$0}) else{throw LineDrawError.message("唯讀複查清單格式不正確。")}
                } else {
                    fixtureURL=try await fixture.start()
                    var check=URLRequest(url:URL(string:fixtureURL!+"self-check")!);check.timeoutInterval=5
                    let (checkData,checkResponse)=try await URLSession.shared.data(for:check)
                    guard (checkResponse as? HTTPURLResponse)?.statusCode==200,String(data:checkData,encoding:.utf8)?.contains("抽選")==true else{throw LineDrawError.message("Fixture 本機 HTTP 檢查失敗。")}
                    urls=(0..<20).map{"https://liff.line.me/linedraw-fixture/c/probe\($0)"}
                }
                let driver=try await runtime.start{stage in self.deviceStage=stage;step=stage;save("running")}
                if let fixtureURL{driver.expectedBundle="com.apple.mobilesafari";driver.fixtureBaseURL=fixtureURL}
                // Review never submits. Navigation inspection may observe a ready button but does not tap it.
                for (i,url) in urls.enumerated(){
                    try Task.checkCancellation();step="open-\(i)";save("running")
                    let baseline=try await driver.open(url)
                    var itemProgress=DeviceBatchProgress();itemProgress.total=urls.count;itemProgress.index=i;itemProgress.itemStep=1;runtime.report(itemProgress)
                    if !review && i==0{try await Task.sleep(for:.seconds(1));await driver.saveFixtureEvidence("opened")}
                    if review {
                        let deadline=Date().addingTimeInterval(30);var result:String?;var previous=""
                        while Date()<deadline {
                            try Task.checkCancellation();try await Task.sleep(for:.milliseconds(200))
                            let screen=try await driver.snapshot()
                            if screen.navigationVerified,itemProgress.itemStep<2{itemProgress.itemStep=2;runtime.report(itemProgress)}
                            let decision=DeviceScreenRules.classify(screen)
                            if inspectNavigation {
                                reviewObservations.append(["index":i,"elapsed":Date().timeIntervalSince(began),"decision":String(describing:decision),"bundle":screen.bundle,"pending":screen.navigationPending,"ready":screen.navigationVerified,"targeted":screen.targeted,"width":screen.width,"height":screen.height,"alerts":screen.nodes.filter{$0.type=="XCUIElementTypeAlert"}.map{["labels":$0.labels,"x":$0.rect.x,"y":$0.rect.y,"width":$0.rect.width,"height":$0.rect.height] as [String:Any]},"documentMatches":screen.nodes.filter{$0.type=="XCUIElementTypeWebView"}.flatMap(\.labels).compactMap{LinkPolicy.canonical($0)}.map{$0==url}])
                                if reviewObservations.count>40{reviewObservations.removeFirst(reviewObservations.count-40)}
                                save("running")
                            }
                            let key=DeviceScreenRules.stabilityKey(screen,decision:decision)
                            if !screen.navigationPending,(screen.navigationVerified || screen.navigationFingerprint != baseline),key==previous {
                                if case .terminal(let value)=decision{result=value;break}
                                if inspectNavigation,case .click=decision{result="READY_NOT_TAPPED";break}
                            }
                            previous=screen.navigationPending || (!screen.navigationVerified && screen.navigationFingerprint==baseline) ? "":key
                        }
                        guard let result else{throw LineDrawError.message("唯讀複查第 \(i+1) 筆未辨識到預期畫面；沒有點擊抽選。")} 
                        completed+=1;findings.append(result);step="review-confirmed";save("running")
                        var progress=DeviceBatchProgress();progress.total=urls.count;progress.index=completed;progress.reason="唯讀換頁檢查 \(completed) / \(urls.count)";runtime.report(progress)
                        continue
                    }
                    var candidate:ScreenNode?;var observation="";let deadline=Date().addingTimeInterval(30)
                    while Date()<deadline {
                        try Task.checkCancellation();try await Task.sleep(for:.milliseconds(500))
                        let screen=try await driver.snapshot()
                        let decision=DeviceScreenRules.classify(screen,expectedBundle:driver.expectedBundle)
                        observation="\(screen.bundle) / \(decision)"
                        if !screen.navigationPending,case .click(_,let node)=decision{candidate=node;break}
                    }
                    guard let node=candidate else{await driver.saveFixtureEvidence("missing-button");throw LineDrawError.message("Fixture 載入後找不到抽選按鈕：\(observation)")}
                    try await driver.tap(node)
                    let after=try await driver.snapshot()
                    guard case .terminal=DeviceScreenRules.classify(after,expectedBundle:driver.expectedBundle) else{throw LineDrawError.message("Fixture 點擊沒有可觀測結果。")}
                    completed+=1;step="fixture-confirmed";save("running")
                    var progress=DeviceBatchProgress();progress.total=20;progress.index=completed;progress.reason="離線畫面驗證 \(completed) / 20";runtime.report(progress)
                    try await Task.sleep(for:.seconds(3))
                }
                finalTimings=runtime.driver?.timings ?? [:];finalPhaseTimings=runtime.driver?.phaseTimings ?? [:];finalLookupMode=runtime.driver?.lookupMode ?? "unknown";finalNavigationCounts=runtime.driver?.navigationCounts ?? [:];step="cleanup"
                await runtime.stop(success:true,beforeCompletion:{step="finished";save("passed")})
                deviceStage=review ? "手機端唯讀頁面複查通過，\(completed) 筆；沒有抽選操作。":"手機端離線畫面驗證通過，20 次操作。"
            }catch{step=error.localizedDescription;save("failed");await runtime.stop(success:false);deviceStage=step;self.error=step}
            busy=false;deviceTask=nil
        }
    }
    #endif
    var batchTotal:Int{area == .demo ? demoTotal:deviceMode ? deviceProgress.total:companion?.engine.total ?? 0}
    var batchIndex:Int{area == .demo ? demoIndex:deviceMode ? deviceProgress.index:companion?.engine.index ?? 0}
    var batchState:String{area == .demo ? (demoPaused ? "PAUSED":demoRunning ? "RUNNING":"COMPLETED"):deviceMode ? deviceProgress.state:companion?.engine.state ?? "IDLE"}
    var batchReason:String{area == .demo ? "離線示範，不操作 LINE。":deviceMode ? deviceProgress.reason:companion?.engine.reason ?? "尚未開始"}
    var batchBusy:Bool{area == .demo ? false:deviceMode ? deviceProgress.busy:companion?.engine.busy ?? false}
    var batchActive:Bool{area == .demo ? demoRunning:deviceMode ? deviceProgress.locked:companion?.engine.locked ?? false}
    var startInstructions:String{deviceMode ? "請保持手機解鎖與 LocalDevVPN 連線。可從 iOS 工作進度取消，或回到 App 停止。":"請保持 Mac 開啟及手機解鎖；可在 Mac 控制台隨時停止。"}
    func clearDiagnostics(){change{$0.diagnostics=[]}}
    var diagnosticsText:String{db?.diagnosticsText() ?? "尚無紀錄。"}
}
