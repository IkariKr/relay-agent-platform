# Native Provider Agent-first 配置与执行入口实施计划（2026-08-15）

> 状态：实施设计 / P0  
> 适用项目：`relay-agent-platform`  
> 上游依据：`docs/codex-native-subagent-roadmap.md`、`docs/native-subagent-next-steps-2026-08-15.md`、当前 `relay-agent` skill 生成机制与 Worker Runtime Registry 代码  
> 核心目标：用户安装 `relay-agent` skill 后，不需要理解 Codex provider TOML、worker manifest、环境变量命名或 native child 生命周期。任意能读取该 skill 的 Agent 都应知道如何发现配置状态、向用户收集最少信息、完成配置、运行 doctor，并发起 native-provider worker。

## 1. 目标用户体验

### 1.1 用户只需要提供的信息

首批 native-provider onboarding 的最小输入固定为：

1. `Base URL`
2. `Model ID`
3. `API Key`

可选信息：

- provider / profile 显示名称，例如 `my-deepseek`；
- worker id，未指定时由 Agent 根据任务和已注册 worker 选择；
- credential 环境变量名，未指定时由 Relay 根据 worker/profile 自动生成稳定名称；
- sandbox variant，首批默认 `read-only`，用户未明确要求时 Agent 不询问。

**用户不需要提供或理解：**

- `[agents.*]` TOML 语法；
- `[model_providers.*]` TOML 语法；
- `wire_api` 的内部字段名；
- worker manifest 路径；
- `CODEX_HOME` 路径；
- agent overlay 安装位置；
- capability probe 命令；
- native child 的 `spawn_agent` / `wait` / `send_input` / `close_agent` 实现细节。

### 1.2 理想自然语言流程

用户安装 skill 后，只需对 Agent 说：

```text
帮我把 DeepSeek 配成 relay 的原生 subagent。
Base URL: https://example.com/v1
Model ID: deepseek-v4-flash-response
API Key: <secret>
```

Agent 应按 skill 合同自动完成：

```text
识别 relay-agent 已安装
  ↓
发现 native-provider worker / 配置状态
  ↓
规范化 Base URL / Model ID
  ↓
安全写入 credential
  ↓
生成用户 provider profile + agent overlay
  ↓
安装/注册 worker
  ↓
运行无付费 doctor
  ↓
报告 ready / blocker
  ↓
只有用户明确要求真实验证或执行任务时才进行付费调用
```

之后用户可以直接说：

```text
把这个只读代码审查任务交给 DeepSeek。
```

Agent 应自行选择已经配置好的 worker/profile 并通过 Codex native child 执行，不再要求用户重复 Base URL、Model ID 或 API Key。

---

## 2. 设计原则

### 2.1 Agent-first，而不是 CLI-first

CLI 是稳定执行接口，但 skill 才是 Agent 的操作说明书。

实现必须保证：

- 人可以直接运行 CLI；
- Agent 可以无需猜测地调用同一 CLI；
- Agent 从 `SKILL.md` 就能知道配置前置条件、命令顺序、缺失信息和安全规则；
- 不依赖某一个特定 Agent 的隐藏能力或专有工具调用格式。

### 2.2 配置实例与 Worker Pack 分离

当前 DeepSeek pack 中：

```text
base_url = "<responses-compatible-endpoint>"
model = "<provider-model-id>"
```

说明 pack 模板与用户部署配置仍混在一起。

目标模型改为：

```text
Worker Pack（仓库定义）
├─ worker id
├─ runtime_type = native-provider
├─ wire API requirements
├─ sandbox / permission policy
├─ data boundary
├─ capability requirements
└─ provider configuration schema

Provider Profile（用户实例）
├─ profile id
├─ worker id
├─ provider id / alias
├─ base_url
├─ model_id
├─ credential_source
└─ created/updated metadata
```

一个 worker pack 可以绑定多个 provider profile。例如：

```text
deepseek-v4-flash
├─ profile: deepseek-official
├─ profile: company-gateway
└─ profile: personal-nexus
```

这样用户更换中转站、模型 ID 或 Base URL 时，不需要修改 Git 仓库中的 pack 文件。

