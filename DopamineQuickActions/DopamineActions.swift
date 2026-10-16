import SwiftUI
import Foundation
import Darwin
import UIKit

@main struct DopamineActions: App {
    var body: some Scene { WindowGroup { MainView() } }
}

struct MainView: View {
    @State private var report = "按「收集診斷」開始。"
    private let fm = FileManager.default

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("RELAXIN 權限診斷").font(.title2).bold()
                Text("iOS \(UIDevice.current.systemVersion) · 唯讀安全診斷")
                    .font(.footnote)
                Button("收集完整診斷") { report = diagnostics() }
                    .buttonStyle(.borderedProminent)
                Button("⚡ Respring（BLOCKED）") {
                    report = diagnostics() + "\n\nRespring: BLOCKED。尚無經核實的 RELAXIN 特權 API 或 Helper；未執行 SpringBoard 終止。"
                }.buttonStyle(.bordered)
                Button("🔄 Userspace Reboot（BLOCKED）") {
                    report = diagnostics() + "\n\nUserspace Reboot: BLOCKED。iOS 18.6 / RELAXIN v0.5.5 相容性與特權通道未核實。"
                }.buttonStyle(.bordered)
                Button("複製完整診斷文字") { UIPasteboard.general.string = report }
                    .buttonStyle(.bordered)
                Text(report).font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding()
        }
    }

    private func diagnostics() -> String {
        let uid = getuid(), euid = geteuid(), gid = getgid(), egid = getegid()
        var lines: [String] = [
            "RELAXIN diagnostic v0.3 (read-only)",
            "iOS=\(UIDevice.current.systemVersion)",
            "uid=\(uid) euid=\(euid) gid=\(gid) egid=\(egid)",
            "sandbox=UNKNOWN (no supported entitlement/API probe; file visibility is not proof)",
            "RELAXIN=UNVERIFIED; RootHide=UNVERIFIED (no documented third-party detection API confirmed)",
            "App bundle=\(Bundle.main.bundlePath)",
            "Home=\(NSHomeDirectory())",
            "Process PATH=\(ProcessInfo.processInfo.environment["PATH"] ?? "<unset>")"
        ]
        // Show only non-sensitive, explicitly selected environment keys.
        let keys = ["JBROOT", "THEOS", "DYLD_ROOT_PATH", "PATH", "HOME", "TMPDIR"]
        for key in keys {
            lines.append("env[\(key)]=\(ProcessInfo.processInfo.environment[key] ?? "<unset>")")
        }
        let roots = [
            ProcessInfo.processInfo.environment["JBROOT"],
            ProcessInfo.processInfo.environment["DYLD_ROOT_PATH"],
            "/var/jb", "/private/var/jb", "/private/preboot", "/usr/local",
            "/var/containers/Bundle/Application"
        ].compactMap { $0 }.filter { $0.hasPrefix("/") }
        let uniqueRoots = Array(Set(roots)).sorted()
        for root in uniqueRoots {
            var isDir: ObjCBool = false
            let exists = fm.fileExists(atPath: root, isDirectory: &isDir)
            lines.append("root candidate \(root): visible=\(exists) directory=\(isDir.boolValue)")
        }
        var paths = ["/usr/bin/killall", "/bin/launchctl"]
        for root in uniqueRoots {
            paths += [root + "/usr/bin/killall", root + "/bin/launchctl",
                      root + "/usr/bin/sbreload", root + "/usr/bin/ldrestart"]
        }
        for name in ["RebootUserSpaceHelper", "RebootRootHelper"] {
            if let bundled = Bundle.main.path(forResource: name, ofType: nil) {
                paths.append(bundled)
            } else {
                lines.append("bundled helper \(name)=MISSING")
            }
        }
        for p in Array(Set(paths)).sorted() {
            lines.append("absolute path=\(p) exists=\(fm.fileExists(atPath: p)) executable=\(fm.isExecutableFile(atPath: p))")
        }
        lines += [
            "requested argv=[\"killall\", \"SpringBoard\"] (NOT EXECUTED)",
            "spawn environment=NOT PASSED; posix_spawn=NOT ATTEMPTED",
            "posix_spawn return=N/A errno=N/A pid=N/A",
            "waitpid=N/A exit code=N/A stdout=N/A stderr=N/A",
            "Respring=BLOCKED; Userspace Reboot=BLOCKED",
            "missing=verified RELAXIN v0.5.5 third-party privileged API or signed/installed helper",
            "note=UID 0 alone does not establish sandbox escape or SpringBoard control."
        ]
        return lines.joined(separator: "\n")
    }
}
