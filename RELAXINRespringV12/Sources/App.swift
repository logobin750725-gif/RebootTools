import SwiftUI
import Foundation
import Darwin

@main struct RELAXINRespringApp: App {
    var body: some Scene { WindowGroup { RespringView() } }
}
enum JailbreakRoot {
    static func detect() -> (String, String)? {
        if let handle = dlopen("systemhook.dylib", RTLD_NOW) {
            defer { dlclose(handle) }
            if let sym = dlsym(handle, "get_jbroot") {
                typealias Getter = @convention(c) () -> UnsafePointer<CChar>?
                if let value = unsafeBitCast(sym, to: Getter.self)() {
                    let path = String(cString: value)
                    if FileManager.default.fileExists(atPath: path) { return (path, "systemhook") }
                }
            }
        }
        if let value = getenv("JBROOT") {
            let path = String(cString: value)
            if FileManager.default.fileExists(atPath: path) { return (path, "JBROOT") }
        }
        if FileManager.default.fileExists(atPath: "/var/jb") { return ("/var/jb", "standard-rootless") }
        return nil
    }
}
struct Diagnostics {
    static func report() -> String {
        var flags: UInt32 = 0
        var result = "csops unavailable"
        typealias Csops = @convention(c) (pid_t, UInt32, UnsafeMutableRawPointer, Int) -> Int32
        if let h = dlopen(nil, RTLD_NOW) {
            defer { dlclose(h) }
            if let symbol = dlsym(h, "csops") {
                let code = unsafeBitCast(symbol, to: Csops.self)(getpid(), 0, &flags, MemoryLayout<UInt32>.size)
                result = "csops=\(code) flags=0x\(String(flags,radix:16)) platform=\(code == 0 && (flags & 0x04000000) != 0)"
            }
        }
        let root = JailbreakRoot.detect()
        return (["iOS=\(UIDevice.current.systemVersion)", "uid=\(getuid()) euid=\(geteuid())", result, "root=\(root?.0 ?? "UNVERIFIED") source=\(root?.1 ?? "UNVERIFIED")"] + Runner.candidates().map { "\($0.path): exists=\(FileManager.default.fileExists(atPath:$0.path)) X_OK=\(access($0.path, X_OK) == 0)" }).joined(separator:"\n")
    }
}
struct Runner {
    struct Candidate { let path: String; let args: [String] }
    static func candidates() -> [Candidate] {
        let root = JailbreakRoot.detect()?.0
        let prefixes = root.map { [$0] } ?? []
        let roots = prefixes + ["/var/jb", ""]
        var found = Set<String>()
        var list = [Candidate]()
        for prefix in roots {
            for item in [("/usr/bin/sbreload", [String]()), ("/bin/launchctl", ["kickstart","-k","system/com.apple.SpringBoard"]), ("/usr/bin/killall", ["-9","SpringBoard"])] {
                let path = prefix + item.0
                if !found.contains(path) { found.insert(path); list.append(Candidate(path:path,args:item.1)) }
            }
        }
        return list
    }
    static func spawn(_ candidate: Candidate) -> String {
        var pid: pid_t = 0
        let argv = ([candidate.path] + candidate.args).map { strdup($0) } + [nil]
        defer { for pointer in argv { if let pointer = pointer { free(pointer) } } }
        let rc = argv.withUnsafeBufferPointer { buffer in
            posix_spawn(&pid, candidate.path, nil, nil, buffer.baseAddress!, environ)
        }
        guard rc == 0 else { return "spawn=\(rc)" }
        var status: Int32 = 0
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let ret = waitpid(pid, &status, WNOHANG)
            if ret == pid {
                let signal = status & 0x7f
                if signal == 0 { return "exit=\((status >> 8) & 0xff)" }
                return "signal=\(signal)"
            }
            if ret == -1 {
                if errno == EINTR { continue }
                return "waitpid-error=\(errno)"
            }
            usleep(25_000)
        }
        DispatchQueue.global().async { var s:Int32 = 0; _ = waitpid(pid, &s, 0) }
        return "timeout=3s; process may still be running"
    }
    static func run() -> String {
        var logs = [String]()
        for candidate in candidates() {
            guard FileManager.default.fileExists(atPath:candidate.path), access(candidate.path,X_OK) == 0 else { continue }
            let outcome = spawn(candidate)
            logs.append("\(candidate.path): \(outcome)")
            if outcome == "exit=0" { return logs.joined(separator:"\n") + "\nCommand exited 0; device respring NOT VERIFIED" }
            if outcome.hasPrefix("timeout=") { return logs.joined(separator:"\n") + "\nStatus unverified; stopped fallback attempts" }
        }
        return logs.isEmpty ? "No executable respring command found" : logs.joined(separator:"\n")
    }
}
struct RespringView: View {
    @State private var confirmation = false
    @State private var running = false
    @State private var status = "尚未執行"
    @State private var log = Diagnostics.report()
    var body: some View {
        VStack(spacing:20) {
            Text("RELAXIN Respring").font(.largeTitle.bold())
            Text(status).multilineTextAlignment(.center)
            Button("執行 Respring") { confirmation = true }.disabled(running).buttonStyle(.borderedProminent)
            DisclosureGroup("完整診斷紀錄") {
                ScrollView { Text(log).font(.system(.caption,design:.monospaced)).frame(maxWidth:.infinity,alignment:.leading).textSelection(.enabled) }.frame(height:250)
                HStack {
                    Button("重新整理") { log = Diagnostics.report() }
                    Button("複製診斷") { UIPasteboard.general.string = log }
                }
            }
            Spacer()
        }.padding()
        .alert("確認執行 Respring",isPresented:$confirmation) {
            Button("取消",role:.cancel) {}
            Button("確認執行",role:.destructive) { execute() }
        } message: { Text("將嘗試重載 SpringBoard；請先儲存工作。") }
    }
    private func execute() {
        running = true
        status = "執行中…"
        DispatchQueue.global(qos:.userInitiated).async {
            let outcome = Runner.run()
            DispatchQueue.main.async {
                running = false
                status = outcome
                log = Diagnostics.report() + "\n\n" + outcome
            }
        }
    }
}
