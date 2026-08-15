# Relay Test Matrix

> 状态：跨计划测试索引  
> 目的：把 Thin Relay v2、Worker Runtime Registry、CodeX host / Codex capability probe、native-provider transport 与发布验收收敛到一张可执行清单。具体测试实现可以拆成多个文件，本表只定义所有权、稳定性和 Phase gate。

## 1. 测试分层

### 1.1 Gate 语义

| Gate | 含义 |
|---|---|
| `必须` | 对应 Phase 的 deterministic/release gate；未通过则该 Phase 不完成。 |
| `条件` | 只有前置 evidence 触发该能力时才要求通过；“能力不可用”可以是合法 probe 结果，但必须记录，不能静默跳过。 |
| `best-effort` | 外部账号、网络或真实 CLI 相关 integration evidence；失败必须区分 Relay regression 与外部依赖，不作为离线 CI 唯一阻断项。 |
| `supported gate` | 对外使用 `supported native child` 声明的硬门槛；全部相关用例必须有可复现 evidence。 |
| `产品需要时` | 当前首批产品不依赖该能力；一旦产品承诺该能力，对应测试即升级为 `必须` 或 `supported gate`。 |

| 层级 | 目标 | 默认是否进入 CI |
|---|---|---|
| deterministic unit/contract | schema、命令构造、配置优先级、adapter normalization | 是 |
| deterministic process | fake/stub CLI 的 stdout/stderr、exit code、log mirror、missing CLI、redaction | 是 |
| filesystem protocol | Hook claim/TTL/locking/replay/quarantine | 是，使用临时目录 |
| host capability | Codex/CodeX agent/provider/hook/callback 行为探测 | 是，但允许按宿主能力产生 supported/unsupported report；不能静默跳过 |
| provider configuration | agent/provider overlay、credential presence、ownership/uninstall | 是，不调用付费模型 |
| paid native smoke | 真实第三方 provider/model identity + native child lifecycle | 否；用户/维护者显式触发 |
| external integration smoke | 真实 Claude/OpenCode/Antigravity CLI | 发布前 best-effort，不作为离线 CI 唯一判据 |
| network-dependent smoke | 天气、搜索等外部实时能力 | 否；只作诊断性 evidence |

### 1.2 测试框架与 stub CLI 夹具

- 测试运行器：**Pester v5 + Invoke-Pester**，作为 deterministic unit/contract 与 deterministic process 的统一入口。现有 `tests/thin-relay-contract.ps1` 手写断言可迁入 Pester 或保留为轻量冒烟入口，但新增测试一律走 Pester v5。
- stub CLI fixture：`tests/fixtures/stub-cli/` 提供 `opencode.cmd` / `claude.cmd` / `agy.cmd` 三个薄启动器，统一转调同一个 `stub-cli.ps1`；通过 `STUB_EXIT_CODE`、`STUB_STDOUT_LINE`、`STUB_STDERR_LINE` 环境变量控制输出与退出码。测试把 fixture 目录前置到 `$env:PATH`，从而覆盖命令解析、真实进程 spawn、stdout/stderr 分流、exit code、`--log-dir` mirror、CLI missing 与 redaction（TR-PROC-* / TR-LOG-* / TR-ONCE-* / TR-GIT-* / TR-SEC-*）。
- stub fixture 只存在于测试上下文，不得进入 package 生成物。

## 2. Thin Relay external-cli

