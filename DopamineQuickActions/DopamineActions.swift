import SwiftUI
import UIKit
import Darwin

@main struct RELAXINRespringApp: App {
    var body: some Scene { WindowGroup { RespringView() } }
}

struct RespringView: View {
    @State private var showingConfirmation = false
    @State private var status = "尚未確認 RELAXIN v0.5.5 的第三方 Respring 特權通道"
    @State private var log = "正在初始化診斷…"
    @State private var lastCheck = "NOT_RUN"
    private let service = RespringService()

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("RELAXIN Respring").font(.title2).bold()
            Button {
                log += "\nphase=button_tapped"
                showingConfirmation = true
            } label: {
                Text("檢查 Respring 授權")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, minHeight: 80)
            }
            .buttonStyle(.borderedProminent)
            Text(status).foregroundColor(.secondary).multilineTextAlignment(.center)
            Text("功能狀態：BLOCKED｜授權檢查：\(lastCheck)")
                .font(.caption).foregroundColor(.secondary)
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
        .onAppear {
            if log == "正在初始化診斷…" {
                log = EnvironmentProbe().report() + "\nphase=app_started\nresult=READY"
            }
        }
        .confirmationDialog("僅檢查環境與授權狀態，不會執行 Respring。是否繼續？", isPresented: $showingConfirmation) {
            Button("開始唯讀檢查") { execute() }
            Button("取消", role: .cancel) {}
        }
        .onChange(of: showingConfirmation) { presented in
            if presented { log += "\nphase=confirmation_presented" }
        }
    }

    private func execute() {
        let result = service.request()
        status = result.message
        lastCheck = "UNVERIFIED"
        log = result.log + "\nphase=read_only_check_confirmed"
    }
}

struct RespringResult {
    let message: String
    let log: String
}

struct RespringService {
    func request() -> RespringResult {
        let environment = EnvironmentProbe().report()
        // This standalone binary has no verified RELAXIN v0.5.5 third-party
        // authorization interface. Platform flags, root UID and a visible
        // sbreload binary alone do not establish official authorization.
        // Fail closed BEFORE any process spawn, even on a privileged device.
        return RespringResult(
            message: "BLOCKED：尚無已驗證的 RELAXIN 官方第三方 Respring 通道",
            log: environment + "\nphase=official_channel_preflight\nchannel=UNVERIFIED\nspawn=NOT_ATTEMPTED\nresult=BLOCKED"
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
        let platformProbe = PlatformProbe.report()
        let rootProbe = RootHideProbe.jailbreakRoot() ?? "UNAVAILABLE"
        return "platform_probe=\(platformProbe)\nroot_hide_root=\(rootProbe)\niOS=\(UIDevice.current.systemVersion)\nuid=\(getuid()) euid=\(geteuid()) gid=\(getgid()) egid=\(getegid())\nsandbox=UNKNOWN\nRELAXIN=UNVERIFIED\nRootHide=UNVERIFIED\nPATH=\(env["PATH"] ?? "<unset>")\nJBROOT=\(env["JBROOT"] ?? "<unset>")\n" + details
    }
}

struct PlatformProbe {
    // Mirrors RELAXIN's csops(CS_OPS_STATUS) platform-binary preflight.
    // It does NOT confer platform privileges or bypass sandboxing.
    static func isPlatformBinary() -> Bool {
        return statusAndFlags().map { ($0 & 0x04000000) != 0 } ?? false
    }

    private static func statusAndFlags() -> UInt32? {
        typealias CSOps = @convention(c) (pid_t, UInt32, UnsafeMutableRawPointer?, Int) -> Int32
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "csops") else { return nil }
        defer { dlclose(handle) }
        let call = unsafeBitCast(symbol, to: CSOps.self)
        var flags: UInt32 = 0
        let status = withUnsafeMutablePointer(to: &flags) {
            call(getpid(), 0, UnsafeMutableRawPointer($0), MemoryLayout<UInt32>.size)
        }
        return status == 0 ? flags : nil
    }

    static func report() -> String {
        typealias CSOps = @convention(c) (pid_t, UInt32, UnsafeMutableRawPointer?, Int) -> Int32
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "csops") else {
            return "csops=UNAVAILABLE"
        }
        defer { dlclose(handle) }
        let call = unsafeBitCast(symbol, to: CSOps.self)
        var flags: UInt32 = 0
        errno = 0
        let status = withUnsafeMutablePointer(to: &flags) {
            call(getpid(), 0, UnsafeMutableRawPointer($0), MemoryLayout<UInt32>.size)
        }
        let errorCode = status == 0 ? 0 : errno
        let platform = status == 0 && (flags & 0x04000000) != 0
        return "csops_status=\(status) csflags=0x\(String(flags, radix: 16)) platform=\(platform) errno=\(errorCode)"
    }
}

struct RootHideProbe {
    // Match RELAXIN's RTLD_NOLOAD systemhook check; never invent a JBROOT.
    static func jailbreakRoot() -> String? {
        guard let handle = dlopen("systemhook.dylib", RTLD_NOW | RTLD_NOLOAD) else {
            return nil
        }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "get_jbroot") else { return nil }
        typealias GetRoot = @convention(c) () -> UnsafePointer<CChar>?
        let getRoot = unsafeBitCast(symbol, to: GetRoot.self)
        guard let ptr = getRoot() else { return nil }
        let root = String(cString: ptr)
        return root.isEmpty ? nil : root
    }
}
