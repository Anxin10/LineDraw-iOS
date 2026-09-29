import SwiftUI
import LineDrawCore
struct CatalogView:View{
    @EnvironmentObject var model:AppModel
    @State private var showFilters=false;@State private var showStart=false;@State private var detail:Draw?
    var grouped:[String]{var values:[String]=[];for row in model.visible where !values.contains(row.store){values.append(row.store)};return values}
    var body:some View{
        NavigationStack{
            List{
                Section{
                    VStack(alignment:.leading,spacing:14){
                        AdaptiveStack{Label(model.area.title,systemImage:model.area == .website ? "globe.asia.australia":"testtube.2").font(.subheadline.weight(.medium)).foregroundStyle(.secondary);Spacer();if model.area == .demo{StatusBadge(text:"不操作 LINE",color:.purple)}}
                        HStack(alignment:.firstTextBaseline,spacing:6){Text("\(model.readyCount)").font(.system(size:48,weight:.bold,design:.rounded)).monospacedDigit();Text("筆可抽選").font(.title3).foregroundStyle(.secondary);Spacer();Image(systemName:"ticket.fill").font(.system(size:34)).foregroundStyle(.blue.gradient).rotationEffect(.degrees(-15)).accessibilityHidden(true)}
                        AdaptiveStack{Text(model.area == .website ? model.data.syncSummary:"清單與網站紀錄分開保存").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true);Spacer();if model.busy{ProgressView();if model.syncing{Button("取消"){model.cancelSync()}}}else{Button{Task{await model.sync()}}label:{Label("同步",systemImage:"arrow.triangle.2.circlepath")}.font(.subheadline.weight(.semibold)).disabled(model.locked).accessibilityIdentifier("syncCatalog")}}
                        if let date=model.data.lastSync,model.area == .website{Text("更新於 \(dateText(date)) · 台北時間").font(.caption2).foregroundStyle(.tertiary)}
                    }.padding(.vertical,8)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top:0,leading:4,bottom:10,trailing:4))
                if model.batchTotal > 0 {Section{BatchProgressView()}.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top:0,leading:0,bottom:4,trailing:0))}
                if let notice=model.notice{Section{HStack(alignment:.top){Image(systemName:"checkmark.circle").foregroundStyle(.green);Text(notice).font(.subheadline);Spacer();Button{model.notice=nil}label:{Image(systemName:"xmark")}.buttonStyle(.plain).accessibilityLabel("關閉提示")}}}
                Section{
                    AdaptiveStack{
                        Button{showFilters=true}label:{Label(model.filter.cities.isEmpty && model.filter.statuses.isEmpty ? "篩選":"篩選 · \(model.filter.cities.count+model.filter.statuses.count)",systemImage:"line.3.horizontal.decrease")}.buttonStyle(.glass).accessibilityIdentifier("openFilters").disabled(model.locked)
                        Spacer();Text("\(model.visible.count) 筆").font(.subheadline).foregroundStyle(.secondary)
                        Button(model.selectedDraws.count==model.runnable.count && !model.runnable.isEmpty ? "取消全選":"全選"){if model.selectedDraws.count==model.runnable.count{model.clearSelection()}else{model.selectAll()}}.disabled(model.locked || model.runnable.isEmpty).accessibilityIdentifier("selectAll")
                    }.listRowBackground(Color.clear)
                }.listRowInsets(EdgeInsets(top:0,leading:0,bottom:0,trailing:0))
                if model.visible.isEmpty {
                    Section{ContentUnavailableView(model.allDraws.isEmpty ? "還沒有抽選資料":"沒有符合條件的活動",systemImage:"ticket",description:Text(model.allDraws.isEmpty ? "下拉同步，取得最新活動。":"調整地區、狀態或搜尋條件。"))}.listRowBackground(Color.clear)
                }
                ForEach(grouped,id:\.self){store in
                    Section{ForEach(model.visible.filter{$0.store==store}){draw in
                        DrawRow(draw:draw,onDetail:{detail=draw})
                    }}header:{Text(store).textCase(nil).font(.subheadline.weight(.semibold))}
                }
                if !model.visible.isEmpty{Section{Text(model.area == .demo ? "這是離線示範，所有操作只改變示範紀錄。":"送出抽選後直接接續下一筆；「已送出」不代表中獎或未中獎。").font(.footnote).foregroundStyle(.secondary)}.listRowBackground(Color.clear)}
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).background{AppBackdrop()}
            .navigationTitle("抽選").searchable(text:$model.filter.query,prompt:"搜尋店家、商品或地區").disabled(model.fatalStorage)
            .onChange(of:model.filter){_,_ in model.clearSelection()}
            .refreshable{await model.sync()}
            .toolbar{ToolbarItem(placement:.topBarTrailing){Menu{ForEach(DrawArea.allCases,id:\.self){area in Button{model.chooseArea(area)}label:{Label(area.title,systemImage:area==model.area ? "checkmark":"circle")}.disabled(model.locked)}}label:{Image(systemName:"rectangle.stack")}.accessibilityLabel("切換清單")}}
            .safeAreaInset(edge:.bottom){if !model.selectedDraws.isEmpty && !model.locked{AdaptiveStack{VStack(alignment:.leading,spacing:3){Text("已選 \(model.selectedDraws.count) 筆").font(.headline);Text(model.area == .demo ? "離線示範":"按清單順序執行").font(.caption).foregroundStyle(.secondary)};Spacer();Button{showStart=true}label:{Label(model.area == .demo ? "開始示範":"開始抽選",systemImage:"play.fill")}.buttonStyle(.glassProminent).controlSize(.large).accessibilityIdentifier("startBatch")}.padding(14).glassPanel().padding(.horizontal,16).padding(.bottom,8)}}
            .sheet(isPresented:$showFilters){FilterSheet()}
            .sheet(item:$detail){draw in DrawDetail(draw:draw)}
            .confirmationDialog("開始處理 \(model.selectedDraws.count) 筆活動？",isPresented:$showStart,titleVisibility:.visible){Button(model.area == .demo ? "開始離線示範":"開始本次抽選"){Task{await model.start()}}.accessibilityIdentifier("confirmStart");Button("取消",role:.cancel){}}message:{Text(model.area == .demo ? "不會開啟 LINE，也不會送出真實抽選。":"請確認手機目前的 LINE 帳號正確。\(model.data.settings.autoFriend ? "必要時會加入店家好友。":"需要加好友時會暫停。")\(model.startInstructions)")}
        }
    }
}
struct DrawRow:View{
    @EnvironmentObject var model:AppModel
    let draw:Draw;let onDetail:()->Void
    var record:ParticipationRecord?{model.records[draw.activityKey]}
    var selectable:Bool{draw.runnable(at:model.now) && record?.blocksRepeat != true && !model.locked}
    var body:some View{
        HStack(alignment:.center,spacing:14){
            Button{model.toggle(draw)}label:{Image(systemName:model.selected.contains(draw.id) && selectable ? "checkmark.circle.fill":"circle").font(.title2).foregroundStyle(selectable ? Color.accentColor:Color.secondary.opacity(0.35)).frame(width:30,height:48)}.buttonStyle(.borderless).disabled(!selectable).accessibilityLabel("選擇 \(draw.product)").accessibilityValue(model.selected.contains(draw.id) ? "已選取":"未選取").accessibilityIdentifier("select:\(draw.id)")
            Button(action:onDetail){VStack(alignment:.leading,spacing:8){Text(draw.product).font(.body.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading);HStack(spacing:6){StatusBadge(text:record?.title ?? draw.eligibility(at:model.now).title,color:record != nil ? .secondary:draw.eligibility(at:model.now) == .ready ? .blue:.orange);Text(draw.city).font(.caption).foregroundStyle(.secondary)};Text(draw.eligibility(at:model.now) == .notStarted ? "\(dateText(draw.startsAt)) 開始":"\(dateText(draw.endsAt)) 截止").font(.caption).foregroundStyle(.secondary);if draw.canonicalURL==nil{Text("連結待解析").font(.caption).foregroundStyle(.orange)}}.frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).accessibilityIdentifier("detail:\(draw.id)")
            Image(systemName:"chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }.padding(.vertical,8)
        .swipeActions(edge:.trailing,allowsFullSwipe:false){if record?.status=="MANUAL"{Button("撤銷完成"){if let record{model.undo(record)}}.tint(.orange).disabled(model.locked)}else if record==nil || record!.canMarkManually{Button("標記完成"){model.mark(draw)}.tint(.blue).disabled(model.locked || draw.canonicalURL==nil)}}
    }
}
struct FilterSheet:View{
    @EnvironmentObject var model:AppModel;@Environment(\.dismiss) var dismiss
    var body:some View{NavigationStack{List{
        Section{Button{model.filter.statuses=[]}label:{filterLabel("全部",selected:model.filter.statuses.isEmpty)};ForEach(DrawStatusFilter.allCases){status in Button{if model.filter.statuses.contains(status){model.filter.statuses.remove(status)}else{model.filter.statuses.insert(status)}}label:{filterLabel(status.title,selected:model.filter.statuses.contains(status))}.accessibilityIdentifier("filterStatus:\(status.rawValue)")}}header:{Text("活動狀態 · 可多選")}
        Section{Button{model.filter.cities=[]}label:{filterLabel("所有地區",selected:model.filter.cities.isEmpty)};ForEach(model.cities,id:\.self){city in Button{if model.filter.cities.contains(city){model.filter.cities.remove(city)}else{model.filter.cities.insert(city)}}label:{filterLabel(city,selected:model.filter.cities.contains(city))}.accessibilityIdentifier("filterCity:\(city)")}}header:{Text("地區 · 可多選")}footer:{Text("同一組符合任一條件即可；地區、狀態及搜尋需同時符合。")}
    }.navigationTitle("篩選").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button("重設"){model.filter=CatalogFilter()}};ToolbarItem(placement:.confirmationAction){Button("完成"){dismiss()}.accessibilityIdentifier("doneFilters")}}}.presentationDetents([.medium,.large])}
    func filterLabel(_ title:String,selected:Bool)->some View{HStack{Text(title).foregroundStyle(.primary);Spacer();if selected{Image(systemName:"checkmark").foregroundStyle(.blue)}}.accessibilityValue(selected ? "已選取":"未選取")}
}
struct DrawDetail:View{
    @EnvironmentObject var model:AppModel;@Environment(\.dismiss) var dismiss;let draw:Draw
    var record:ParticipationRecord?{model.records[draw.activityKey]}
    var body:some View{NavigationStack{List{
        Section{VStack(alignment:.leading,spacing:14){Image(systemName:"ticket.fill").font(.largeTitle).foregroundStyle(.blue.gradient);Text(draw.product).font(.title2.bold());Text(draw.store).foregroundStyle(.secondary);StatusBadge(text:record?.title ?? draw.eligibility(at:model.now).title)}}
        Section("活動資訊"){LabeledContent("地區",value:draw.city);LabeledContent("開始",value:dateText(draw.startsAt));LabeledContent("截止",value:dateText(draw.endsAt));Text(draw.timeLabel).font(.footnote).foregroundStyle(.secondary);Text(draw.url).font(.footnote.monospaced()).textSelection(.enabled)}
        if let record{Section("本機紀錄"){Text(record.title).font(.headline);Text(record.evidence).foregroundStyle(.secondary);Text(dateText(record.updatedAt)).font(.caption)}}
        Section{if draw.area != .demo{Button{Task{await model.open(draw)}}label:{Label("在 LINE 開啟",systemImage:"arrow.up.forward.app")}.disabled(model.locked)}
            if record?.status=="MANUAL"{Button("撤銷手動完成"){if let record{model.undo(record)}}.disabled(model.locked).accessibilityIdentifier("undoManual")}
            else if record==nil || record!.canMarkManually{Button{model.mark(draw)}label:{Label("標記已完成",systemImage:"checkmark.circle")}.disabled(model.locked || draw.canonicalURL==nil).accessibilityIdentifier("markManual")}
        }footer:{Text("手動標記不代表中獎。撤銷會恢復標記前狀態，不會清除原有送出紀錄。")}
    }.navigationTitle("活動詳情").navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.confirmationAction){Button("完成"){dismiss()}.accessibilityIdentifier("closeDetail")}}}}
}
struct BatchProgressView:View{
    @EnvironmentObject var model:AppModel
    var body:some View{VStack(alignment:.leading,spacing:12){
        HStack{Label(model.batchActive ? "抽選進行中":"本輪進度",systemImage:model.batchActive ? "arrow.triangle.2.circlepath":"checkmark.circle").font(.headline);Spacer();Text("\(model.batchIndex) / \(model.batchTotal)").monospacedDigit().foregroundStyle(.secondary)}
        ProgressView(value:Double(model.batchIndex),total:Double(max(1,model.batchTotal)))
        Text(model.batchReason).font(.caption).foregroundStyle(.secondary)
        if model.batchActive{HStack{
            Button(model.batchState=="PAUSED" ? "繼續":"暫停"){Task{await model.control(model.batchState=="PAUSED" ? "resume":"pause")}}.buttonStyle(.glass).disabled(model.batchState=="PAUSED" && model.batchBusy)
            if model.area != .demo,model.batchState=="PAUSED"{Button("略過本筆"){Task{await model.control("skip")}}.buttonStyle(.glass).disabled(model.batchBusy)}
            Spacer();Button("停止",role:.destructive){Task{await model.control("stop")}}.buttonStyle(.glass)
        }}
    }.padding(16).glassPanel()}
}