| ID | 用例 | 类型 | 所属 Phase | Gate |
|---|---|---|---|---|
| TR-CMD-001 | 三 backend 的显式 model/agent/prompt 命令构造 | deterministic contract | SOP 0/1 | 必须 |
| TR-CMD-002 | passthrough 顺序、同名 token、不被 Relay 重新解释 | deterministic contract | SOP 0/1 | 必须 |
| TR-CFG-001 | CLI 值覆盖 workspace/user default | deterministic contract | SOP 0/1 | 必须 |
| TR-DRY-001 | dry-run 不检查/启动 CLI，展示命令与实际构造一致 | deterministic contract | SOP 0/1 | 必须 |
| TR-SEC-001 | `--api-key value` / token / secret / Authorization header 脱敏 | deterministic contract | SOP 0 | 必须 |
| TR-PROC-001 | stdout/stderr 实时分流 | deterministic process | SOP 0/1 | 必须 |
| TR-PROC-002 | 非零 native exit code 原样返回 | deterministic process | SOP 0/1 | 必须 |
| TR-PROC-003 | CLI missing 返回 Relay 层明确错误 | deterministic process | SOP 0/1 | 必须 |
| TR-LOG-001 | `--log-dir` 在实时输出同时镜像日志 | deterministic process | SOP 0 | 必须 |
| TR-GIT-001 | 非 Git workdir 正常执行且 Relay 不调用 Git | deterministic process | SOP 0/1 | 必须 |
| TR-ONCE-001 | 默认只有一次 backend invocation，无 timeout/retry | deterministic process | SOP 0/1 | 必须 |
| TR-ROUTE-001 | `relay route` 只在 external-cli backend 集合内选择 | deterministic contract | SOP 2 / Roadmap C | 必须 |
| TR-CLI-001 | `scripts/relay.ps1 run` 与旧 wrapper 共用同一 thin core | deterministic contract | SOP 1 | 必须 |
| TR-INTEG-001 | 真实 backend direct CLI 与 Relay 等价调用 | external integration | release | best-effort |

## 3. Worker Runtime Registry

| ID | 用例 | 类型 | 所属 Phase | Gate |
|---|---|---|---|---|
| WR-SCHEMA-001 | native-provider manifest 通过 worker schema | deterministic contract | A1 | 必须 |
| WR-ADAPTER-001 | legacy backend.json 归一化为 external-cli WorkerDescriptor | deterministic contract | A1 | 必须 |
| WR-ADAPTER-002 | external-cli 不需要修改 legacy schema 即可提供 runtime_type/host/data defaults | deterministic contract | A1 | 必须 |
| WR-NATIVE-001 | synthetic native-provider fixture 不要求 command/runner_script | deterministic contract | A1 | 必须 |
| WR-ID-001 | worker id 在 install/doctor/dispatch/audit 中稳定 | deterministic contract | A1 | 必须 |
| WR-DATA-001 | unknown external-cli egress 默认禁止敏感 auto-dispatch | deterministic contract | A1/C | 必须 |
| WR-DATA-002 | 明确 local-only / external-transmit profile 正确覆盖保守默认 | deterministic contract | A1/C | 必须 |

## 4. Codex / CodeX Capability Probe

具体字段名由 `platform/contracts/capability-probe.schema.json` 决定，本矩阵只绑定能力语义。

| ID | 能力 | 类型 | Phase | Evidence |
|---|---|---|---|---|
| CP-HOST-001 | host/build/Codex version 可记录 | host capability | A2 | 必须 |
| CP-AGENT-001 | custom agent discovery | host capability | A2 | 必须 |
| CP-AGENT-002 | custom agent/native spawn | host capability | A2 | 必须 |
| CP-PROV-001 | custom provider config 可加载 | host capability | A2 | 必须 |
| CP-ISO-001 | fork/context isolation 行为 | host capability | A2/B2 | 必须 |
| CP-HOOK-001 | SubagentStart-equivalent hook 是否可用 | host capability | A2 | 条件 |
| CP-HOOK-002 | hook additional context 是否真实抵达 child | host capability | A2/B3 | 条件 |
| CP-LIFE-001 | native wait/callback | host capability | A2/B2 | 必须 |
| CP-LIFE-002 | native cancel | host capability | A2/B4 | 必须 |
| CP-MSG-001 | initial plaintext assignment | host capability | B2 | 必须 |
| CP-MSG-002 | follow-up plaintext transport | host capability | B2 | 产品需要时 |

每次 A2/B2 基线运行都生成 `docs/evidence/codex-capability/` 证据。失败的 probe 也是有效结果，但不得被解释为 supported。

