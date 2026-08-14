# CodeX Native Subagent 优先路线图

> 状态：实施路线图 / CodeX first  
> 第一目标：把 DeepSeek 等第三方 Responses-compatible provider/model 作为 **真正的 Codex native child** 接入，而不是通过 CLI、SDK、MCP 或另一个 Codex 进程模拟 subagent。  
> 与 [Thin Relay v2 SOP](thin-relay-v2-sop.md) 的关系：本路线图扩展 worker runtime；不恢复 Relay v1 的超时、自动重试、Git 轮询、JSONL 摘要或伪进度职责。  
> 参考实现：[Utopia-V/codex-deepseek-subagent](https://github.com/Utopia-V/codex-deepseek-subagent)。参考项目用于验证可行路径；Relay 必须把其 DeepSeek 专用实现抽象成可复用平台合同，而不是复制成新的特判。

> [!NOTE]
> 本文默认使用 **Codex** 指 OpenAI Codex 产品/runtime，包括主代理、CLI、原生 multi-agent 与 native child 生命周期；**CodeX** 仅在特指当前承载这些能力的宿主/UI 或 host adapter 时使用。标题保留 CodeX-first，是为了强调首批交付宿主。

## TL;DR

首批交付按一条纵切推进：先让 Thin Relay external-cli 达到既有 SOP 门槛，再建立 Worker Runtime Registry 和 Codex capability probe，随后把 DeepSeek 作为独立 `native-provider` agent pack 接入。只有真实 native spawn、独立 provider/model、原生 wait/callback/cancel 和显式 paid smoke 全部通过，README 才能称其为 supported native child。若原生 plaintext transport 不可用，才启用可拔除的 Hook handoff；若 Hook 也不可行，则停在 capability evidence，不用 CLI/SDK/MCP 伪装 native child。

## 1. 不可退让的目标

Relay 的长期抽象是 **Worker Runtime Registry**。它接入的是可委派的 worker runtime，而不是“某个 CLI 列表”。

在 CodeX / Codex 中，优先把 Codex 能通过自定义 provider 调用的第三方模型注册为真正的 native child：

```text
CodeX 主 Agent
├─ native-provider worker
│  └─ Codex native child task
│     ├─ 独立 agent identity
│     ├─ 独立 provider/model
│     ├─ Codex 原生 wait / cancel / callback
│     └─ Codex 原生工具与 sandbox 边界
│
└─ external-cli worker
   └─ Thin Relay → Claude / OpenCode / Antigravity CLI
```

首批目标是 DeepSeek Responses-compatible worker，例如 DeepSeek V4 Flash 或当时可用的等价模型。后续同一合同应可扩展到其他 Responses-compatible provider，而不修改主 Agent 的 OpenAI provider、ChatGPT 登录状态或全局默认模型。

以下条件同时满足，Relay 才可以把某 worker 称为 **Codex native child**：

1. child 由 Codex 的原生 multi-agent / spawn 机制创建；
2. child identity 在 Codex UI / tool event 中是独立注册的 worker id；
3. child 实际使用声明的第三方 provider/model；
4. child 生命周期由 Codex 管理，包括 wait、cancel 和 callback；
5. 不通过外部 CLI、HTTP SDK、MCP、另一个 Codex 进程或输出解析冒充 native child。

## 2. 架构决策：Worker Runtime Registry 包含 CLI Backend Registry

当前仓库的 `Backend Registry` 是 CLI-centric 合同：backend manifest 需要 `command`、`runner_script`，availability 通过 PATH 上的命令判断。这个合同适合 Claude/OpenCode/Antigravity，但不适合 native provider。

因此 **不要把 native-provider 硬塞进现有 backend.json**。目标结构是：

```text
Worker Runtime Registry
├─ native-provider
│  ├─ provider/agent pack
│  ├─ host capability requirements
│  ├─ transport contract
│  ├─ data boundary
│  └─ install / doctor / smoke / uninstall
│
└─ external-cli
   └─ existing Backend Registry
      ├─ claude
      ├─ opencode
      └─ antigravity
```

### 2.1 Worker manifest 公共合同

所有 worker 至少声明：

- `id`
- `display_name`
- `runtime_type`: `native-provider` 或 `external-cli`
- `purpose`
- `host_requirements`
- `data_boundary`
- `permissions`
- `install_contract`
- `health_check`
- `smoke_test`
- `uninstall_contract`

### 2.2 native-provider 专属字段

至少声明：

- `agent_config`
- `provider_id`
- `model_id`
- `wire_api`
- `credential_source`
- `default_sandbox`
- `transport_preferences`
- `required_host_capabilities`

### 2.3 external-cli 专属字段与兼容策略

继续复用现有 backend manifest：

- `command`
- `runner_script`
- `default_surface`
- CLI capabilities

**Schema 决策：不把 Worker 公共字段强塞进 `backend.json` v2。** 现有 `backend.json` 保持 CLI backend 的 source of truth；Worker Runtime Registry 通过 `ExternalCliWorkerAdapter` 将其规范化为统一的 `WorkerDescriptor`。这样旧 package、现有 build/validation 和 routing config 不需要一次性 schema 迁移，也不会让 native-provider 背上假 `command` / `runner_script`。

规范化规则至少包括：

- `id` / `display_name`：直接映射 backend manifest；
- `runtime_type = external-cli`：由 adapter 固定注入；
- `host_requirements`：由 CLI/PATH 和 backend capabilities 派生；
- `install_contract` / `health_check` / `smoke_test` / `uninstall_contract`：由 backend adapter 的约定或独立 worker metadata 提供，不要求复制到 legacy backend manifest；
- `permissions` / `data_boundary`：使用 runtime 保守默认值，再由 backend/config 显式收紧或细化。

external-cli 的默认数据边界不是简单的“必然发送到远端 provider”，而是：

```text
execution_boundary = external-process
egress = unknown-or-provider-dependent
sensitive_auto_dispatch = deny-unless-explicitly-classified
```

如果 backend/profile 明确连接远端 provider，则归一化结果必须标记为 external transmit；如果明确是本地模型，可以标记为 local-only。未知配置按保守边界处理，不能自动接收敏感任务。

现有 Backend Registry 因此不需要推翻；它成为 Worker Runtime Registry 中 `external-cli` runtime 的 adapter/source of truth。§10 的外发红线仍适用于最终被判定为 `external-transmit` 的路径；这里的分类只是为了区分本地 CLI、本地模型与远端 provider，不降低安全承诺。

### 2.4 最终目标仓库结构

完整目标结构只在本路线图定义；`platform-architecture-v2.md` 只记录已经实现的 external-cli 子层：

```text
platform/
  contracts/
    worker-manifest.schema.json
    capability-probe.schema.json
    backend-manifest.schema.json
    surface-manifest.schema.json
    routing.schema.json
  registry/
    WorkerRegistry.psm1
    ExternalCliWorkerAdapter.psm1
    NativeProviderWorkerLoader.psm1
  hosts/
    codex/
      CodexHostAdapter.psm1
      CapabilityProbe.psm1
      Doctor.psm1
  transports/
    native-plaintext/
    hook-handoff-v1/
  runtime/
    BackendRegistry.psm1
    RoutingEngine.psm1
    SurfaceInvoker.psm1
  generation/
  validation/

shared/
  scripts/
    ThinRelay.psm1

scripts/
  relay.ps1
  run_relay.ps1       # compatibility wrapper during deprecation window
  route_relay.ps1     # compatibility wrapper during deprecation window

workers/
  native-providers/
    deepseek-v4-flash/
      worker.json
      agent.toml
      smoke/

backends/
  claude/
  opencode/
  antigravity/

surfaces/
packages/
tests/
  matrix/

docs/
  evidence/
    codex-capability/
  test-matrix.md
```

目录名在实现时可以按 PowerShell/module 习惯微调，但所有权边界不能倒退：Worker Runtime Registry、host adapter、transport、doctor/evidence 和 CLI backend adapter 必须可独立演进。`platform/registry/WorkerRegistry.psm1` 提供跨 runtime 的统一视图；`platform/runtime/BackendRegistry.psm1` 只是 external-cli 数据源之一，通过 adapter 接入前者。

## 3. Codex Capability Probe：行为证据优先于版本号

Codex 的 multi-agent、custom agent/provider、Hook 和 collaboration 表面仍可能随版本、模型和宿主变化。因此最低版本只能作为提示，**不能作为 native-provider 可用性的充分条件**。

安装、doctor 和发布验证必须运行 capability probe。**Probe schema 本身是版本化平台产物**，计划路径为 `platform/contracts/capability-probe.schema.json`；roadmap 不把某次 Codex build 的具体 feature 名称当成永久 API。

当前需要覆盖的能力类别示例如下：

```text
host identity / build
codex CLI version
multi-agent availability
custom agent discovery + spawn
custom provider load
fork / context isolation
SubagentStart-equivalent hook support
hook additional context
native wait / callback / cancel
initial plaintext assignment
follow-up plaintext transport
```

实现后的机器字段名以 capability-probe schema 为准。`multi_agent_v2_enabled`、`fork_turns_none` 等只能作为某个版本的 probe 字段或 evidence，不能成为路线图正文里的永久接口。

### 3.1 Probe 原则

- 优先探测行为，不仅检查配置键是否存在；
- probe 默认不调用付费第三方模型；
- 可以用本地 agent discovery、配置解析、Hook protocol test 和无外部调用的 spawn 前置验证确认结构能力；
- 真正 provider/model identity 必须通过用户显式触发的 paid smoke test 验证；
- 任一关键能力不满足时 fail closed，并输出明确缺失项；
- 不因为版本号较新就假设 fork isolation、Hook 或 callback 一定工作。

A2 每次基线探测必须生成不可变 evidence artifact，建议放在：

```text
docs/evidence/codex-capability/<YYYY-MM-DD>-<codex-version>-<host>.json
```

证据至少包含：probe schema version、Codex/CodeX build、日期、feature 状态、行为探测结果、失败原因和测试 surface。B2 是否直接走原生 plaintext、B3 是否允许进入 Hook spike，都以最新通过 review 的 evidence/ADR 为依据，而不是根据 roadmap 中可能过期的 feature 名推断。

当前开发环境的 feature 状态只应记录在 evidence 中，不作为长期规范文本。

## 4. Provider-native agent pack

每个 native-provider worker 使用独立 Codex agent role/config overlay，不改写主 Agent 的 provider/model。首选显式 role 注册，避免把“文件存在”误当成“宿主已经发现该 agent”。

当前目标配置形态应类似：

```toml
# CODEX_HOME/config.toml 中只注册 role；不修改全局 model/model_provider
[agents.deepseek-v4-flash]
description = "Read-only DeepSeek native child worker"
config_file = "<pack-owned-path>/deepseek-v4-flash.toml"
```

worker overlay：

```toml
# <pack-owned-path>/deepseek-v4-flash.toml
model_provider = "deepseek"
model = "<provider-model-id>"
sandbox_mode = "read-only"

[model_providers.deepseek]
name = "DeepSeek"
base_url = "<responses-compatible-endpoint>"
wire_api = "responses"
env_key = "DEEPSEEK_API_KEY"
```

`<responses-compatible-endpoint>` 可以是 provider 官方 Responses endpoint，也可以是经过明确审查的本地 protocol adapter；如果上游只有 Chat Completions 语义，不能因为 URL 可访问就宣称其已经满足 Codex Responses/tool-turn contract。

具体字段、相对路径解析和 agent discovery 规则以当前 Codex 版本实际支持的配置格式为准，安装前由 capability/config probe 验证。文档中的示例不能替代 runtime validation。

### 4.1 安全约束

- provider 配置只属于该 worker pack，不写全局主 provider/model；
- secret 只来自环境变量或 Codex 当前支持的 credential source；
- API key 不进入 manifest、agent prompt、Git、Hook envelope、日志或 terminal transcript；
- 默认 `read-only`；写 worker 必须作为单独 variant 审查；
- native external-provider worker 读取的 prompt、文件内容和 tool result 均视为可能发送给该 provider；
- 安装器遇到非本 pack 拥有的同名 agent/Hook/state 必须停止并报告冲突。

## 5. 跨 provider transport：优先原生 plaintext，Hook 只是可拔除兼容层

### 5.1 首选路径

如果当前 CodeX 能把父任务的 plaintext assignment 原生传给不同 provider 的 child，则直接使用原生 transport。

父 Agent 必须构造完整、自洽的 assignment。跨 provider child 默认是 bounded one-shot worker，不依赖继承整个父对话才能理解任务。

### 5.2 Hook handoff fallback

只有当“native child 可创建，但父任务 plaintext 无法可靠抵达 child”时，才启用受信任的一次性 handoff transport。

建议作为独立 transport 子系统：

```text
platform/transports/
├─ native-plaintext/
└─ hook-handoff-v1/
```

不要把 Hook 逻辑写死在 DeepSeek worker 中。DeepSeek 只是第一个 consumer。

`hook-handoff-v1` 必须满足：

- 只匹配精确 worker id；
- 父 Agent 先 stage 一个完整 assignment；
- child 使用 `fork_turns="none"` 或当前 Codex 等价的隔离语义；
- envelope 包含随机 nonce / marker、worker id、created_at、expires_at 和 payload；
- 原子 claim；
- 一次消费；
- 并发锁；
- TTL；
- replay rejection；
- malformed/corrupt state quarantine；
- consumer identity mismatch 拒绝；
- assignment 本机短暂明文的数据边界必须明确；
- Hook 仅注入 assignment，不接管 child 生命周期；
- child 最终仍通过 Codex 原生 callback 返回。

上游 plaintext transport 一旦稳定通过验收，Hook transport 必须可独立卸载。

## 6. 首批 DeepSeek Native Child MVP

### 6.1 支持范围

第一批只做低风险、read-only delegation：

- 代码/文本阅读；
- repo 搜索；
- 日志分析；
- 提取与枚举；
- 多文件批量理解；
- 方案评审；
- 只读研究任务。

首批不做：

- 文件写入；
- Git commit；
- secret-bearing repo；
- 自动 fallback 到其他 provider；
- 自动重复付费调用；
- 依赖跨 provider follow-up 才能完成的长对话任务。

### 6.2 目标用户路径

理想用户体验：

```text
用户：把这个只读分析任务交给 DeepSeek worker。

Codex 主 Agent
  → 选择 worker: deepseek-v4-flash
  → 检查数据边界和 host capability
  → 创建 native child
  → child 使用 DeepSeek provider/model
  → Codex UI 显示独立 child
  → 主 Agent wait
  → 原生 callback 返回结果
  → 主 Agent review
```

用户不需要手写 DeepSeek CLI，也不需要把主 Codex provider 切换到 DeepSeek。

## 7. 分阶段实施计划

### Phase A0：Thin Relay v2 基线收口

A0 **不重复拥有 external-cli 修复任务**。`--log-dir` 实时 mirror、命令脱敏、进程契约测试和 v1 行为清理均由 [Thin Relay v2 SOP](thin-relay-v2-sop.md) 的 Phase 0/1 负责。

本路线图只把以下条件作为 native-provider 开工前置门槛：

1. SOP Phase 0 exit gate 通过；
2. SOP Phase 1 的薄核心与确定性契约测试通过；
3. 对应测试证据可重复执行；
4. external-cli 的已知剩余缺口不会与 Worker Runtime Registry / host adapter 发生所有权冲突。

**退出门槛：** 由 Thin Relay SOP 的 Phase 0/1 exit gate 提供证据，本路线图不维护第二份重复清单。

### Phase A1：Worker Runtime Registry

1. 新增 worker manifest schema；
2. 保留 Backend Registry 作为 `external-cli` adapter；
3. 把 Claude/OpenCode/Antigravity 映射为 `runtime_type=external-cli`；
4. 为 `native-provider` 建独立 validator/loader，不要求 `command` 或 `runner_script`；
5. build/validation 根据 runtime discriminator 分派，不出现 native-provider 的假 command；
6. worker id 成为后续 install/doctor/dispatch/audit 的稳定主键。

**退出门槛：** Registry 能同时描述一个 external-cli worker 和一个无 CLI 的 synthetic native-provider fixture，并通过 schema/validation test。

### Phase A2：CodeX Host Adapter 与 Capability Probe

1. 实现 CodeX host adapter；
2. 实现 `platform/contracts/capability-probe.schema.json` 并版本化 probe 输出；
3. 探测 agent discovery、custom provider、custom agent spawn、fork isolation、SubagentStart Hook、additional context、wait/callback/cancel 等当前实际能力；
4. 输出机器可读 capability report；
5. capability 不满足时 fail closed；
6. 添加针对当前开发 Codex 版本的 regression fixture，不把版本号写成唯一判据；
7. 每次基线验证生成 `docs/evidence/codex-capability/` evidence，并在需要 transport 取舍时附 ADR/decision note。

**退出门槛：** doctor 可以明确告诉用户“哪些能力可用、哪些能力阻止 native-provider”，且没有第三方付费调用；对应 evidence 已落盘，可作为 B2/B3 的决策输入。

### Phase B1：DeepSeek Agent Pack + Provider Preflight

1. 增加 `deepseek-v4-flash` worker manifest；
2. 增加独立 agent role 注册 + provider/model overlay TOML；若 DeepSeek 当时没有满足 Codex Responses/tool-turn 语义的直连接口，则把 protocol adapter 作为显式 provider transport dependency，而不是藏进 Relay core；
3. secret-safe preflight：只确认 env var 是否存在，不打印值；
4. 默认 read-only sandbox；
5. install/uninstall 只操作 pack 自己拥有的文件；
6. 不改变主 Agent provider/model；
7. 增加配置解析与 uninstall ownership tests。

**退出门槛：** 无付费调用即可完成安装、发现、配置验证、卸载和主配置不变断言。

### Phase B2：Native Plaintext Transport First

1. 用最小 deterministic assignment 测试 native child；
2. 首选 Codex 原生 initial plaintext transport；
3. 验证 `fork_turns="none"` 或当前等价隔离语义；
4. 验证 child 收到完整 marker；
5. 验证原生 wait/callback；
6. 生成本次 transport evidence，并引用 A2 的 capability evidence。

若这一阶段全部通过，**不实现 Hook**。是否进入 B3 必须由 evidence + ADR/decision note 明确记录，不能靠维护者口头判断。

### Phase B3：Hook Handoff Compatibility Layer（仅在 B2 被 transport 阻断时）

1. 实现 `platform/transports/hook-handoff-v1`；
2. protocol tests 覆盖 nonce、TTL、atomic claim、one-shot、concurrency、quarantine、replay、identity mismatch；测试至少包含进程内 deterministic claim-store fixture 与真实临时文件系统 fixture，后者用于验证锁、原子 rename/claim、并发竞争和损坏 state quarantine；
3. Hook 只对精确 worker 生效；
4. Hook trust 必须由用户/宿主正常机制建立，安装器不得伪造 trust；
5. child callback 仍走 Codex native lifecycle。

**退出门槛：** Hook 只解决 task delivery，不成为第二套 orchestration runtime。

### Phase B4：用户显式 Paid Smoke Test

付费 smoke 必须显式触发，不在 install/doctor 默认执行。

测试应生成随机 marker，并同时证明：

- 主 Agent provider/model 未改变；
- UI/tool event 中出现独立 worker id；
- child 实际 provider/model 等于 manifest；
- assignment marker 到达 child；
- child 返回确定性 marker；
- wait/callback 由 Codex 原生完成；
- 未启动 external CLI 或第二个 Codex；
- secret 未出现在配置 diff、日志、prompt、Hook state 或测试输出。

**只有 B4 通过后，README 才能宣称该 DeepSeek worker 是 supported native child。**

### Phase C：统一 Dispatch Policy

Dispatch 与现有 external-cli route 是两层，不互相替代：

```text
用户/主 Agent
  ↓
Worker Dispatch
  ├─ 显式 native-provider worker → Codex native child
  ├─ 显式 external-cli worker → 对应 CLI backend
  └─ 显式请求自动选择
       ├─ 先决定 runtime class / worker policy
       └─ 若落到 external-cli router surface，再由 relay route 选择具体 CLI backend
```

- `dispatch` 解决“选哪个 worker/runtime”；配置归 Worker Runtime Registry / host policy；
- `relay route` 只解决 external-cli 里的“选哪个 CLI backend”；配置仍归 `.relay-agent/routing.json` 等现有 routing contract；
- 用户显式点名 `deepseek-v4-flash`、`claude`、`opencode` 等稳定 worker/backend id 时，不经过自动 heuristic 覆盖；
- 不允许 `relay route` 选择或伪装 native-provider；native-provider selection 只能由 Worker Dispatch 负责。

实施要求：

1. 主 Agent 根据用户显式选择、数据分级、host capability 和 worker capability 决定 runtime；
2. 用户点名 worker 时不得被 heuristic 替换；
3. 自动调度可优先 native-provider，其次 external-cli，但跨 provider fallback 必须符合数据策略；
4. native-provider 失败时默认 fail closed；
5. 每次 dispatch 记录公开 metadata：worker id、runtime type、host、provider/model、data-boundary decision、result status；
6. Relay CLI core 不重新获得 child lifecycle、retry 或 output interpretation 职责。

### Phase D：扩展其他第三方 Provider

当 DeepSeek contract 稳定后，第二个 provider 必须以“零核心特判”为目标接入。

验收标准：新增 provider 主要是增加 manifest + agent/provider config + smoke fixture，不修改 DeepSeek-specific core branch。

### Phase E：其他宿主

1. Claude Code、OpenCode、generic shell 各自有 host adapter；
2. capability detector 决定可安装 runtime；
3. 不支持 native provider child 的宿主只暴露 external-cli worker；
4. CodeX Hook 配置不复制给其他宿主；
5. 产品文案明确区分 native lifecycle 和 CLI process lifecycle。

## 8. 发布门槛、风险与验收矩阵

### 8.1 Phase → release / claim gate

不在路线图中预先绑定具体 SemVer；版本号由 `docs/release-checklist.md` 的发布策略决定。这里绑定的是**能对外声称什么**：

| Gate | 必要阶段 | 允许对外声明 |
|---|---|---|
| External CLI baseline | SOP Phase 0 + 1 | Thin Relay external-cli 核心 contract 已有确定性测试证据 |
| Worker platform foundation | A1 + A2 | Worker Runtime Registry / CodeX host + Codex capability probe 可用；只能称 native-provider candidate infrastructure |
| Native transport candidate | B1 + B2，或有证据进入 B3 | DeepSeek native-provider candidate 可安装、可探测；尚不能称 supported |
| Supported native child | B4 | 对已验证的 host/provider/model 组合可称 supported Codex native child |
| Provider-extensible platform | D | 第二个 provider 在无核心 provider 特判前提下接入成功 |

README 的能力状态必须跟随 gate，不得因为代码已合并但 smoke/evidence 未通过而提前升级措辞。

### 8.2 关键风险与 Spike / 退路

最大技术不确定性不是 DeepSeek API 本身，而是目标 Codex build 是否同时提供：第三方 provider native child、可靠 plaintext assignment、隔离语义以及原生 callback/cancel。

实施原则：

1. A2 先做 capability spike 并保存 evidence；
2. B2 先验证官方/native plaintext transport；
3. 只有 evidence 证明 task delivery 是唯一阻断点时才进入 B3 Hook spike；
4. 如果 native plaintext 不可行，且 Hook 又因 trust/host 约束无法满足安全与生命周期要求，**不得退化为伪 native**；该发布只交付 A0-A2（以及可独立成立的 B1 配置/preflight），第三方模型继续通过 external-cli 路线使用；
5. 后续 Codex build 能力变化后，用新的 capability evidence 重新开启 B2/B3，不需要推翻 Worker Runtime Registry。

这条退路是正式计划分支，不视为项目失败，也不得用 CLI/SDK/MCP 冒充完成 B4。

完整跨文档测试目录由 [测试矩阵](test-matrix.md) 维护；roadmap 只保留 native-provider 的发布级验收门槛。

### 8.3 Native-provider

以下全部成立才可称为 Codex native child：

- [ ] 主任务模型/provider 保持不变；
- [ ] 独立 child task 可见；
- [ ] child agent type 等于 worker id；
- [ ] child provider/model 与 manifest 一致；
- [ ] child 不是 CLI / SDK / MCP / 第二 Codex 进程；
- [ ] assignment 完整到达 child；
- [ ] fork/isolation 语义符合预期；
- [ ] 父任务通过原生 wait/callback 收到结果；
- [ ] 原生 cancel 可验证；
- [ ] install/doctor 默认无付费模型调用；
- [ ] secret 不进入 repo/config diff/log/prompt/terminal transcript；
- [ ] read-only worker 无非预期写入；
- [ ] 如使用 Hook，protocol tests 全通过；
- [ ] uninstall 能安全移除仅属于该 pack 的 agent/Hook/state/index；
- [ ] capability report 与实际行为一致。

### 8.4 External CLI

- [ ] `relay run` 构造的命令可复制为原生 CLI 命令；
- [ ] 显式 model/agent/passthrough 未被改写；
- [ ] stdout/stderr 实时可见；
- [ ] `--log-dir` 是 mirror，不改变实时语义；
- [ ] Relay 返回原始退出码；
- [ ] 默认一次调用；
- [ ] 无 Relay timeout/retry/Git polling/JSONL 摘要/伪进度；
- [ ] CodeX child 发起 CLI 时，只宣称外层 child 是 native lifecycle。

## 9. 文档与产品语言规则

为了避免能力膨胀式宣传，所有文档遵循：

- `native child`：只用于通过第 8.3 Native-provider 验收的 worker；
- `native-provider candidate`：配置和 capability 已存在，但 paid identity/callback smoke 尚未通过；
- `external-cli worker`：外部进程，不论由谁发起都不变成 provider-native child；
- `supported`：当前发布版本已有自动化或可复现证据；
- `experimental`：依赖 under-development Codex surface 或仅在部分版本/模型组合验证；
- 不承诺读取 worker hidden reasoning，只审查公开 tool events、输出和最终结果。

## 10. 安全与运营红线

- 不把 API key 写入 Relay manifest、agent TOML 明文值、Hook、日志、测试 fixture、terminal transcript 或 Git；
- external provider 收到的所有输入均按“数据已外发”处理；
- 默认禁止委派密钥、个人数据、受监管数据、用户未授权私有源代码；
- read-only 仅代表本地写权限，不代表数据不外发；
- Hook 是用户信任的可执行代码，安装器不绕过 trust；
- provider-native 失败默认 fail closed；
- 不静默换 provider/model/runtime；
- paid smoke、写 worker、敏感数据外发必须显式授权。

## 11. Hook 退出条件

当 CodeX 上游原生 plaintext transport 在目标 host/model/provider 组合下稳定满足：

- initial assignment；
- 必要的 follow-up（若产品需要）；
- 正确 child identity；
- isolation；
- permission/sandbox；
- wait/callback；
- cancel；

则：

1. 停止新安装 `hook-handoff-v1`；
2. 删除 Hook adapter 和本地明文 state；
3. 保留 worker manifest、provider config、安全边界和验收测试；
4. transport 切换为官方机制；
5. 发布迁移说明并验证 uninstall 不影响用户其他 Hooks。

## 12. 首批交付定义

首批 CodeX native-provider 版本不是“支持了一个 DeepSeek API”就完成，而是必须交付完整纵切：

```text
Worker manifest
  + CodeX capability probe
  + DeepSeek agent/provider pack
  + secret-safe install/doctor/uninstall
  + native plaintext transport 或受限 Hook fallback
  + native child identity
  + native wait/callback/cancel
  + deterministic paid smoke
  + data-boundary policy
  + protocol / regression tests
  + accurate README status
```

完成这条纵切后，第二个第三方 provider 才开始接入。第二个 provider 能否在不新增核心特判的情况下上线，是 Worker Runtime Registry 是否真正成立的关键架构验收。