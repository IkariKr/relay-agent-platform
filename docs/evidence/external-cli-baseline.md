# External-CLI 基线记录（SOP Phase 0）

> 记录日期：2026-08-14  
> 用途：SOP Phase 0 "冻结复杂度并建立基线" 的证据落盘。本文件只记录确定性可复现事实；付费模型 smoke 属于 release 期 best-effort（TR-INTEG-001），不在本基线内。

## 1. 环境

| 项 | 值 |
|---|---|
| PowerShell | pwsh 7.6.4 |
| Pester | 6.1.0（计划文档写 Pester v5 + Invoke-Pester；本机 PSGallery 当前为 v6，`Invoke-Pester` API 兼容，故以 v6 落地，偏差已记录） |
| 平台 | win32 / Windows 10 |

## 2. 后端 CLI 可用性（Phase 0 item 1）

| backend | 可执行 | 版本 |
|---|---|---|
| claude | 是（`C:\Users\ckr2577\.local\bin\claude`） | 2.1.201 (Claude Code) |
| opencode | 是（`C:\Users\ckr2577\AppData\Roaming\npm\opencode`） | 1.18.6 |
| antigravity | 是（`C:\Users\ckr2577\AppData\Local\agy\bin\agy`） | 1.1.10 |
| codex（宿主） | 是 | codex-cli 0.142.5 |

## 3. 确定性契约基线（Phase 0 item 3-7）

- 测试运行器：Pester + `Invoke-Pester`，入口 `tests/ThinRelay.Contract.Tests.ps1` 与 `tests/ThinRelay.Process.Tests.ps1`。
- stub CLI fixture：`tests/fixtures/stub-cli/`（`opencode.cmd` / `claude.cmd` / `agy.cmd` → `stub-cli.ps1`，`STUB_*` 环境变量控制）。
- 覆盖：命令构造（TR-CMD-*）、passthrough 顺序与同名 token（TR-CMD-002）、配置默认值/显式优先（TR-CFG-001）、dry-run 不解析 CLI（TR-DRY-001）、token-aware 脱敏（TR-SEC-001）、stdout/stderr 分流（TR-PROC-001）、退出码（TR-PROC-002）、CLI missing（TR-PROC-003）、`--log-dir` 实时 mirror（TR-LOG-001）、单次调用（TR-ONCE-001）、非 Git 目录（TR-GIT-001）、命令清单脱敏（TR-SEC-002）。

## 4. 已知缺口与后续

- 付费/联网模型 smoke（真实 Claude/OpenCode/Antigravity 调用）未在本基线执行，属 release 期 best-effort（SOP §9.3 / TR-INTEG-001）。
- 本机 2026-08-14 三个后端 CLI 全部可用，可直接执行后续 best-effort smoke。
- Pester 版本为 6.1.0（非计划的 5.x）：`Invoke-Pester` 语法兼容，无计划行为差异；如需严格锁定 5.x，在 CI 中改用 `-RequiredVersion`。
