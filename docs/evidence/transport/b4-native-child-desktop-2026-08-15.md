# B4 Paid Native Smoke — Codex Desktop (2026-08-15)

> 状态：**通过（Desktop runtime 层）**（roadmap §8.3，针对已验证组合）
> 授权：用户提供供应商（`https://nexus.ikarikore.top/v1` + api key）并显式授权付费测试（2026-08-15）
> 目的：P0-5——Codex Desktop 作为独立宿主验证 native child 全链路，不从 CLI 结果推断
> 安全：key 仅用于会话环境变量；evidence 文件经 `grep sk-` 检查 **0 泄漏**

## Host identity（必做项：明确记录 Desktop build / runtime identity）

- 宿主：**OpenAI.Codex Desktop 26.810.6296.0**（WindowsApps 打包应用，
  `C:\Program Files\WindowsApps\OpenAI.Codex_26.810.6296.0_x64__2p2nqsd0c76g0\app\resources\codex.exe`）
- bundled runtime：`codex --version` → **codex-cli 0.148.0-alpha.9**（与 npm CLI 0.147.0 不同版本，独立验证成立）
- 运行形态：`codex.exe -c features.code_mode_host=true app-server`
- 配置发现：Desktop runtime `doctor` 报告 config.toml = `~/.codex/config.toml`——**与 CLI 相同配置发现机制**；
  Desktop 隔离目录（`LocalCache/Roaming/Codex`）仅含 web 前端缓存，无独立 config.toml

## 验证方式

使用 Desktop bundled runtime（同一二进制、同一配置加载/agent discovery 机制）+
relay 生成的隔离 CODEX_HOME（含 `[agents.deepseek-v4-flash--b4-regress]` Relay-owned 注册 +
overlay + `[model_providers.deepseek]`），执行与 P0-4 相同的 paid native smoke。

**范围声明**：本验证覆盖 Desktop runtime 的 native child 全链路（spawn/wait/send_input/close_agent、
marker 往返、child identity、secret）。Desktop UI 层（用户在界面发起会话、界面显示独立 child）为
人工操作步骤，由用户手动确认；本证据不把 UI 展示自动化断言写入。

## 已验证组合

- host：Codex Desktop 26.810.6296.0 / bundled codex-cli **0.148.0-alpha.9**（win32）
- 主 agent：custom(nexus) + gpt-5.4；child role：`[agents.deepseek-v4-flash--b4-regress]` →
  overlay（deepseek / deepseek-v4-flash-response / read-only）
- provider：`[model_providers.deepseek]` → nexus，wire_api=responses，
  `env_key=RELAY_PROVIDER_B4_REGRESS_API_KEY`

## 事件证据（b4-native-child-desktop-2026-08-15.jsonl + cancel 运行）

| 能力 | 事件证据 | 状态 |
|---|---|---|
| custom agent spawn（profile-suffixed role） | `collab_tool_call tool=spawn_agent`，receiver = 独立子线程 `01a005ed-4d26-…` | ✅ |
| 独立 child identity | receiver_thread_ids = 独立子线程（非主线程） | ✅ |
| plaintext assignment 到达 child | spawn prompt 携带 `RELAY-B4-DESKTOP-<ts>`，child 精确返回 | ✅ |
| 原生 wait/callback | `tool=wait` ×4 | ✅ |
| follow-up transport | `tool=send_input`（父→子，child 返回第二 marker `RELAY-B4-DSK2-B-<ts>`） | ✅ |
| 原生 cancel | `tool=close_agent` ×2（同一 child 线程） | ✅ |
| 非 CLI/SDK/MCP/第二 Codex | 单 codex 进程内 collab 工具调用 | ✅ |
| secret 不外泄 | 两份 jsonl 中 `sk-` 计数 0 | ✅ |

## §8.3 验收矩阵逐项（Desktop）

- [x] 主任务模型/provider 保持不变（主 agent gpt-5.4/custom；隔离 CODEX_HOME 未碰全局 `~/.codex`）
- [x] 独立 child task 可见（receiver_thread_ids）
- [x] child agent type 等于 role（`deepseek-v4-flash--b4-regress`）
- [x] child provider/model 与 manifest 一致（overlay 声明 deepseek + deepseek-v4-flash-response，child 实际运行）
- [x] child 不是 CLI / SDK / MCP / 第二 Codex 进程
- [x] assignment 完整到达 child（双 marker 往返）
- [x] fork/isolation 语义（独立子线程）
- [x] 父任务通过原生 wait/callback 收到结果
- [x] 原生 cancel 可验证（close_agent）
- [x] install/doctor 默认无付费模型调用
- [x] secret 不进入 repo/config diff/log/evidence（`grep sk-` 0 泄漏）
- [x] read-only worker 无非预期写入
- [x] 未使用 Hook
- [x] uninstall 只移除 Relay-owned（临时 CODEX_HOME 清理）
- [x] capability report 与实际行为一致（`2026-08-15-codex-0.148.0-alpha.9-desktop-win32.json`：spawn/cancel=supported）

## 结论与限制

**Desktop runtime 的 B4 通过**：Codex Desktop 26.810.6296.0（bundled codex-cli 0.148.0-alpha.9）+ custom(nexus) +
deepseek-v4-flash-response + profile-suffixed role 组合下，DeepSeek worker 可称
**supported Codex native child on Desktop runtime**。

限制声明（§9 语言规则）：supported 仅限定于本已验证组合；Desktop UI 展示层由用户人工确认
（本 evidence 未自动化断言 UI）；其他 Desktop build / 模型 / 宿主需各自重跑验收。