### 2.3 Secret 与普通配置严格分离

`Base URL`、`Model ID`、profile id 可以进入用户配置文件。

API Key 不得：

- 写入 `worker.json`；
- 写入 `agent.toml` 明文；
- 写入 Relay profile JSON/TOML 明文；
- 作为 `--api-key <secret>` 出现在命令行；
- 出现在 shell history；
- 出现在 doctor 输出；
- 出现在日志、evidence、异常消息；
- 出现在 Git diff。

Relay 只保存 `credential_source`，例如：

```text
env:RELAY_PROVIDER_DEEPSEEK_OFFICIAL_API_KEY
```

首批 credential backend 以环境变量为最低公共能力；后续可增加 OS credential store / Codex credential source adapter，但不能改变上层 onboarding 合同。

---

## 3. 正式 CLI 合同

Native-provider 的正式入口收敛到：

```text
relay worker ...
```

不把 native-provider 塞进现有 `relay run --backend ...`。

### 3.1 发现与状态

```powershell
relay worker list
relay worker show <worker-id>
relay worker status <worker-id> [--profile <profile-id>]
```

`list` 至少输出：

- worker id；
- runtime type；
- purpose；
- configured profiles count；
- ready / needs-config / blocked 状态。

`show` 至少输出：

- provider contract；
- required inputs；
- default sandbox；
- data-boundary warning；
- installed profiles；
- credential source **名称**，绝不显示 secret。

### 3.2 配置入口

正式命令：

```powershell
relay worker configure <worker-id>
```

支持两种模式。

#### A. 人类交互模式

```powershell
relay worker configure deepseek-v4-flash
```

Relay 逐项询问：

```text
Profile name [deepseek-default]:
Base URL:
Model ID:
API Key: ********
```

API Key 必须使用 masked / non-echo input。

结束后自动：

1. 校验 URL 格式；
2. 校验 model id 非空；
3. 生成 profile id；
4. 选择稳定 credential env name；
5. 安全保存 credential；
6. 生成用户级 provider/agent overlay；
7. 注册/安装 worker；
8. 运行无付费 doctor；
9. 输出机器和人均可读的 ready 状态。

#### B. Agent 非交互模式

```powershell
relay worker configure deepseek-v4-flash \
  --profile personal-nexus \
  --base-url https://example.com/v1 \
  --model deepseek-v4-flash-response \
  --api-key-stdin \
  --non-interactive \
  --json
```

关键规则：

- **不存在 `--api-key <value>` 参数。**
- Agent 必须通过 stdin 或未来的 credential adapter 传递 secret；
- Relay 输出 JSON 时只返回 credential source 名称和 `present=true/false`；
- JSON 中不能出现 secret、secret hash、secret prefix；
- 如果 Agent runtime 无法安全提供 stdin，则 skill 必须改为让用户自己运行一次 masked credential 命令，而不是把 key 拼进 shell command。

建议 stdin 合同：

```text
标准输入只包含 API Key 原文，不包含 JSON wrapper，不回显。
```

实现时必须验证 subprocess / PowerShell 调用链不会把 stdin 内容打印到 transcript。

### 3.3 只修改非 secret 配置

```powershell
relay worker configure <worker-id> \
  --profile <profile-id> \
  --base-url <url> \
  --model <model-id> \
  --keep-credential
```

用于用户更换模型或 Base URL，而不重新输入 API Key。

### 3.4 Credential 专用入口

提供独立入口，避免普通配置更新必须触碰 secret：

```powershell
relay worker credential set <worker-id> --profile <profile-id>
relay worker credential status <worker-id> --profile <profile-id>
relay worker credential remove <worker-id> --profile <profile-id>
```

Agent 自动化可使用：

```powershell
relay worker credential set <worker-id> \
  --profile <profile-id> \
  --api-key-stdin \
  --non-interactive \
  --json
```

`credential status` 仅允许输出：

```json
{
  "source": "env:RELAY_PROVIDER_PERSONAL_NEXUS_API_KEY",
  "present": true
}
```

### 3.5 Doctor

