import SwiftUI
import Foundation
import Darwin
import UIKit

@main struct DopamineActions: App {
    var body: some Scene { WindowGroup { MainView() } }
}
struct MainView: View {
    @State private var confirm: Int? = nil
    @State private var showing = false
    @State private var status = "待命"
    var body: some View {
        VStack(spacing: 24) {
            Text("RELAXIN 一鍵工具（診斷版）").font(.title).bold()
            Text("iPhone 11 Pro Max · iOS 18.6 · RELAXIN v0.5.5")
            Text("RELAXIN 插件注入已開啟不等於此 App 有系統特權。此版本先檢查指令執行結果。").font(.footnote)
            Button("⚡ Respring") { confirm = 0; showing = true }
            Button("🔄 Userspace Reboot（暫停）") { status = "尚未確認 RELAXIN 的安全 Userspace Reboot 介面；此版本不執行重啟。" }
            Text("執行狀態").font(.headline)
            Text(status).font(.body).foregroundColor(.red).multilineTextAlignment(.center)
            Button("複製診斷結果") { UIPasteboard.general.string = status }
        }
        .padding()
        .onReceive(NotificationCenter.default.publisher(for: .init("DopamineActionResult"))) { notification in
            if let message = notification.object as? String { status = message }
        }
        .confirmationDialog("執行會中斷目前的工作，確定嗎？", isPresented: $showing) {
            Button("確定執行", role: .destructive) {
                if let n = confirm {
                    status = "已按下確定執行，開始檢查…"
                    DispatchQueue.global(qos: .userInitiated).async {
                        let result = run(n)
                        DispatchQueue.main.async { status = result }
                    }
                }
            }
            Button("取消", role: .cancel) {}
        }
    }
    func run(_ n: Int) -> String {
        let rootless = FileManager.default.fileExists(atPath: "/var/jb")
        let candidates = ["/var/jb/usr/bin/killall", "/usr/bin/killall"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return "找不到 killall；/var/jb 存在：\(rootless)。檢查 RELAXIN 路徑與權限。"
        }
        guard n == 0 else { return "此版本停用直接 Userspace Reboot，待確認 RELAXIN 官方介面。" }
        let args = ["killall", "SpringBoard"]
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
        return "已送出：\(path)，PID \(pid)，等待程序結果…"
    }
}
