# B4 Paid Native Smoke — Profile-suffixed Role Regression (2026-08-15)

> 状态：**通过**（roadmap §8.3 Native-provider 验收矩阵，针对已验证组合）
> 授权：用户提供供应商（`https://nexus.ikarikore.top/v1` + api key）并显式授权付费测试（2026-08-15）
> 目的：P0-4 必验项——`<worker-id>--<profile-id>` 形态 agent role 的 native child 全链路回归
> 安全：key 仅用于会话环境变量；evidence 文件经 `grep sk-` 检查 **0 泄漏**

## 与旧 B4 evidence 的关系

旧 evidence（`b4-native-child-2026-08-14.md`）验证的是 `[agents.deepseek-v4-flash]`（无 profile 后缀）。
本轮回归验证 onboarding 产品化后的 **profile-suffixed role**：`[agents.deepseek-v4-flash--b4-regress]`，
该注册由 `relay worker configure` 自动生成（Relay-owned marker + 用户级 overlay），
配置加载层证据见 `profile-suffixed-agent-role-config-load-2026-08-15.md`（`codex doctor`：config.load=ok）。

## 已验证组合

- host：codex-cli **0.147.0**（win32）/ pwsh 7.6.4
- 主 agent：`custom` provider → nexus（`https://nexus.ikarikore.top/v1`，wire_api=responses）+ `gpt-5.4`（主任务 provider/model 与 child 不同，identity 区分更强）
- child agent role：`[agents.deepseek-v4-flash--b4-regress]` → overlay（`model_provider=deepseek`, `model=deepseek-v4-flash-response`, `sandbox_mode=read-only`）
- provider：`[model_providers.deepseek]` → nexus（wire_api=responses），`env_key=RELAY_PROVIDER_B4_REGRESS_API_KEY`
- 隔离 CODEX_HOME（临时目录），全程未触碰用户全局 `~/.codex`

## 事件证据（b4-native-child-profile-suffix-2026-08-15.jsonl + cancel 运行）

| 能力 | 事件证据 | 状态 |
|---|---|---|
| custom agent spawn（profile-suffixed role） | `collab_tool_call tool=spawn_agent`，prompt 携带 marker，receiver = 独立子线程 `01a005e9-d976-…` | ✅ |
| 独立 child identity | receiver_thread_ids = 独立子线程（非主线程 `01a005e9-b65f-…`） | ✅ |
| plaintext assignment 到达 child | spawn prompt 携带 `RELAY-B4-REGRESS-<ts>`，child 精确返回同 token | ✅ |
| 原生 wait/callback | `tool=wait` ×4，父任务收到 child 输出 | ✅ |
| follow-up transport | `tool=send_input`（父→子，child 返回第二个 marker `RELAY-B4-R2-B-<ts>`） | ✅ |
| 原生 cancel | `tool=close_agent` ×2（receiver = 同一 child 线程） | ✅ |
| 非 CLI/SDK/MCP/第二 Codex | 单 codex 进程内 collab 工具调用 | ✅ |
| secret 不外泄 | 两份 jsonl 中 `sk-` 计数 0 | ✅ |

## §8.3 验收矩阵逐项

- [x] 主任务模型/provider 保持不变（主 agent gpt-5.4/custom 未变；隔离 CODEX_HOME 未碰全局）
- [x] 独立 child task 可见（receiver_thread_ids 独立子线程）
- [x] child agent type 等于 role（`deepseek-v4-flash--b4-regress`，由 Relay 注册段绑定 overlay）
- [x] child provider/model 与 manifest 一致（overlay 声明 deepseek + deepseek-v4-flash-response，child 实际运行并返回 marker）
- [x] child 不是 CLI / SDK / MCP / 第二 Codex 进程
- [x] assignment 完整到达 child（双 marker 往返）
- [x] fork/isolation 语义（独立子线程）
- [x] 父任务通过原生 wait/callback 收到结果
- [x] 原生 cancel 可验证（close_agent）
- [x] install/doctor 默认无付费模型调用（configure/doctor 零付费，paid 仅 exec）
- [x] secret 不进入 repo/config diff/log/evidence（`grep sk-` 0 泄漏）
- [x] read-only worker 无非预期写入（sandbox read-only）
- [x] 未使用 Hook（原生 plaintext transport 首选路径）
- [x] uninstall 只移除 Relay-owned（uninstall 测试 + 临时 CODEX_HOME 清理）
- [x] capability report 与实际行为一致（`docs/evidence/codex-capability/2026-08-15-codex-0.147.0-win32.json`：spawn/wait/cancel/plaintext=supported，evidence 引用本轮 jsonl）

## 结论

**P0-4 regression 通过**：codex-cli 0.147.0 + custom(nexus) + `deepseek-v4-flash-response` +
profile-suffixed role `[agents.deepseek-v4-flash--<profile>]` 组合下，DeepSeek worker
可称 **supported Codex native child**。此前的 `[agents.deepseek-v4-flash]` B4 claim 现已
由产品化 role 形态（relay worker configure 生成路径）重新验证，二者均有效。

**限制声明（§9 语言规则）**：supported 仅限定于本已验证组合（CLI 0.147.0 / win32 / nexus /
deepseek-v4-flash-response / profile-suffixed role）；**Codex Desktop 未在本轮验证**（P0-5），
其他宿主/模型/版本需各自重跑验收。
