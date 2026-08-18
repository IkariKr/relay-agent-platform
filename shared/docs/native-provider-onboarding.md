# Native Provider Onboarding — Agent 操作协议

> 本片段由 `scripts/build-packages.ps1` 注入 `relay-agent/SKILL.md`（onboarding plan §5）。
> 安装 `relay-agent` skill 后，Agent 应能仅凭本协议完成第三方 Responses-compatible
> provider 的发现、配置、doctor 与执行，用户只需提供 Base URL / Model ID / API Key。
> This fragment is injected into `relay-agent/SKILL.md` by the build script. An Agent
> with this skill installed can discover, configure, doctor and dispatch native-provider
> workers from only Base URL / Model ID / API Key.

## Native Provider Workers（与 external-cli 并列的第二种 runtime）

Relay 的 `worker` 命令面管理 **native-provider** worker（以 Codex native child 运行的
第三方 provider/model，例如 DeepSeek）与 **external-cli** worker（Claude / OpenCode /
Antigravity）。`relay worker ...` 是 native-provider 的唯一正式入口；不要指导用户手改
Codex TOML、worker manifest 或环境变量名。

用户只需要提供三样东西：

1. `Base URL`（Responses-compatible endpoint）
2. `Model ID`
3. `API Key`（secret）

其他一切（profile、credential source 名、Codex agent/provider overlay、doctor）由
Relay 自动完成。API Key **绝不**出现在命令行参数、日志、JSON 输出或 Git diff。

## 发现规则

当用户意图匹配以下任一情况时，先运行（不要直接改 TOML）：

```text
relay worker list --json
relay worker status <worker-id> --json
```

- “把 DeepSeek / Qwen / Kimi / 其他第三方模型配成 subagent”；
- “配置 relay provider / native-provider”；
- “把这个模型接进 Codex”；
- 用户直接给出 Base URL / Model ID / API Key。

`list` 会显示每个 worker 的 runtime type 与状态（needs-config / credential-missing /
host-blocked / ready）。

## 缺失信息规则

`status` 返回 `needs-config` / `credential-missing` 时，**只向用户索取缺失字段**
（Base URL、Model ID、API Key 中的哪些 `missing` 列表给出）。用户已提供的信息不得
重复询问。用户没有主动要求时，不询问 sandbox variant（默认 read-only）等内部字段。

## 自动配置规则（Agent 非交互模式）

信息齐全后：

1. 调用 `relay worker configure <worker-id> --profile <profile-id> --base-url <url> --model <model-id> --api-key-stdin --non-interactive --json`；
2. 通过 **stdin** 传 API Key（stdin 内容只有 API Key 一行，不带 JSON wrapper）；
3. 运行 `relay worker doctor <worker-id> --profile <profile-id> --json`；
4. 若 doctor 返回 `ready`，告知用户配置完成；
5. **不默认运行 paid smoke**——configure/doctor 都是零付费调用。

示例（用户已给全信息）：

```text
relay worker configure deepseek-v4-flash --profile personal-nexus \
  --base-url https://nexus.example.com/v1 --model deepseek-v4-flash-response \
  --api-key-stdin --non-interactive --json
```

之后用户再说“把这个只读审查任务交给 DeepSeek”时，直接复用已配置的 profile，不再要
Base URL / Model ID / API Key：

```text
relay worker dispatch deepseek-v4-flash --profile personal-nexus -- <task>
```

## Secret 规则（不可妥协）

- **不存在 `--api-key <value>` 参数**。绝不要拼 `--api-key sk-xxx`；
- 绝不要把 key 写进临时 `.ps1` / `.json` / `.toml` 文件来绕过 stdin；
- 如果当前宿主无法安全提供 stdin：**不降级为明文命令行**；让用户自己运行一次
  masked 交互命令，Agent 再继续 doctor/configure：
  ```text
  relay worker credential set <worker-id> --profile <profile-id>
  ```
- `credential status` 只返回 `{"source": "env:...", "present": true/false}`；
- 任何命令的输出、错误消息、evidence 中出现 key 都视为泄漏缺陷。

## 执行规则

1. 用户点名已配置的 provider/model（例如 Gemini、DeepSeek）时，必须将它解析为对应
   native worker/profile；不得调用 `relay route`、`relay run`，也不得降级到 Antigravity、
   Claude 或 OpenCode CLI。
