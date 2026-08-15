# Codex Native Subagent 下一阶段实施计划（2026-08-15）

> 状态：下一阶段执行计划  
> 适用项目：`relay-agent-platform`  
> 上游依据：`docs/codex-native-subagent-roadmap.md`、`docs/test-matrix.md`、现有 DeepSeek B4 evidence 与当前代码落地情况  
> 当前基线：DeepSeek 已在 **codex-cli 0.147.0 / win32 / 指定 Responses-compatible provider+model 组合**下通过 B4，可称 supported Codex native child；下一阶段重点不再是验证“能不能做”，而是补齐 Desktop、多 provider、产品化入口和可重复发布证据。

## 1. 当前已完成基线

以下能力视为本计划的既有前提，不重复造轮子：

- Worker Runtime Registry 已支持 `native-provider` / `external-cli` 双 runtime；
- DeepSeek `native-provider` worker pack 已存在；
- Codex host adapter、capability probe、doctor/evidence 机制已存在；
- 原生 plaintext transport 已通过，不需要进入 Hook handoff B3；
- DeepSeek 在已验证组合下已通过 native `spawn_agent`、`wait`、`send_input`、`close_agent` 生命周期；
- Dispatch Policy 已有模块级实现；
- 第二 provider 的“零核心特判”已通过 synthetic fixture 验证；
- external-cli Thin Relay 继续保持独立，不得重新承担 native child lifecycle。

本阶段禁止因为做产品化收口而倒退以下边界：

1. 不用 CLI / SDK / MCP / 第二 Codex 进程冒充 native-provider child；
2. 不把 native-provider 硬塞进 legacy backend manifest；
3. 不恢复 Hook，除非新的明确 runtime evidence 证明 native plaintext 再次成为唯一阻断点；
4. 不修改主 Codex 的全局 provider/model 来完成 worker 接入；
5. native-provider 失败继续 fail closed，不静默换 provider/runtime。

## 2. P0：补齐 Codex Desktop 独立 B4 验收

### 目标

确认 Codex Desktop 作为独立宿主时，DeepSeek worker 同样满足 native child 定义，而不是从 Codex CLI 的结果做推断。

### 必做项

- [ ] 明确记录 Codex Desktop 的 build / runtime identity；
- [ ] 确认 Desktop 是否复用与 CLI 相同的 agent/provider 配置与 native multi-agent runtime；
- [ ] 在 Desktop 发起 `deepseek-v4-flash` native child；
- [ ] 记录独立 child identity / thread id / tool event；
- [ ] 验证 child 实际 provider/model 与 worker 声明一致；
- [ ] 用随机 deterministic marker 验证 initial plaintext assignment；
- [ ] 验证 Desktop 内的 native wait/callback；
- [ ] 验证 follow-up transport（若 Desktop 产品路径允许）；
- [ ] 验证 cancel/close；
- [ ] 确认没有 external CLI、SDK/MCP bridge 或第二 Codex 进程；
- [ ] 检查 secret 不进入日志、prompt、配置 diff、evidence；
- [ ] 将结果写入新的 Desktop-specific capability / transport evidence。

### Evidence 建议

```text
docs/evidence/codex-capability/<date>-codex-desktop-<build>-win32.json
docs/evidence/transport/b4-native-child-desktop-<date>.md
docs/evidence/transport/b4-native-child-desktop-<date>.jsonl
```

### 退出门槛

只有全部 B4 关键项通过后，README 才可以写：

> DeepSeek native child supported on Codex Desktop（限定已验证 build/provider/model 组合）。

如果 Desktop 与 CLI runtime 共享实现，也必须保留独立 host evidence，不能只写“理论上相同”。

## 3. P0：把 native-provider 能力接入正式用户入口

> 详细设计见 [`native-provider-agent-onboarding-plan-2026-08-15.md`](native-provider-agent-onboarding-plan-2026-08-15.md)。该设计是本节的 P0 实施细化，目标是让安装 `relay-agent` skill 的任意 Agent 都能自行发现配置状态、向用户只收集 Base URL / Model ID / API Key，并自动完成安全配置、doctor 与执行准备。