```powershell
relay worker doctor <worker-id> [--profile <profile-id>] [--json]
```

默认 **零付费调用**。

至少检查：

- worker manifest 有效；
- profile 存在；
- Base URL 已设置且不是模板占位符；
- Model ID 已设置且不是模板占位符；
- credential present；
- provider/agent overlay 已安装；
- 主 Codex provider/model 未被修改；
- Codex host capability；
- native child 必需 capability evidence；
- sandbox / data boundary 状态。

统一状态：

```text
ready
needs-config
credential-missing
host-blocked
provider-misaligned
invalid-config
```

Agent 必须根据结构化状态决定下一步，不通过解析自然语言错误消息猜测。

### 3.6 执行入口

```powershell
relay worker dispatch <worker-id> \
  [--profile <profile-id>] \
  -- <task>
```

或 Agent 在 Codex 中使用原生 multi-agent surface 时，`dispatch` 可以作为决策/准备层，实际 child lifecycle 仍由 Codex 原生 `spawn_agent` 管理。

原则：

- Relay 不实现第二套 child lifecycle；
- 用户显式指定 worker/profile 时不得被自动 heuristic 替换；
- profile 未 ready 时 fail closed，并返回下一步 `configure`/`doctor` 动作；
- 不静默 fallback 到 external-cli 或另一个 provider。

---

## 4. 用户级配置布局

### 4.1 建议目录

避免修改仓库 pack，使用 Relay 自有用户状态目录，例如：

```text
CODEX_HOME/
  relay/
    native-providers/
      profiles/
        personal-nexus.json
    generated/
      agents/
        deepseek-v4-flash--personal-nexus.toml
```

具体路径可由实现阶段按 Codex discovery 规则微调，但必须满足：

- pack source 与 user instance 分离；
- Relay 能判断 ownership；
- uninstall profile 不删除其他 profile；
- uninstall worker 不破坏用户非 Relay 管理的 Codex provider；
- 所有生成文件可由 profile id 追踪来源。

### 4.2 Profile schema

新增版本化合同，例如：

```text
platform/contracts/provider-profile.schema.json
```

建议最小字段：

```json
{
  "schema_version": "1.0",
  "profile_id": "personal-nexus",
  "worker_id": "deepseek-v4-flash",
  "provider_id": "custom",
  "base_url": "https://example.com/v1",
  "model_id": "deepseek-v4-flash-response",
  "wire_api": "responses",
  "credential_source": "env:RELAY_PROVIDER_PERSONAL_NEXUS_API_KEY",
  "managed_by": "relay-agent",
  "created_at": "...",
  "updated_at": "..."
}
```

禁止 schema 出现：

```text
api_key
secret
credential_value
```

### 4.3 Worker manifest 的职责调整

`worker.json` 中的 provider block 从“具体部署值”调整为“配置合同 + 默认值”。

例如由：

```json
{
  "provider_id": "deepseek",
  "model_id": "<provider-model-id>",
  "credential_source": "env:DEEPSEEK_API_KEY"
}
```

演进为类似：

```json
{
  "provider_id": "deepseek",
  "wire_api": "responses",
  "configuration": {
    "requires": ["base_url", "model_id", "credential"],
    "default_profile_id": "deepseek-default"
  }
}
```

兼容窗口内 loader 可以继续读取旧字段，但新 profile 成为运行时具体值的 source of truth。

---

## 5. Skill 必须成为 Agent 的操作协议

这是本计划最重要的部分之一。

当前 `packages/relay-agent/SKILL.md` 由：

```text
scripts/build-packages.ps1
  + shared/docs/workflow.md
  + backends/agent/skill-backend.md
  + shared/docs/prompt-template.md
  + shared/docs/review-checklist.md
```

生成，因此 **不能直接手改 generated `packages/relay-agent/SKILL.md` 作为 source of truth**。

### 5.1 新增共享 onboarding 文档片段

建议新增：

```text
shared/docs/native-provider-onboarding.md
```

并由 `Get-GeneratedSkillMarkdown` 注入 `relay-agent` skill。

