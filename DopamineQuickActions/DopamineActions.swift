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
            Text("僅限已啟用 Dopamine 越獄的裝置")
            Button("⚡ Respring") { confirm = 0; showing = true }
            Button("🔄 Userspace Reboot") { confirm = 1; showing = true }
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
        let path = n == 0 ? "/var/jb/usr/bin/killall" : "/bin/launchctl"
        let args = n == 0 ? ["killall", "SpringBoard"] : ["launchctl", "reboot", "userspace"]
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