## 5. Hook Handoff Protocol

Hook 只有在 B2 evidence 证明 native spawn/lifecycle 可用、task delivery 被阻断时才实现。

测试使用两组 fixture：

1. 进程内 deterministic claim store，用于状态机、TTL、nonce、identity、replay 的快速契约测试；
2. 真实临时文件系统 fixture，用于锁竞争、原子 claim/rename、并发 consumer、损坏 state quarantine。

| ID | 用例 | Fixture | Phase | Gate |
|---|---|---|---|---|
| HH-NONCE-001 | nonce/marker 唯一且匹配 | 两者 | B3 | 必须 |
| HH-TTL-001 | expired envelope 不可消费 | 两者 | B3 | 必须 |
| HH-CLAIM-001 | atomic claim 只有一个 winner | filesystem | B3 | 必须 |
| HH-ONCE-001 | 已消费 envelope 不可再次使用 | 两者 | B3 | 必须 |
| HH-CONC-001 | 并发 consumers 不发生双消费 | filesystem | B3 | 必须 |
| HH-QUAR-001 | malformed/corrupt state 被 quarantine | filesystem | B3 | 必须 |
| HH-REPLAY-001 | replay 被拒绝 | 两者 | B3 | 必须 |
| HH-ID-001 | worker/consumer identity mismatch 被拒绝 | 两者 | B3 | 必须 |
| HH-LIFE-001 | Hook 只交付 assignment，不接管 callback/lifecycle | host + protocol | B3 | 必须 |

## 6. DeepSeek Native Provider

| ID | 用例 | 类型 | Phase | Gate |
|---|---|---|---|---|
| DS-CONFIG-001 | agent role + provider overlay 可解析 | deterministic | B1 | 必须 |
| DS-SECRET-001 | preflight 只检查 credential presence，不输出值 | deterministic | B1 | 必须 |
| DS-OWN-001 | install/uninstall 只操作 pack-owned state | deterministic/filesystem | B1 | 必须 |
| DS-MAIN-001 | install 不改变主 Agent provider/model | deterministic | B1 | 必须 |
| DS-SPAWN-001 | UI/tool event 出现独立 worker id | paid native smoke | B4 | supported gate |
| DS-PROV-001 | child 实际 provider/model 与 manifest 一致 | paid native smoke | B4 | supported gate |
| DS-MSG-001 | deterministic random marker 完整抵达 child | paid native smoke | B4 | supported gate |
| DS-CALL-001 | native wait/callback 返回确定性结果 | paid native smoke | B4 | supported gate |
| DS-CANCEL-001 | native cancel 可验证 | paid native smoke | B4 | supported gate |
| DS-NOFAKE-001 | 未启动 external CLI / 第二 Codex / SDK bridge | paid/native evidence | B4 | supported gate |
| DS-LEAK-001 | secret 不出现在 diff/log/prompt/hook state/output | paid/native evidence | B4 | supported gate |

## 7. 第二 Provider 架构验收

第二个第三方 provider 是 Worker Runtime Registry 的架构测试，不只是功能扩展：

- 主要新增 manifest、agent/provider config 与 smoke fixture；
- 不新增 DeepSeek-specific core branch；
- 不修改 external-cli Backend Registry 的 CLI contract；
- 共用同一 host adapter、capability schema、transport 与 dispatch policy；
- 若必须修改 core，必须解释是通用 contract 缺口还是 provider 特判，并优先修通用合同。

## 8. 测试所有权

- Thin Relay external-cli：`docs/Archive/thin-relay-v2-sop.md`
- Worker/native-provider：`docs/codex-native-subagent-roadmap.md`
- external-cli registry/build historical invariants：`docs/Archive/platform-architecture-v2.md`
- 本文件：跨文档唯一索引，不复制所有实现细节

发布前应从本矩阵生成或人工核对 phase-specific checklist；任何 `supported native child` 声明都必须能回指到具体 evidence 与本矩阵中的 B4 gate。