2. 用户未点名模型时，先查看已配置 profile 的公开 `purpose` 与就绪状态；若只有一个
   合格 native profile，或任务文字能唯一匹配 provider/model，可用：
   ```text
   relay worker dispatch --auto -- <task>
   ```
   自动选择仅在返回 `dispatch-ready` 时成立。若返回
   `NATIVE_WORKER_SELECTION_REQUIRED`，Agent 可依据公开 purpose 做唯一的任务适配选择；
   仍并列时才向用户询问，**绝不**回退到 external-cli。
3. 对已选中的 worker，先 `relay worker status <worker-id> --profile <profile-id> --json`；
4. 仅当 `status == ready` 才 `relay worker dispatch`；
5. dispatch 前校验 data boundary（默认 read-only + external-transmit）；
6. 任务可能含 secret / personal / regulated / 未授权私有源码时，遵守现有外发策略，
   先向用户确认再外发；
7. `dispatch` 返回 `agent_role` 后，必须使用 Codex 原生 `spawn_agent` 创建 child，再
   `wait_agent` 等待结果并 `close_agent` 释放；Relay 不实现第二套 child lifecycle；
8. 只审查 child 的公开 tool events / 输出 / 最终结果。

## 错误码与恢复动作

| error_code | 含义 | Agent 恢复动作 |
|---|---|---|
| WORKER_NOT_FOUND | worker id 不存在 | 运行 `relay worker list --json` 选正确 id |
| PROFILE_NOT_FOUND | profile 不存在 | 运行 configure 创建 profile |
| PROFILE_SELECTION_REQUIRED | 同一 worker 有多个 profile，未明确选择 | 读取返回的 `profile_ids`，选择目标 profile，并在后续 `status / doctor / dispatch` 中显式传 `--profile <profile-id>` |
| NATIVE_WORKER_SELECTION_REQUIRED | 有多个 ready native profile，但任务未唯一匹配 provider/model | 依据公开 purpose 选择唯一适配者；仍并列才向用户询问，绝不回退到 external-cli |
| NO_READY_NATIVE_PROVIDER | 没有已配置且 ready 的 native profile | 运行 `relay worker list --json`，只配置缺失的字段或修复 doctor 的阻断项 |
| INCOMPLETE_CONFIG / OVERLAY_MISSING | 配置不完整 | 按 missing 列表向用户索取字段后重跑 configure |
| AGENT_REGISTRATION_MISSING | Relay overlay 存在，但 Codex `[agents.*]` 注册缺失 | 对同一 worker/profile 重跑 `configure` 让 Relay 重建 owned 注册；不要指导用户手改 TOML |
| CREDENTIAL_MISSING | 缺 API Key | 让用户运行 masked `credential set` 或经 stdin 提供 |
| HOST_CAPABILITY_BLOCKED | 宿主能力未验证 | 不猜测；报告 blocking 列表，等 B4 evidence 或换宿主 |
| PROVIDER_PROFILE_CONFLICT / GENERATED_CONFIG_CONFLICT | 配置冲突 | 停止并展示冲突信息，不覆盖非 Relay 文件 |
| CREDENTIAL_WRITE_UNSUPPORTED | 无法写 credential | 让用户手动执行 masked 命令 |

## 付费调用边界

`list / show / status / configure / credential set|status|remove / doctor` 一律零付费。
真实调用只发生在显式 `relay worker dispatch ...` 或显式授权的 paid smoke。Agent 不得
把“配置完成”自动升级成“帮你试一下”。

## 只改 Relay 拥有的东西

- profile 与生成的 overlay 都在 Relay 自有目录（`<CODEX_HOME>/relay/...`）；
- 为让 Codex 真正发现 native worker，Relay 只在主 `config.toml` 中增删带 ownership marker 的 `[agents.*]` 注册段；
- 绝不修改主 Codex 的全局 `model` / `model_provider`；
- 非 Relay-owned 的同名 `[agents.*]` 一律 fail closed，不覆盖；
- 卸载只清理 Relay-owned 状态：
  ```text
  relay worker uninstall <worker-id> --profile <profile-id>
  ```
- 用户更换 Base URL / Model ID 时用 `configure` 重跑（credential 保留），不需要
  卸载重装。
