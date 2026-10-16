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
