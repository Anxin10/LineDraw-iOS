import SwiftUI

@main
struct FixtureApp: App {
    @State private var coupon = ""
    @State private var loading = false
    @State private var submitted = false
    @State private var friendAdded = false
    @State private var generation = 0
    @State private var sends = 0
    @State private var friends = 0
    private let second = "01M34QQ7QZNTMR8M7ADSWXY7AW"
    private let third = "01M34QQXZ27VBQPSY134CD6FG4"
    private let fourth = "01M34QRHHTGYP0NZ594RCR9Z6T"
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 20) {
                HStack {
                    Text(coupon.isEmpty ? "LineDraw 離線測試" : "官方帳號優惠券").font(.title2).bold()
                    Spacer()
                    if !coupon.isEmpty {
                        Button("關閉") { coupon = ""; generation += 1; loading = false }
                    }
                }.padding()
                if coupon.isEmpty {
                    Text("僅供 WDA 自動化測試；不連線 LINE。").padding()
                } else if loading {
                    ProgressView("載入中")
                } else {
                    Text("陀螺獵人抽選測試").font(.title).bold()
                    Text("這是獨立測試 App，沒有真實抽選。")
                    if coupon == "captcha" { Text("請輸入驗證碼") }
                    if submitted { Text("恭喜中獎") }
                    Text("查看我的優惠券")
                }
                Spacer()
                Text("測試送出 \(sends) 次；加入好友 \(friends) 次").font(.footnote)
                if !coupon.isEmpty && !loading && coupon != "captcha" && coupon != "unknown" {
                    Button(action: perform) {
                        Text(buttonLabel).font(.title3).bold().frame(maxWidth: .infinity).padding(20)
                    }.buttonStyle(.borderedProminent).padding(.horizontal, 12).padding(.bottom, 12)
                        .disabled(coupon == third)
                        .accessibilityHidden(coupon == "image")
                }
            }
            .onOpenURL { url in
                guard url.scheme == "linedraw-fixture", url.host == "coupon" else { return }
                let next = url.lastPathComponent
                generation += 1
                let expected = generation
                coupon = next; submitted = false; loading = true
                DispatchQueue.main.asyncAfter(deadline: .now() + (next == "slow" ? 3 : 0.6)) {
                    if generation == expected { loading = false }
                }
            }
        }
    }
    var buttonLabel: String {
        if coupon == third { return "已結束" }
        if coupon == fourth || submitted { return "查看已領取的優惠券" }
        if coupon == second && !friendAdded { return "加入好友" }
        if coupon == "01M34QPHTDYX6TQ5F0M5TKP5J7" { return "加入好友並參加抽獎" }
        return "抽選"
    }
    func perform() {
        if coupon == third || coupon == fourth || submitted { return }
        if coupon == second && !friendAdded { friendAdded = true; friends += 1; return }
        sends += 1; submitted = true
    }
}
