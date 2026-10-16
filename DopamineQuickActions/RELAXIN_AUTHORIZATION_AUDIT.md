# RELAXIN Respring — authorization evidence and release gate

## Target
iPhone12,5 / iOS 18.6 / RELAXIN v0.5.5 RootHide / TrollStore Lite.

## Verified public implementation (owngoal-dev/Relaxin, public default branch)
- `RelaxinPostJailbreak/Actions/RLXRestartSpringBoardAction.m` implements `RLXPostJailbreakRestartSpringBoard` as an **in-process RELAXIN action** using `RLXPostJailbreakRunAsEffectiveRoot`, `RLXPostJailbreakRunUnsandboxed`, `JBROOT_PATH("/usr/bin/sbreload")`, and suspended process execution/resume/wait. This is **not** a verified public third-party API.
- `RelaxinPostJailbreak/Actions/RLXPostJailbreakActionRunner.m` obtains root via `seteuid(0)` / `setegid(0)` and may use `jbclient_root_set_mac_label`; these calls can fail and do not confer privileges on another app.
- `Vendor/Dopamine/BaseBin/libjailbreak/src/jbclient_xpc.h` declares `jbclient_process_checkin`, `jbclient_get_jbroot`, `jbclient_root_set_mac_label`, and `jbclient_roothide_jailbroken`. Presence in source is **not** evidence of an authorized external endpoint.
- `Vendor/Dopamine/BaseBin/libjailbreak/src/jbclient_roothide.c` sends RootHide-domain requests to jailbreakd; no third-party Respring contract has been verified.
- Public repository default branch is not proof of the user's installed RELAXIN v0.5.5 binary or iOS 18.6 support.

## Additional upstream execution semantics (verified from source)
- `RLXPostJailbreakActionIdentifier` maps Restart SpringBoard to the string `restart_springboard`. This is an **internal action identifier**, not an IPC endpoint or externally callable URL.
- `RLXPostJailbreakInstalledThroughTrollStore()` checks a sibling `_TrollStore` marker. This affects the upstream app's sandbox path; the marker **does not grant root or third-party authorization**.
- `RLXPostJailbreakRunAsEffectiveRoot()` requires successful `seteuid(0)` and `setegid(0)` when the caller is non-root. An app reporting UID/EUID 501 cannot assume those calls will succeed.
- `RLXPostJailbreakRunUnsandboxed()` records an error if `jbclient_root_set_mac_label` fails, but still invokes its operation and then attempts label restoration. Do not copy this flow into a third-party app without proving the caller's permissions and rollback behavior.
- The upstream action resumes a suspended `sbreload` process and may fall back to signaling `backboardd`; neither mechanism is appropriate for speculative third-party invocation.

## Device evidence provided by user
`uid=euid=gid=egid=501`; JBROOT unset; `/var/jb` and `/private/var/jb` invisible; `/private/preboot` visible but no verified `sbreload`; no verified third-party helper, XPC, daemon, socket or URL scheme.

## Security invariant
Until a version-matched RELAXIN-provided, authorized third-party contract is demonstrated and validated on device:
1. Show `BLOCKED`.
2. Do not spawn `sbreload`, signal SpringBoard/backboardd, switch UID/GID, or guess an XPC endpoint.
3. Emit `channel=UNVERIFIED`, `spawn=NOT_ATTEMPTED`, `result=BLOCKED`.
4. CI checks this invariant statically; CI success is **not** device Respring success.

## Evidence required before changing behavior
- Exact official API/IPC symbol and provenance for installed RELAXIN v0.5.5, plus required authorization policy.
- Device logs showing an authenticated successful check-in and authorized action request.
- Controlled iPhone12,5 / iOS 18.6 test demonstrating actual SpringBoard restart and correct error handling.
- CI compile/sign/package pass and separate real-device PASS/FAIL record.

## Status
Build: GitHub Actions #38876637236 success (commit `03c30e02`).
Official third-party channel: UNVERIFIED / BLOCKED.
Actual device Respring: NOT TESTED.

## Framework interface discovered (source audit, not a third-party permission grant)
- Upstream `RelaxinPostJailbreak/RelaxinPostJailbreak.h` imports `RLXPostJailbreakController.h` as an Objective-C framework header.
- The controller header declares `isAvailable`, `hasActiveRootHideRuntime`, and `performAction:outputHandler:completion:` with `RLXPostJailbreakActionRestartSpringBoard`.
- The upstream Swift `PostJailbreakSession` instantiates the controller within RELAXIN and checks runtime availability before calling `perform(action:...)`.
- **Interpretation:** this is a real framework API at source level, but no evidence yet establishes a distributable, loadable third-party framework on the user's device, its ABI compatibility with v0.5.5, or the independent app's root/sandbox authorization. Header visibility is not authorization.
- **Release gate remains CLOSED:** do not link or call this API from the standalone IPA until dependency packaging, exact v0.5.5 compatibility, runtime privileges and a safe device test are verified.

## v0.5.5 release artifact provenance (confirmed release metadata, NOT binary inspection)
- GitHub release: https://github.com/5hux1n/relaxin/releases/tag/v0.5.5
- Published: 2026-10-06T14:25:56Z; release text says the repository is an **auto-mirror**, not itself proof of original upstream signing or source-to-binary equivalence.
- `Relaxin-v0.5.5.ipa`: 38,221,108 bytes; release API SHA-256 `91398555cd74d64a70de7ddb1dcf49656372090f1e7e512a0be83eada662fae3`.
- `Relaxin-v0.5.5.tipa`: 38,273,380 bytes; release API SHA-256 `01de8538699e3ff84d62196bacfae480d6b9afa6cdd9c46b45e5241f81f0878c`.
- Release notes mention improved TrollStore Lite compatibility, **not** an authorized standalone third-party Respring interface.
- These checksums are metadata **published by the mirror**; the release binaries were not downloaded, independently hashed, extracted, disassembled or tested here. Source framework declarations from another repository must not be assumed binary-identical to v0.5.5.
- Next evidence gate: obtain the release IPA/TIPA through an authorized binary-capable path, compare downloaded SHA-256 to metadata, inspect bundled frameworks and exported symbols, then independently validate runtime permissions. Until then `channel=UNVERIFIED`, `spawn=NOT_ATTEMPTED`, `result=BLOCKED`.
