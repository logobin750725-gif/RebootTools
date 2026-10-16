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
        .onReceive(NotificationCenter.default.publisher(for: .init("DopamineActionResult"))) { notification in
            if let message = notification.object as? String { status = message }
        }
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
        guard rc == 0 else { return "啟動失敗：\(rc)，\(String(cString: strerror(rc)))" }
        DispatchQueue.global(qos: .utility).async {
            var waitStatus: Int32 = 0
            let waited = waitpid(pid, &waitStatus, 0)
            let message: String
            if waited == -1 {
                message = "無法取得程序結果：\(errno)"
            } else if (waitStatus & 0x7f) == 0 {
                message = "killall exit code：\((waitStatus >> 8) & 0xff)。若未 Respring，可能沒有權限。"
            } else {
                message = "killall 因訊號結束：\(waitStatus & 0x7f)"
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .init("DopamineActionResult"), object: message)
            }
        }
        return "已送出指令，正在檢查結果（PID \(pid)）"
    }
}
