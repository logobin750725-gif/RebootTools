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
    @State private var log = "正在初始化診斷…"
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
        .onAppear {
            if log == "正在初始化診斷…" {
                log = EnvironmentProbe().report() + "\nphase=app_started\nresult=READY"
            }
        }
        .confirmationDialog("確定檢查並嘗試 Respring？", isPresented: $showingConfirmation) {
            Button("確認") { execute() }
            Button("取消", role: .cancel) {}
        }
        .onChange(of: showingConfirmation) { presented in
            if presented { log += "\nphase=confirmation_presented" }
        } message: {
            Text("未驗證的特權通道不會執行任何重啟指令。")
        }
    }

    private func execute() {
        working = true
        status = "正在檢查可用通道…"
        log = EnvironmentProbe().report() + "\nphase=button_confirmed\nresult=RUNNING"
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
        // RELAXIN's sbreload requires a resolved RootHide jailbreak root and
        // an already-authorized execution context. Never attempt arbitrary
        // privilege escalation, an untrusted helper, or a backboardd kill.
        guard geteuid() == 0 else {
            return RespringResult(
                message: "BLOCKED：App 尚未取得 root 執行權限（euid=\(geteuid())）",
                log: environment + "\nphase=privilege_preflight\nresult=BLOCKED\nerrno=EPERM"
            )
        }
        guard PlatformProbe.isPlatformBinary() else {
            return RespringResult(
                message: "BLOCKED：未通過 RELAXIN 平台執行權限檢查",
                log: environment + "\nphase=platform_preflight\nresult=BLOCKED"
            )
        }
        guard let root = RootHideProbe.jailbreakRoot(),
              root.hasPrefix("/"), !root.contains("..") else {
            return RespringResult(
                message: "BLOCKED：未取得 RootHide systemhook 提供的 jailbreak root",
                log: environment + "\nphase=jbroot_resolution\nresult=BLOCKED"
            )
        }
        let executable = (root as NSString).appendingPathComponent("usr/bin/sbreload")
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            return RespringResult(
                message: "BLOCKED：找不到可執行的 sbreload",
                log: environment + "\nphase=sbreload_preflight\npath=\(executable)\nresult=BLOCKED"
            )
        }
        var pid: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup(executable), nil]
        defer { free(argv[0]) }
        let spawnStatus = argv.withUnsafeBufferPointer { buffer in
            posix_spawn(&pid, executable, nil, nil,
                        UnsafeMutablePointer(mutating: buffer.baseAddress), environ)
        }
        guard spawnStatus == 0 else {
            return RespringResult(
                message: "FAIL：sbreload 無法啟動（\(spawnStatus)）",
                log: environment + "\nphase=posix_spawn\npath=\(executable)\nstatus=\(spawnStatus)\nresult=FAIL"
            )
        }
        return RespringResult(
            message: "已發出 sbreload 指令；SpringBoard 是否完成重啟仍待實機確認",
            log: environment + "\nphase=dispatched\npath=\(executable)\npid=\(pid)\nresult=UNVERIFIED"
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
