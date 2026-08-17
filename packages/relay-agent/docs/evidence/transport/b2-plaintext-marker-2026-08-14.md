# B2 Partial Evidence — Plaintext Marker Round-Trip (2026-08-14)

> 状态：**部分证据达成**（roadmap §7 Phase B2 项 1/2/4/5 的 transport 部分）
> 授权：用户提供供应商（base_url `https://nexus.ikarikore.top/v1` + api key）并显式授权付费测试
> 安全：key 仅用于会话环境变量，未写入任何仓库文件；本文件不含任何 secret

## 1. 供应商能力发现（授权诊断调用）

- `GET /v1/models`：多模型代理，包含 `deepseek-v4-flash-response`（owned_by openai）、`deepseek-v4-pro` 等
- `POST /v1/responses`（model=`deepseek-v4-flash-response`）：**成功**，返回 `status: completed`，
  `parallel_tool_calls: true`、`tools: []`、含 reasoning + message output —— 端点满足 Codex Responses/tool-turn 合同
- `deepseek-chat` 等猜测 id 返回 `model_not_found`（正常，模型 id 以代理实际列表为准）

## 2. 直接 API marker 往返（最小付费调用）

- prompt: `Output exactly this token and nothing else: RELAY-B2-<ts>`
- 响应 output_text: **精确返回 marker**；usage: 100 in / 32 out tokens

## 3. codex exec marker 往返（B2 transport 部分证据）

- 命令：`codex exec -c 'model_providers.custom.base_url=...' -c 'model_providers.custom.env_key=DEEPSEEK_API_KEY' -c 'model_providers.custom.wire_api="responses"' -m deepseek-v4-flash-response --skip-git-repo-check --json --ephemeral -o lastmsg.txt -- "<marker prompt>"`
- JSONL 事件：`turn.started → item.completed(agent_message: RELAY-B2-CODEX-<ts>) → turn.completed`
- `lastmsg.txt` = marker 精确值；退出码 0
- 现有 `[model_providers.custom]` 即 nexus 端点（wire_api=responses，顶层 model_provider=custom）

## 4. 证明 / 未证明

**证明（B2 项 2/4/5 的 transport 部分）**：
- custom provider（Responses）经 codex 加载并调用 ✓
- plaintext initial message 到达第三方模型 ✓
- marker 完整到达并返回（wait/callback：turn.completed + last message）✓

**未证明（B4 门禁剩余项）**：
- 独立 native-child identity（UI/tool event 独立 worker id）——本次为主 Agent 调用，非 spawn 的子任务
- fork/isolation 语义（fork_turns）
- child 级 provider/model 与 manifest 一致
- 需 `[agents]` 注册 + multi-agent 运行时行为；0.147.0 无 CLI spawn 开关，agent schema 待验证