> 状态（2026-08-15）：P0-1/P0-2/P0-3 已落地（`relay worker` 命令面 + profile/credential contract + 锁定 Pester runner，147 项确定性测试，`scripts/test.ps1` 复现）。**P0-4 与 P0-5 已完成**：profile-suffixed `<worker-id>--<profile-id>` agent role 的 native child 全链路已在 codex-cli 0.147.0（`b4-native-child-profile-suffix-2026-08-15.md`）与 Codex Desktop 26.810.6296.0 / bundled 0.148.0-alpha.9（`b4-native-child-desktop-2026-08-15.md`）各自独立验收通过；Desktop UI 展示层由用户手动确认。

### 当前问题

现有核心模块已经有：

- `Install-WorkerPack`
- `Uninstall-WorkerPack`
- `Get-DispatchDecision`
- `Get-AutoDispatchDecision`
- `Invoke-CapabilityProbe`
- `Get-CodexCapabilityReport`

但它们主要仍作为模块与测试能力存在，尚未形成完整、稳定、可发现的普通用户入口。

### 目标

让用户不需要直接 Import PowerShell module，也能完成 native-provider 的完整生命周期。

### 建议 CLI 形态

命名可以按现有命令风格微调，但至少需要覆盖：

```text
relay worker list
relay worker show <worker-id>
relay worker status <worker-id> [--profile <profile-id>]
relay worker configure <worker-id>
relay worker credential set|status|remove <worker-id> --profile <profile-id>
relay worker install <worker-id>
relay worker doctor <worker-id> [--profile <profile-id>]
relay worker dispatch <worker-id> [--profile <profile-id>] -- <task>
relay worker uninstall <worker-id>
```

自动选择可单独提供：

```text
relay worker dispatch --auto -- <task>
```

### 必做项

- [ ] `list` 同时展示 external-cli 与 native-provider，但明确 runtime type；
- [ ] `show` 展示 provider contract、data boundary、sandbox、已配置 profile 与 credential source 名称，不展示 secret；
- [ ] 新增用户级 provider profile，把 Base URL / Model ID / credential source 从 pack 模板中分离；
- [ ] `configure` 同时支持 masked 人类交互与 Agent 非交互模式；Agent 模式通过 stdin/credential adapter 接收 API Key，禁止 `--api-key <value>`；
- [ ] 所有 `worker` 管理命令提供稳定 `--json` 合同，让不同 Agent 不必解析人类文案；
- [ ] generated `relay-agent/SKILL.md` 明确写出 discover → collect missing fields → configure → doctor → dispatch 的 Agent 协议；
- [ ] 用户已经提供 Base URL / Model ID / API Key 时，Agent 不重复询问其他内部配置字段；
- [ ] `install` 调用 pack-owned install contract；
- [ ] `doctor` 联合检查 worker manifest、credential presence、provider alignment、host capability；
- [ ] `dispatch` 尊重显式 worker id，不被 heuristic 覆盖；
- [ ] native-provider dispatch 在 capability 不满足时 fail closed；
- [ ] `uninstall` 只删除 pack-owned state；
- [ ] 所有命令输出稳定、可测试、可用于 release evidence；
- [ ] external-cli 的 `relay run/route` 行为不因新增 worker 命令而改变。

### 退出门槛

一个新用户可以只通过正式入口完成：

```text
发现 worker → status → configure/profile+credential → doctor → install/注册 → dispatch → uninstall
```

不需要手工修改模块内部路径或直接调用 `.psm1` 函数。

## 4. P0：锁定 Pester / 测试运行环境

### 当前问题

历史 evidence 使用过 Pester 6.1.0，测试矩阵要求 Pester v5+；但 2026-08-15 当前 DevSpace 环境加载了 Pester 3.4.0，导致顶层 `BeforeAll` 在 test discovery 阶段直接失败，测试断言没有真正执行。

这不是业务回归，但说明 release/test runner 目前不可重复。

### 必做项