如果专用 external-cli skill 不应暴露 native-provider 配置能力，则通过 surface capability 决定是否注入，而不是四个 generated skill 全部硬编码同一段文字。

### 5.2 SKILL.md 中必须出现的 Agent 指令

至少明确：

#### 发现规则

当用户提到以下意图时：

- “用 DeepSeek/Qwen/Kimi/第三方模型做 subagent”；
- “配置 relay provider”；
- “把这个模型接进 Codex”；
- “使用 native-provider”；
- 指定 Base URL / Model ID / API Key；

Agent 应优先运行：

```text
relay worker list --json
relay worker status <worker-id> --json
```

而不是指导用户手改 TOML。

#### 缺失信息规则

如果状态为 `needs-config`，Agent 只向用户索取缺失字段：

```text
Base URL
Model ID
API Key
```

已经提供的信息不能重复询问。

#### 自动配置规则

信息齐全后，Agent 应：

1. 调用 `relay worker configure ... --non-interactive --json`；
2. 用安全 stdin 传 API Key；
3. 运行 `relay worker doctor ... --json`；
4. 若 doctor ready，告知用户配置完成；
5. 不默认运行 paid smoke。

#### 执行规则

用户要求执行任务时：

1. 读取 worker/profile readiness；
2. 校验 data boundary；
3. 如果任务可能包含 secret / personal / regulated / 未授权私有源码，先遵守现有外发策略；
4. 使用指定 native worker；
5. Codex host 下保持原生 child lifecycle；
6. review child 的公开结果。

#### Secret 规则

Agent 绝不能：

```text
relay worker configure ... --api-key sk-xxx
```

也不能把 key 写临时 `.ps1` / `.json` / `.toml` 文件来绕过 stdin。

如果 Agent 所在宿主不支持安全 stdin/credential write：

- 不降级为明文命令行；
- 指示用户运行 `relay worker credential set ...` 的 masked prompt；
- 然后 Agent 继续自动 doctor/configure 流程。

### 5.3 Skill description 更新

`relay-agent` 的 description 需要覆盖 native-provider 能力，否则其他 Agent 仅靠 skill discovery 可能不会在用户说“配置 DeepSeek subagent”时选择它。

目标语义应包含：

```text
Configure and run Codex native-provider workers plus thin external CLI workers.
Use when the user wants to connect a Responses-compatible provider/model,
configure Base URL/model/credential, or delegate to DeepSeek/other workers.
```

具体文案在实现阶段保持简短，避免 description 变成说明书。

---

## 6. Agent 可依赖的机器可读输出

所有新的 worker 命令必须支持：

```text
--json
```

这不是锦上添花，而是跨 Agent 稳定调用的核心合同。

### 6.1 Configure 成功

示例：

```json
{
  "status": "configured",
  "worker_id": "deepseek-v4-flash",
  "profile_id": "personal-nexus",
  "provider_id": "custom",
  "base_url": "https://example.com/v1",
  "model_id": "deepseek-v4-flash-response",
  "credential": {
    "source": "env:RELAY_PROVIDER_PERSONAL_NEXUS_API_KEY",
    "present": true
  },
  "next_action": "doctor"
}
```

### 6.2 缺配置

```json
{
  "status": "needs-config",
  "worker_id": "deepseek-v4-flash",
  "missing": ["base_url", "model_id", "credential"],
  "next_action": "configure"
}
```

### 6.3 Doctor Ready

```json
{
  "status": "ready",
  "worker_id": "deepseek-v4-flash",
  "profile_id": "personal-nexus",
  "paid_call_performed": false,
  "next_action": "dispatch"
}
```

### 6.4 Blocked

```json
{
  "status": "host-blocked",
  "blocking_capabilities": ["custom_agent_spawn"],
  "paid_call_performed": false,
  "next_action": null
}
```

字段要版本化并写测试，Agent 不应依赖人类文案中的关键词。

---

## 7. Provider ID 与 Base URL 的处理

### 7.1 不要求用户理解 provider id

用户输入：

```text
Base URL + Model ID + API Key
```

就应足够。

如果 worker pack 已声明 provider identity，则默认使用 pack provider id。

