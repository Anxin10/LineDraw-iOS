import SwiftUI
import LineDrawCore

@main struct LineDrawApp:App{
    @StateObject private var model=AppModel()
    var body:some Scene{WindowGroup{RootView().environmentObject(model).preferredColorScheme(model.colorScheme).tint(Color.accentColor)}}
}
struct RootView:View{
    @EnvironmentObject private var model:AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var tab=0
    @State private var showDeviceSetup=false
    var body:some View{
        Group{
            if model.accepted {
                TabView(selection:$tab){
                    Tab("抽選",systemImage:"ticket",value:0){CatalogView()}
                    Tab("紀錄",systemImage:"clock.arrow.circlepath",value:1){HistoryView()}
                    Tab("設定",systemImage:"gearshape",value:2){SettingsView()}
                }
            }else{ConsentView()}
        }
        .transaction{if systemReduceMotion || model.data.settings.reduceMotion{$0.disablesAnimations=true;$0.animation=nil}}
        .alert("提醒",isPresented:Binding(get:{model.error != nil},set:{if !$0{model.error=nil}})){Button("知道了",role:.cancel){model.error=nil}}message:{Text(model.error ?? "")}
        .task(id:scenePhase){guard scenePhase == .active else{return};while !Task.isCancelled{model.now=Date();await model.poll();try? await Task.sleep(for:.seconds(3))}}
        .sheet(isPresented:$showDeviceSetup){NavigationStack{DeviceSetupView().toolbar{ToolbarItem(placement:.confirmationAction){Button("完成"){showDeviceSetup=false}}}}}
        .onOpenURL{url in
            guard model.accepted,url.scheme=="linedraw" else{return}
            if url.host=="pair"{Task{await model.pair(url.absoluteString)}}
            if url.host=="device-setup"{tab=2;showDeviceSetup=true}
        }
    }
}
struct GlassPanel:ViewModifier{
    @EnvironmentObject var model:AppModel
    @Environment(\.accessibilityReduceTransparency) var systemReduce
    func body(content:Content)->some View{
        if model.data.settings.reduceTransparency || systemReduce{content.background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:24))}
        else{content.glassEffect(.regular,in:.rect(cornerRadius:24))}
    }
}
extension View{func glassPanel()->some View{modifier(GlassPanel())}}
struct AppBackdrop:View{
    @Environment(\.colorScheme) var scheme
    var body:some View{LinearGradient(colors:scheme == .dark ? [Color(red:0.04,green:0.07,blue:0.13),Color(red:0.10,green:0.09,blue:0.17)]:[Color(red:0.92,green:0.96,blue:1),Color(red:0.97,green:0.95,blue:1),Color(uiColor:.systemGroupedBackground)],startPoint:.topLeading,endPoint:.bottomTrailing).ignoresSafeArea()}
}
func dateText(_ date:Date?)->String{guard let date else{return "時間未確認"};let f=DateFormatter();f.locale=Locale(identifier:"zh_TW");f.timeZone=TimeZone(identifier:"Asia/Taipei");f.dateFormat="MM/dd HH:mm";return f.string(from:date)}
struct StatusBadge:View{
    let text:String;var color:Color = .blue
    var body:some View{Text(text).font(.caption.weight(.semibold)).foregroundStyle(color).padding(.horizontal,9).padding(.vertical,5).background(color.opacity(0.09),in:Capsule()).fixedSize(horizontal:false,vertical:true)}
}
struct ConsentView:View{
    @EnvironmentObject var model:AppModel
    @State private var declined=false
    var body:some View{
        NavigationStack{ScrollView{VStack(alignment:.leading,spacing:24){
            Image(systemName:"ticket.fill").font(.system(size:48)).foregroundStyle(.blue).padding(24).glassPanel().frame(maxWidth:.infinity)
            VStack(alignment:.leading,spacing:8){Text("讓每一次抽選，\n接續發生。").font(.largeTitle.bold());Text("LineDraw · 在 iPhone 接續完成").foregroundStyle(.secondary)}
            ForEach(Array(UsageDeclaration.paragraphs.enumerated()),id:\.offset){i,text in HStack(alignment:.top,spacing:14){Image(systemName:["curlybraces","hand.tap","pause.circle","externaldrive"][i]).foregroundStyle(.blue).frame(width:24);Text(text).font(.body).fixedSize(horizontal:false,vertical:true)}}
            Text("首次使用及說明更新時，需要重新同意。\nPolyForm Noncommercial 1.0.0 · 限非商業使用").font(.footnote).foregroundStyle(.secondary)
            if declined{Text("你尚未同意，功能保持關閉。可直接關閉 App，或重新閱讀後同意。").foregroundStyle(.secondary).accessibilityIdentifier("consentDeclined")}
            Button("同意並開始使用"){model.accept()}.buttonStyle(.glassProminent).controlSize(.large).frame(maxWidth:.infinity).accessibilityIdentifier("acceptConsent").disabled(model.fatalStorage)
            Button("不同意"){model.decline();declined=true}.frame(maxWidth:.infinity).accessibilityIdentifier("declineConsent")
        }.padding(24)}.background{AppBackdrop()}.navigationTitle("歡迎使用").navigationBarTitleDisplayMode(.inline)}
    }
}

struct AdaptiveStack<Content:View>:View{
    @Environment(\.dynamicTypeSize) var size
    @ViewBuilder var content:()->Content
    var body:some View{let layout:AnyLayout=size.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:12)):AnyLayout(HStackLayout());layout{content()}}
}