- [x] 明确项目支持的 Pester major 版本（建议 `>=5 <7` 或直接锁具体 major）——已锁定 `>=5 <7`，当前验证版本 Pester 6.1.0 / pwsh 7.6.4；
- [x] 提供统一测试入口，例如 `scripts/test.ps1`；
- [x] runner 启动时检查 Pester 版本，不满足立即输出明确错误；
- [x] CI / release checklist 统一调用同一个 runner；
- [x] native-provider、external-cli、host adapter、dispatch 测试都走统一入口；
- [x] 测试 evidence 记录 PowerShell、Pester、OS、Codex build；
- [x] README 中“89 项确定性测试”等数字改为由当前可重复 runner 产生，不手工维护陈旧数字（现为 91 项，`scripts/test.ps1 -ExportEvidence` 输出）。

### 退出门槛

在干净环境中执行一个命令即可：

1. 确认测试依赖版本；
2. 运行完整 deterministic suite；
3. 得到稳定 pass/fail 结果；
4. 可将结果直接纳入 release evidence。

## 5. P1：用第二个真实 Provider 完成 Phase D

### 当前状态

现有 `provider-b` fixture 已证明 Registry / Dispatch 核心没有 DeepSeek-specific branch。这证明了架构方向，但还没有证明第二个真实 provider 能完整通过 native child runtime。

### 目标

选择一个真正独立于 DeepSeek 的 Responses-compatible provider/model，完成与 DeepSeek 相同的 B1/B2/B4 纵切，并做到尽量零核心修改。

### Provider 选择原则

优先选择：

- 真正支持 Codex 所需 Responses/tool-turn 语义；
- provider identity 可明确验证；
- 有稳定的 API / endpoint；
- 不需要为该 provider 向 `platform/registry` 增加专用 branch；
- 能用独立 env credential；
- 可以 read-only worker 起步。

可选对象由实施时的实际 Responses compatibility 决定，例如 Qwen、Kimi、GLM、其他 OpenAI Responses-compatible provider；不要仅因为“Chat Completions 能请求成功”就判定合格。

### 必做项

- [ ] 新增第二真实 provider worker pack；
- [ ] 只通过 manifest + agent/provider config + smoke fixture 接入；
- [ ] `platform/registry` 不新增 provider 字面量；
- [ ] install/doctor/uninstall 复用现有 WorkerPackManager；
- [ ] capability / transport 复用现有 Codex host adapter；
- [ ] native plaintext transport 仍优先；
- [ ] 完成 paid B4 smoke；
- [ ] 生成独立 provider evidence；
- [ ] 对比 DeepSeek 接入 diff，确认核心没有 provider-specific 分叉。

### 退出门槛

当第二真实 provider 通过 B4，且核心 Registry/Dispatch 无 provider 特判时，才把平台对外定义为：

> provider-extensible native-provider platform

在此之前，只能说“架构支持扩展”。

## 6. P1：修正 Capability Probe 状态语义

### 当前问题

当前 evidence 中存在类似：

```text
hook_additional_context.status = supported
hook not used; native plaintext transport verified
```

这会把“该能力不需要”与“该能力已验证支持”混为一谈。

### 目标

让 capability report 严格描述证据，而不是为了 aggregate gate 全绿而扩大 `supported` 的含义。

### 建议状态模型

至少区分：

```text
supported
blocked
unknown
not-tested
not-required
```

若不希望立刻扩 schema，也可以用等价字段表达：

```text
status = unknown
required = false
```

关键是不要把未测试能力写成 supported。

### 必做项

- [ ] 更新 capability-probe schema；
- [ ] 更新 doctor 聚合逻辑，只阻断 required capability；
- [ ] Hook 未进入时输出 `not-required` / 等价状态；
- [ ] 保持 B2/B4 native plaintext gate 不受影响；
- [ ] 为状态组合补 deterministic tests；
- [ ] 迁移或解释旧 evidence，不篡改不可变历史 evidence。

### 退出门槛

Capability report 能同时回答两个问题：

1. 这个 host/runtime 能否运行 native-provider？
2. 每个单独 feature 到底是已验证、未验证、无需验证，还是被阻断？

## 7. P1：统一 Host 身份与 supported claim 边界

### 目标

避免继续用 `win32 + codex CLI version` 代表所有 Codex 宿主。

### 必做项

- [ ] host identity 中明确区分 CLI / Desktop；
- [ ] evidence key 至少包含 host surface / build；
- [ ] `supported` 绑定到 host + build/version + provider + model 组合；
- [ ] host adapter 加载 evidence 时避免跨 surface 误复用；
- [ ] Desktop 和 CLI 的 claim 独立展示；
- [ ] 未来 macOS/Linux 也沿用同一组合级 gate。

