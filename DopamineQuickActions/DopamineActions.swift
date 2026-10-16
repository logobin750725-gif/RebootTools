import SwiftUI
import UIKit
import Darwin

@main struct RELAXINRespringApp: App {
    var body: some Scene { WindowGroup { RespringView() } }
}

struct RespringView: View {
    @State private var showingConfirmation = false
    @State private var working = false
    @State private var status = "尚未確認 RELAXIN v0.5.5 的第三方 Respring 特權通道"
    @State private var log = "等待診斷"
    private let service = RespringService()

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("RELAXIN Respring").font(.title2).bold()
            Button {
                showingConfirmation = true
            } label: {
                Text(working ? "檢查中…" : "⚡ Respring")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
            .buttonStyle(.borderedProminent)
            .disabled(working)
            Text(status).foregroundColor(.secondary).multilineTextAlignment(.center)
            Spacer()
            DisclosureGroup("診斷紀錄") {
                ScrollView {
                    Text(log).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 210)
                Button("複製診斷") { UIPasteboard.general.string = log }
            }
        }
        .padding(24)
        .confirmationDialog("確定檢查並嘗試 Respring？", isPresented: $showingConfirmation) {
            Button("確認") { execute() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("未驗證的特權通道不會執行任何重啟指令。")
        }
    }

    private func execute() {
        working = true
        status = "正在檢查可用通道…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = service.request()
            DispatchQueue.main.async {
                status = result.message
                log = result.log
                working = false
            }
        }
    }
}

struct RespringResult {
    let message: String
    let log: String
}

struct RespringService {
    func request() -> RespringResult {
        let environment = EnvironmentProbe().report()
        // No verified third-party RELAXIN v0.5.5 service, socket, notification,
        // helper, or URL scheme is known. Never infer authorization from a path.
        return RespringResult(
            message: "BLOCKED：尚無已驗證的 RELAXIN 特權 API／Helper。請使用 RELAXIN 內建 Respring。",
            log: environment + "\nrequest=Respring\nchannel=NONE_VERIFIED\nargv=NOT_EXECUTED\nposix_spawn=NOT_ATTEMPTED\nwaitpid=NOT_ATTEMPTED\nerrno=N/A\nstdout=N/A\nstderr=N/A\nresult=BLOCKED"
        )
    }
}

struct EnvironmentProbe {
    func report() -> String {
        let env = ProcessInfo.processInfo.environment
        let fm = FileManager.default
        let paths = ["/var/jb", "/private/var/jb", "/private/preboot",
                     "/usr/bin/killall", "/usr/bin/sbreload"]
        let details = paths.map {
            "\($0): visible=\(fm.fileExists(atPath: $0)), executable=\(fm.isExecutableFile(atPath: $0))"
        }.joined(separator: "\n")
        return "iOS=\(UIDevice.current.systemVersion)\nuid=\(getuid()) euid=\(geteuid()) gid=\(getgid()) egid=\(getegid())\nsandbox=UNKNOWN\nRELAXIN=UNVERIFIED\nRootHide=UNVERIFIED\nPATH=\(env["PATH"] ?? "<unset>")\nJBROOT=\(env["JBROOT"] ?? "<unset>")\n" + details
    }
}