如果用户使用中转站/聚合网关，可生成稳定 profile provider alias，例如：

```text
relay-personal-nexus
```

内部生成 Codex `[model_providers.*]` 段时使用该 alias，避免碰撞用户已有 `custom` provider。

### 7.2 Provider section ownership

Relay 生成的 provider section 必须具备可追踪 ownership。

如果 Codex 的配置机制要求写主 `config.toml` 才能注册 `[model_providers.*]` 或 `[agents.*]`，实现必须使用结构化 patch + ownership marker / index，不能整文件覆盖。

如目标 Codex build 支持独立 include/profile 文件，应优先使用独立文件，降低对主配置的侵入。

现有“主配置 byte-identical”测试如果与真实 Codex discovery 要求冲突，需要升级为更准确的承诺：

> 不修改主 Agent 的全局 `model` / `model_provider`，只增删 Relay 明确拥有的 provider/agent 注册段。

该变化必须先由新的 runtime evidence 证明必要性并补 ownership tests。

---

## 8. 安装后 Agent 自发现

### 8.1 安装完成后的第一条能力

`relay-agent` skill 安装成功后，Agent 应能运行：

```powershell
relay worker list --json
```

因此 generated package 必须包含 native-provider 所需的：

- registry modules；
- contracts；
- worker manifests/templates；
- host adapter / doctor；
- worker CLI command implementation。

当前 `build-packages.ps1` 主要同步 external-cli runtime/registry 数据，实施时必须审计 package 是否真正自包含这些 native-provider 文件。

### 8.2 不要求用户再次安装第二个 skill

首批目标是：

> 安装 `relay-agent` 一个 skill，即获得 external-cli + native-provider 的统一 Agent 入口。

DeepSeek worker 可以作为该 skill 中的内置 worker pack，也可以未来由扩展包提供，但用户的 onboarding 命令和 Agent 协议保持一致。

### 8.3 Agent 可解释错误

配置失败时 JSON 必须给出稳定 error code，例如：

```text
WORKER_NOT_FOUND
PROFILE_NOT_FOUND
BASE_URL_INVALID
MODEL_ID_MISSING
CREDENTIAL_MISSING
CREDENTIAL_WRITE_UNSUPPORTED
PROVIDER_PROFILE_CONFLICT
HOST_CAPABILITY_BLOCKED
GENERATED_CONFIG_CONFLICT
```

skill 中定义 Agent 的恢复动作，避免 Agent 自己发明修复方法。

---

## 9. 付费调用边界

`configure`、`credential set/status`、`install`、`status`、`doctor` 默认都不得调用第三方模型。

真实调用只发生在：

```text
relay worker dispatch ...
```

或：

```text
relay worker smoke ... --paid
```

其中 paid smoke 必须保留显式授权语义。

Agent 不得把“配置完成”自动升级成“帮你试一下”，除非用户已经明确要求测试/执行。

---

## 10. 建议实现模块

避免把所有逻辑堆进 `scripts/relay.ps1`。

建议新增或扩展：

```text
platform/contracts/
  provider-profile.schema.json

platform/registry/
  WorkerProfileStore.psm1
  WorkerPackManager.psm1
  WorkerDispatch.psm1

platform/credentials/
  CredentialStore.psm1
  EnvCredentialStore.psm1

platform/generation/
  CodexProviderConfigGenerator.psm1

platform/hosts/codex/
  Doctor.psm1
  CodexHostAdapter.psm1

shared/docs/
  native-provider-onboarding.md

scripts/
  relay.ps1
```

职责边界：

- `WorkerProfileStore`：profile CRUD / schema / ownership；
- `CredentialStore`：secret 存取抽象，不知道 worker dispatch；
- `CodexProviderConfigGenerator`：把 pack + profile 生成 Codex 可发现配置；
- `WorkerPackManager`：install/uninstall 与 ownership；
- `Doctor`：组合 profile/credential/host/capability 检查；
- `relay.ps1`：仅参数解析、调用模块、格式化输出；
- `SKILL.md`：Agent 调用协议，不复制业务实现。

