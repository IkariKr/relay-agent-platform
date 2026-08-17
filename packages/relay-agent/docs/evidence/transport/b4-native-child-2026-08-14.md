# B4 Paid Native Smoke — Verified (2026-08-14)

> 状态：**通过**（roadmap §8.3 Native-provider 验收矩阵，针对已验证组合）
> 授权：用户提供供应商（`https://nexus.ikarikore.top/v1` + api key）并显式授权付费测试
> 安全：key 仅用于会话环境变量；evidence 文件经 `grep sk-` 检查 **0 泄漏**

## 已验证组合

- host：codex-cli **0.147.0**（win32）/ pwsh 7.6.4
- provider：`custom` → `https://nexus.ikarikore.top/v1`（wire_api=`responses`，多模型代理）
- model：`deepseek-v4-flash-response`（Responses 端点，`parallel_tool_calls: true`，满足 tool-turn 合同）
- agent 注册：临时 profile `[agents.deepseek-v4-flash]`（model_provider=custom, model=deepseek-v4-flash-response, sandbox=read-only）
- pack：`workers/native-providers/deepseek-v4-flash/`（provider_id=deepseek，别名 custom）

## 事件证据（b4-native-child-20260814.jsonl + cancel 运行）

| 能力 | 事件证据 | 状态 |
|---|---|---|
| custom agent spawn | `collab_tool_call tool=spawn_agent sender=… receivers=019fff02-…`（独立子线程 id） | ✅ |
| 独立 child identity | receiver_thread_ids = 独立子线程（非主线程） | ✅ |
| plaintext assignment 到达 child | spawn prompt 携带 marker，child 精确返回 `RELAY-B4-CHILD-<ts>` | ✅ |
| 原生 wait/callback | `tool=wait … status=completed` + 父任务收到 child 输出 | ✅ |
| 原生 cancel | `tool=close_agent` 返回 `previous_status: {"completed":"4"}` | ✅ |
| follow-up transport | `tool=send_input`（父→子续跑，child 输出 1,2,3,4） | ✅ |
| 非 CLI/SDK/MCP/第二 Codex | 单 codex 进程内 collab 工具调用 | ✅ |
| secret 不外泄 | evidence 中 `sk-` 计数 0 | ✅ |

## §8.3 验收矩阵逐项

- [x] 主任务模型/provider 保持不变（未改全局配置；profile 临时分层后删除）
- [x] 独立 child task 可见（receiver_thread_ids）
- [x] child agent type 等于 worker id（`deepseek-v4-flash`，由 [agents] 注册）
- [x] child provider/model 与 manifest 一致（agent 声明 custom+deepseek-v4-flash-response，child 实际运行）
- [x] child 不是 CLI / SDK / MCP / 第二 Codex 进程
- [x] assignment 完整到达 child（marker 往返）
- [x] fork/isolation 语义（独立子线程）
- [x] 父任务通过原生 wait/callback 收到结果
- [x] 原生 cancel 可验证（close_agent）
- [x] install/doctor 默认无付费模型调用（probe 本地）
- [x] secret 不进入 repo/config diff/log/prompt/terminal transcript
- [x] read-only worker 无非预期写入（sandbox read-only + scratch 目录）
- [x] 未使用 Hook（原生 plaintext transport 首选路径达成，roadmap "若全部通过不实现 Hook"）
- [x] uninstall 只移除 pack-owned（B1 测试 + profile 已删）
- [x] capability report 与实际行为一致（本证据更新 probe 状态）

## 结论

**B4 门禁通过**：针对 codex-cli 0.147.0 + custom(nexus)/deepseek-v4-flash-response + [agents.deepseek-v4-flash] 组合，
DeepSeek worker 可称 **supported Codex native child**（roadmap §8.1 "Supported native child | B4 | 对已验证的 host/provider/model 组合可称 supported"）。

**限制声明（§9 语言规则）**：supported 仅限定于本已验证组合；其他版本/模型/宿主需各自重跑验收。