### 退出门槛

系统不能因为存在一个 Win32 CLI B4 evidence，就自动把 Desktop 或另一 CLI build 判定为 supported。

## 8. P2：文档与产品语言全局收口

### 当前问题

README 已经写明 A1/A2/B1/B2/B4 等阶段完成，但部分后文仍把 `platform/` 描述为“下一阶段承载 Worker Runtime Registry / host adapter”，存在历史状态残留。

### 必做项

- [ ] README 全局 sweep 当前/未来时态；
- [ ] Quickstart 增加 native-provider 的正式用户路径；
- [ ] 明确区分 `native-provider` 与 `external-cli`；
- [ ] 明确 supported 组合的精确边界；
- [ ] synthetic second-provider 测试不得写成“第二真实 provider 已支持”；
- [ ] Desktop 未通过 B4 前不得写“Desktop supported”；
- [ ] 所有旧架构文档继续归档，不让 Archive 状态与当前 roadmap 互相覆盖；
- [ ] release checklist 加入 provider/host/model 组合级 evidence 检查。

## 9. 建议实施顺序

建议严格按以下顺序推进：

```text
P0-1  Agent-first provider onboarding / profile / credential contract          [x] 已落地
  ↓
P0-2  native-provider 正式 worker CLI + JSON contract + skill Agent 协议        [x] 已落地
  ↓
P0-3  锁定测试 runner / Pester                                                [x] 已落地
  ↓
P0-4  Codex CLI 当前版本 regression（profile-suffixed role B4）                [x] 已通过（2026-08-15）
  ↓
P0-5  Codex Desktop 独立 B4（runtime 层；UI 层用户确认）                        [x] 已通过（2026-08-15）
  ↓
P1-1  capability 状态语义修正
  ↓
P1-2  第二真实 provider B4
  ↓
P1-3  host/support claim 组合级治理
  ↓
P2    README / quickstart / release 文档收口
```

其中测试 runner 可以与 Desktop spike 并行，但在宣布新的 supported claim 前必须先有可重复的 deterministic suite。

## 10. 下一阶段完成定义（Definition of Done）

本计划不是完成几个模块就结束。下一阶段全部完成时，应满足：

- [x] DeepSeek 在 Codex CLI 的已验证组合继续通过 B4 regression；
- [x] DeepSeek 在至少一个 Codex Desktop build 下通过独立 B4；
- [ ] native-provider 有稳定用户入口：list/show/status/configure/credential/install/doctor/dispatch/uninstall；
- [ ] 用户只提供 Base URL、Model ID、API Key，安装了 `relay-agent` skill 的 Agent 即可按照 skill 合同自动完成配置；
- [ ] API Key 不进入命令行参数、普通配置、日志或 JSON 输出；
- [ ] worker pack 与用户 provider profile 分离，同一 worker 可绑定多个 Base URL / Model ID profile；
- [ ] deterministic test suite 在锁定 Pester 环境下一键可复现；
- [ ] capability schema 能区分 supported / blocked / unknown / not-tested / not-required；
- [ ] 第二个真实第三方 provider 在不新增核心 provider 特判的前提下通过 B4；
- [ ] support claim 精确绑定 host/build/provider/model；
- [ ] README / quickstart / release checklist 与实际能力一致；
- [ ] external-cli 与 native-provider 的责任边界没有倒退；
- [ ] 没有为了补产品化入口而引入新的伪 native orchestration 层。

## 11. 最终目标形态

完成本计划后，项目应从当前的：

```text
已验证的 DeepSeek Codex CLI native-child 纵切
+ 通用 Worker Runtime Registry
+ 部分内部管理 API
```

推进到：

```text
Codex CLI + Codex Desktop
        ×
多个真实 Responses-compatible provider
        ×
统一 worker install / doctor / dispatch UX
        ×
组合级 capability/evidence gate
        ×
可重复 CI / release validation
```

此时才能把项目从“核心技术方案已成功落地”升级为“可持续扩展、可发布、可被普通用户稳定使用的 Codex native-provider subagent 平台”。
