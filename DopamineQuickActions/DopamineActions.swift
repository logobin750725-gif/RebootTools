import SwiftUI
import Foundation
import Darwin

@main struct DopamineActions: App {
    var body: some Scene { WindowGroup { MainView() } }
}
struct MainView: View {
    @State private var confirm: Int? = nil
    @State private var showing = false
    @State private var status = "待命"
    var body: some View {
        VStack(spacing: 24) {
            Text("Dopamine 一鍵工具").font(.title).bold()
            Text("iPhone 11 Pro Max · iOS 18.6 · Dopamine 3.x")
            Text("注意：此為測試版，Respring 需要越獄執行權限；Userspace Reboot 請用 Dopamine 官方 App。").font(.footnote)
            Button("⚡ Respring") { confirm = 0; showing = true }
            Button("🔄 Userspace Reboot（請使用 Dopamine 官方 App）") { status = "iOS 18.6：為避免系統異常，請使用 Dopamine 3.0.5+ 內建的 Reboot Userspace 功能。此測試版不直接呼叫舊版系統指令。" }
            Text(status).font(.footnote)
        }
        .padding()
        .confirmationDialog("執行會中斷目前的工作，確定嗎？", isPresented: $showing) {
            Button("確定執行", role: .destructive) {
                if let n = confirm { status = run(n) }
            }
            Button("取消", role: .cancel) {}
        }
    }
    func run(_ n: Int) -> String {
        guard FileManager.default.fileExists(atPath: "/var/jb") else { return "Dopamine 越獄未啟用" }
        guard n == 0 else { return "此版本停用直接 Userspace Reboot，請使用 Dopamine 官方 App。" }
        let path = "/var/jb/usr/bin/killall"
        let args = ["killall", "SpringBoard"]
        guard FileManager.default.isExecutableFile(atPath: path) else { return "找不到可執行檔：\(path)" }
        var pid: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { for p in argv { if let p = p { free(p) } } }
        let rc = argv.withUnsafeBufferPointer {
            posix_spawn(&pid, path, nil, nil, UnsafeMutablePointer(mutating: $0.baseAddress!), environ)
        }
        return rc == 0 ? "已啟動程序 PID \(pid)，實際成功仍待確認" : "啟動失敗：\(rc)，可能需要特權 helper"
    }
}
