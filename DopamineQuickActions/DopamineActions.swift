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
        ScrollView {
          VStack(spacing: 18) {
            Text("RELAXIN 工具診斷").font(.title2).bold().minimumScaleFactor(0.8)
            Text("裝置：\(UIDevice.current.model) · iOS \(UIDevice.current.systemVersion)")
                .font(.subheadline)
            Text("RELAXIN 插件注入已開啟不等於此 App 有系統特權。此版本先檢查指令執行結果。").font(.footnote)
            Button("檢查環境與權限") {
                status = diagnostics()
            }
            Button("⚡ Respring") { confirm = 0; showing = true }
            Button("🔄 Userspace Reboot（暫停）") { status = "尚未確認 RELAXIN 的安全 Userspace Reboot 介面；此版本不執行重啟。" }
            Text("執行狀態").font(.headline)
            Text(status).font(.body).foregroundColor(.red).multilineTextAlignment(.center)
            Button("複製診斷結果") { UIPasteboard.general.string = status }
          }.frame(maxWidth: .infinity)
        }.padding()
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
    func diagnostics() -> String {
        let paths = ["/var/jb", "/var/jb/usr/bin/killall", "/usr/bin/killall"]
        let lines = paths.map { p in
            "\(p): exists=\(FileManager.default.fileExists(atPath: p)), executable=\(FileManager.default.isExecutableFile(atPath: p))"
        }
        return "UID=\(getuid()), EUID=\(geteuid())\n" + lines.joined(separator: "\n") + "\n提示：檔案存在或 EUID=0 不代表能控制 SpringBoard。"
    }
    func run(_ n: Int) -> String {
        guard n == 0 else { return "Userspace Reboot 尚未通過相容性驗證，禁止執行。" }
        let rootless = FileManager.default.fileExists(atPath: "/var/jb")
        let candidates = ["/var/jb/usr/bin/killall", "/usr/bin/killall"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return "找不到 killall；/var/jb 存在：\(rootless)。檢查 RELAXIN 路徑與權限。"
        }
        guard geteuid() == 0 else {
            return "BLOCKED：EUID=\(geteuid())，目前 App 沒有 root 身分；不執行無權限的 SpringBoard 終止指令。\n" + diagnostics()
        }
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