---

## 11. 测试矩阵新增项

### 11.1 Profile

- [ ] NP-PROFILE-001：Base URL / Model ID 可形成有效 profile；
- [ ] NP-PROFILE-002：profile 不含 API Key；
- [ ] NP-PROFILE-003：同 worker 可存在多个 profile；
- [ ] NP-PROFILE-004：profile id 冲突 fail closed；
- [ ] NP-PROFILE-005：删除一个 profile 不影响其他 profile。

### 11.2 Credential

- [ ] NP-CRED-001：masked interactive input 不回显；
- [ ] NP-CRED-002：`--api-key-stdin` 可非交互设置；
- [ ] NP-CRED-003：不存在 `--api-key <value>` 参数；
- [ ] NP-CRED-004：stdout/stderr/JSON 不含 secret；
- [ ] NP-CRED-005：doctor 只报告 presence；
- [ ] NP-CRED-006：credential remove 只删除该 profile 拥有的 secret；
- [ ] NP-CRED-007：失败异常不包含输入 secret。

### 11.3 Generation / ownership

- [ ] NP-GEN-001：pack + profile 可生成合法 Codex agent/provider overlay；
- [ ] NP-GEN-002：生成配置使用 profile 的 Base URL / Model ID；
- [ ] NP-GEN-003：API Key 只以 credential source 引用出现；
- [ ] NP-GEN-004：不改变主 Agent 全局 model/provider；
- [ ] NP-GEN-005：遇到非 Relay-owned 同名配置时停止；
- [ ] NP-GEN-006：uninstall 只清理 Relay-owned state。

### 11.4 CLI / Agent contract

- [ ] NP-CLI-001：`worker list/status/configure/doctor/dispatch` 支持 `--json`；
- [ ] NP-CLI-002：缺失字段返回稳定 machine status + missing list；
- [ ] NP-CLI-003：non-interactive 不偷偷 prompt；
- [ ] NP-CLI-004：未 ready 的 dispatch fail closed；
- [ ] NP-SKILL-001：generated `relay-agent/SKILL.md` 包含 native-provider discovery/config/execute 流程；
- [ ] NP-SKILL-002：skill 明确禁止 command-line API key；
- [ ] NP-SKILL-003：skill 描述能被“配置第三方 native subagent”意图发现；
- [ ] NP-PKG-001：干净环境只安装 `relay-agent` package 后即可运行 `worker list/configure/doctor`。

### 11.5 Runtime

- [ ] NP-RUN-001：使用配置 profile 后 child 实际 provider/model 与 profile 一致；
- [ ] NP-RUN-002：更换 profile 后不需要改 pack；
- [ ] NP-RUN-003：两个 profile 可分别通过 identity marker smoke；
- [ ] NP-RUN-004：配置/doctor 无付费调用；
- [ ] NP-RUN-005：paid smoke 仍需显式授权。

---

## 12. 分阶段实施顺序

### P0-A：Profile 与 credential contract

1. 新增 `provider-profile.schema.json`；
2. 实现 `WorkerProfileStore`；
3. 定义 credential store 接口；
4. 实现 env credential backend；
5. 实现 stdin / masked secret input；
6. 完成 secret leakage tests。

**Exit gate：** 可以安全保存 `Base URL + Model ID + credential reference`，任何持久化文件与输出都不含 secret。

### P0-B：Codex 配置生成与 ownership

1. pack 模板参数化；
2. profile → provider/agent overlay generator；
3. conflict detection；
4. install/update/uninstall ownership；
5. 不改变主 Agent global provider/model；
6. profile update 可重生成配置。

**Exit gate：** 用户不手改 TOML 即可得到 Codex 可发现的 worker 配置。

### P0-C：`relay worker` CLI

实现：

```text
list
show
status
configure
credential set/status/remove
doctor
dispatch
uninstall
```

全部关键命令支持 `--json`。

**Exit gate：** 一个不了解仓库内部结构的人只靠 CLI help 就能完成配置。

### P0-D：Skill Agent protocol

1. 新增 `shared/docs/native-provider-onboarding.md`；
2. 修改 package generation，把 onboarding 注入 `relay-agent/SKILL.md`；
3. 更新 `relay-agent` surface description/default prompt；
4. 定义缺失字段恢复规则；
5. 定义 secret 安全降级规则；
6. clean package install 验证 Agent 可自发现。

**Exit gate：** 给一个没有项目上下文的 Agent 安装 `relay-agent` 后，只告诉它 Base URL / Model ID / API Key，它能从 skill 自己推导并完成正确配置流程。

### P0-E：端到端 Agent onboarding 验收

至少执行两类场景：

#### 场景 1：全新用户

```text
安装 relay-agent
→ 用户给 Base URL / Model ID / API Key
→ Agent 自动 configure
→ doctor ready
→ 用户要求任务
→ native child 成功
```

#### 场景 2：已有 profile，只换模型

```text
用户：把模型改成 xxx
→ Agent status
→ configure --model xxx --keep-credential
→ doctor
→ 后续任务使用新 model
```

**Exit gate：** 用户无需接触 TOML、manifest、环境变量名和仓库路径。

---

## 13. 对现有下一阶段计划的优先级调整

该工作应提升为 `docs/native-subagent-next-steps-2026-08-15.md` 中的 P0 项，并放在“正式 native-provider 用户入口”内部的最前面。

建议顺序调整为：

```text
P0-1  Agent-first provider onboarding/profile/credential
P0-2  native-provider 正式 worker CLI + JSON contract
P0-3  测试运行环境锁定
P0-4  Codex CLI 当前版本重新验证
P0-5  Codex Desktop 独立 B4
P1    第二真实 provider / capability 语义 / docs release 收口
```

理由：Desktop 和第二 provider 即使继续验证，如果普通用户仍必须手改 Base URL、Model ID、TOML 和环境变量，平台仍然不能称为“安装 skill 后可被 Agent 自助使用”。

---

## 14. Definition of Done

只有以下全部成立，才认为“用户只提供信息，Agent 自动配置和执行”真正落地：

- [ ] 用户只需提供 Base URL、Model ID、API Key；
- [ ] 用户不需要知道 provider TOML / agent TOML 语法；
- [ ] 用户不需要自己选择 credential 环境变量名；
- [ ] API Key 不进入命令行参数、配置文件、日志或 JSON 输出；
- [ ] 同一个 worker 支持多个独立 provider profile；
- [ ] profile 是具体 Base URL / Model ID 的 source of truth，pack 不再要求用户修改模板；
- [ ] `relay worker configure` 同时支持 masked human flow 和 safe Agent non-interactive flow；
- [ ] `relay worker status/doctor/configure` 有稳定 JSON contract；
- [ ] `relay-agent/SKILL.md` 明确告诉任意 Agent 如何发现、配置、doctor、执行和恢复错误；
- [ ] skill 安装包自包含 native-provider 所需 runtime/contracts/worker pack；
- [ ] Agent 在信息已提供时不重复询问；
- [ ] Agent 遇到无法安全传 secret 的宿主时 fail safe，让用户执行 masked credential step，而不是泄漏 key；
- [ ] configure / doctor 默认零付费调用；
- [ ] paid smoke / dispatch 的计费和数据外发边界仍按现有安全策略处理；
- [ ] Codex native child lifecycle 仍由 Codex 原生能力负责，Relay 不长出第二套 orchestration runtime；
- [ ] clean install 的真实 Agent onboarding E2E 通过。

## 15. 最终目标体验

用户侧最终应该只剩两类自然语言：

```text
第一次：
“帮我配置 DeepSeek。Base URL 是 X，模型是 Y，API Key 是 Z。”
```

和：

```text
以后：
“把这个任务交给 DeepSeek。”
```

中间所有配置发现、profile 生成、credential source、Codex agent/provider overlay、doctor、worker selection 和 native lifecycle 边界，都由 Relay 的稳定合同 + 安装后的 skill 指令让 Agent 自动处理。

这才是本入口的完成标准：**不是让用户学会配置 Relay，而是让安装了 Relay 的 Agent 学会替用户配置 Relay。**
