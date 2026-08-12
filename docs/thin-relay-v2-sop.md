# Thin Relay v2 演进 SOP

> 状态：提案 / 实施标准  
> 适用范围：Relay 的统一入口、Claude、OpenCode、Antigravity 三类后端及其模型选择。  
> 核心目标：保留多后端、多模型的统一价值，同时确保 Relay 不会削弱后端原生 CLI 与模型能力。

## 1. 背景与问题

Relay 需要同时支持：

- OpenCode 及其可用模型；
- Claude Code 及其可用模型；
- Antigravity 及其可用模型。

现有实现将路由、配置合并、模型意图评分、超时和空闲判定、自动重试、Git 状态轮询、JSONL 解析与伪进度汇报串在同一条执行路径中。这会带来额外故障点，并可能造成以下问题：

- 用户显式指定的模型或 agent 被中间层覆盖、拒绝或难以追踪；
- 后端 CLI 新增参数或能力时，必须等待 Relay 适配；
- 临时目录或非 Git 工作区触发无关错误；
- JSONL 解析、伪进度或重试行为遮蔽真实的后端输出和失败原因；
- 对于一次性问答、调研或简单执行，Relay 的复杂度超过直接调用原生 CLI。

## 2. 产品定位

Relay v2 是**薄型、多后端执行层**，不是替代后端 CLI 的自动驾驶编排器。

它负责：

- 用一套稳定的 Relay 接口选择后端；
- 以最小映射构造并执行对应原生命令；
- 可选地提供配置默认值、路由解释和原始日志保存。

它不负责：

- 猜测用户应使用哪个模型、agent 或工具；
- 在默认执行路径中改写、筛选或降级用户显式参数；
- 承担墙钟或空闲超时、自动重试、Git 检查、测试或提交；
- 解析 JSONL 以生成摘要或伪进度；
- 依赖解析模型输出才能判定后端调用是否成功。

## 3. 不可违背的设计原则

### 3.1 原生命令优先

每次 `relay run` 都必须打印最终将执行的、可复制的原生命令（敏感值脱敏）。用户应能脱离 Relay 直接运行该命令，并得到等价的后端行为。

### 3.2 显式参数优先

命令行中的 `backend`、`model`、`agent`、prompt 和透传参数拥有最高优先级。Relay 不得基于 intent、价格、可用性评分或启发式规则替换显式模型。

### 3.3 一次调用、原样结果

默认仅调用后端一次；实时转发 stdout/stderr；保留后端原始退出码。成功与失败均以原生 CLI 结果为准。

### 3.4 高级能力显式启用

自动路由必须显式通过 `relay route run` 启用；Relay 不提供墙钟/空闲超时、自动重试、Git 轮询、JSONL 摘要解析或伪进度汇报。

### 3.5 配置只补默认值

工作区和用户配置只在命令行缺少对应参数时提供默认值。配置加载、合并应在内存完成；不为正常执行创建临时配置文件。

### 3.6 后端能力不设上限

Relay 应提供原生参数透传机制。任何后端新增的 CLI 参数，都应能在 Relay 未发布新版本时被使用。

## 4. 目标命令面

优先将公开执行面收敛为一个命令和两个独立的辅助命令：

```powershell
# 默认：薄执行路径。backend 必填，避免隐藏路由。
relay run --backend opencode --model opencode/deepseek-v4-flash-free --agent build -- "查询今天上海天气"

# 显式请求路由建议或执行路由。
relay route explain -- "请快速修复一个本地 TypeScript 问题"
relay route run -- "请实现这个功能"

# 显式诊断后端可用性与原生命令。
relay doctor --backend opencode
```

为降低迁移成本，现有 PowerShell 脚本可先保留为兼容入口，但它们最终应只转调同一个核心执行器，而不是各自维护一套执行逻辑。

### 4.1 最小公共参数

`relay run` 仅长期承诺以下跨后端参数：

| 参数 | 含义 | 规则 |
|---|---|---|
| `--backend` | `opencode`、`claude` 或 `antigravity` | 必填；`auto` 不是 `run` 的合法值，自动选择只能使用 `route run`。 |
| `--model` | 后端原生模型标识 | 原样传递；未提供时才读取配置默认值或使用后端默认。 |
| `--agent` | 后端原生 agent / profile | 原样传递；未提供时不由 Relay 猜测。 |
| `--workdir` | 后端运行目录 | 默认当前目录；不要求其必须是 Git 仓库。 |
| `--` | 后续 prompt | 原样传递，保持用户文本。 |
| `--passthrough <token>` | 后端特有参数 | 严格消费紧随的单个 token，且不将其解释为 Relay 参数；允许重复使用。 |

例如：

```powershell
relay run --backend opencode --model opencode/deepseek-v4-flash-free `
  --passthrough --auto --passthrough --format --passthrough json `
  -- "只读查询今天上海天气"
```

带值的原生选项使用两次 `--passthrough`，例如 `--passthrough --file --passthrough README.md`。适配器必须将公共参数映射后的参数与全部透传参数置于原生 CLI 的 prompt 分隔符（例如 `--`）及 prompt **之前**；不得简单追加到 prompt 之后。这样可以避免后端将透传参数误当成 prompt 文本的一部分。契约测试必须覆盖与 Relay 自身参数同名的透传 token，例如 `--passthrough --model`。

实现时也可提供更自然的 `relay opencode -- <原生参数>` 别名；该别名应尽可能等价于直接运行 `opencode`。

### 4.2 可选执行控制

以下功能必须显式指定，且不能改变默认的原始输出语义：

| 参数 / 子命令 | 行为 |
|---|---|
| `--log-dir <path>` | 将未经改写的 stdout/stderr 写入文件，同时继续实时输出。 |
| `--dry-run` | 不启动后端；打印构造后的脱敏原生命令，成功退出。 |

`--dry-run` 不检查或启动后端 CLI，其成功仅表示命令构造成功。Relay 不自行中止 worker，也不以输出间隔推断 worker 卡住；任务生命周期、持续观察和人工干预由 Codex 主代理或原生 subagent 管理。

## 5. 参数与配置优先级

优先级从高到低如下：

1. `relay run` 命令行参数；
2. 仅本次进程使用的环境变量（若保留）；
3. 工作区 `.relay-agent/backends/<backend>.json`；
4. 用户级 Relay 配置；
5. 后端原生 CLI 默认值。

配置文件仅允许声明默认值，例如 `default_model`、`default_agent`、`default_passthrough`。不得通过配置强制覆盖命令行的显式参数。

每次执行应以可读形式显示“参数来源”，例如：

```text
backend: opencode (command line)
model: opencode/deepseek-v4-flash-free (command line)
agent: build (workspace default)
```

## 6. 后端适配器实施规范

每个后端仅保留一个轻量适配器。适配器的职责限于：

1. 检查对应 CLI 是否存在；
2. 将公共参数映射为该 CLI 的原生参数；
3. 追加用户透传参数；
4. 启动子进程，并原样转发 stdout/stderr 与退出码；
5. 返回命令构造结果供 `--dry-run`、原始日志和测试使用。

适配器不得：

- 拉取或评分模型列表；
- 自动选择 `agent`；
- 写入临时 JSON 配置；
- 解析 JSONL 生成摘要、进度或成功判断；
- 执行 Git 命令；
- 启动墙钟或空闲计时器，或重试完整 prompt。

后端特有参数应由 `--passthrough` 处理，而非为每个新参数修改 Relay 公共接口。

## 7. 路由 SOP

自动路由保留，但从默认路径移出。

### 7.1 路由规则

- 仅在 `relay route run` 下启用；`relay run` 必须使用具体 backend；
- 规则为可读的有序表，首个匹配规则生效；
- 不使用不透明评分和模型意图推断；
- 路由只选择 backend，默认不选择或改写 model；
- 路由结果必须输出匹配规则、理由、可用 fallback 以及最终原生命令；
- `relay run` 中的具体 `--backend` 不经过路由，任何路由规则都无权覆盖它。

### 7.2 失败处理

- 明确指定的 backend 不可用：直接失败，显示原生 CLI 安装/诊断建议；
- 自动路由的 backend 不可用：仅按显式配置的 fallback 顺序尝试，并完整输出原因；
- fallback 不得静默切换到不同的付费模型或供应商。

## 8. 原始输出与任务生命周期 SOP

- Relay 默认实时转发后端原始 stdout/stderr，不解析 JSONL，也不将输出改写为摘要或进度；
- 可选 `--log-dir` 仅镜像保存两个原始日志文件和一份不含密钥的命令清单；
- 日志路径、后端 session id（若其原始输出提供）和最终退出码应在结尾打印；
- Relay 自身错误必须清楚标注为 Relay 层错误，并与后端 stderr 分开显示；
- Relay 不执行 Git 命令，也不轮询 Git 状态；变更审查、测试和提交属于 Codex 主代理或原生 subagent；
- Relay 不自行中止 worker，不做空闲判定，也不自动重试；
- 复杂或长时间任务应由 Codex 原生 subagent 发起外部 worker 调用。Codex 负责显示执行过程、维持任务上下文、决定继续或中止；Relay 仅执行一条原生命令并返回结果。

## 9. 验收标准与测试矩阵

每次修改执行器或后端适配器，都必须满足以下标准：

### 9.1 命令构造契约测试

为 Claude、OpenCode、Antigravity 分别覆盖：

- 显式 backend、model、agent 和 prompt 生成预期原生命令；
- 所有 `--passthrough` 参数保持顺序且没有丢失，并位于 prompt 分隔符之前；
- `--passthrough` 严格消费一个 token；与 Relay 参数同名的原生 token 不得被重新解释；
- 配置仅补齐缺失值，不覆盖命令行值；
- `--dry-run` 展示的命令与实际执行命令一致；
- `--dry-run` 不启动或检查后端 CLI，命令构造成功时退出 `0`；
- 不可用 CLI、无效 backend（包括 `auto`）和缺失 prompt 给出明确的 Relay 错误；
- Relay 不启动超时/空闲计时器，不触发第二次调用，也不执行 Git 命令。

### 9.2 端到端 Smoke Test

每个已安装后端至少保留一条只读、无文件修改的 smoke test，例如：

```text
请使用可用联网工具查询今天上海天气；无法可靠获取时明确说明原因；不得修改文件。
```

验收：

- 原生 CLI 直接调用成功时，等价的 `relay run` 必须成功；
- Relay 的退出码必须等于后端原始退出码；
- 模型和 agent 与用户显式指定的完全一致；
- 不依赖 Git 仓库；
- 原始模型输出可见并可在原始日志中复查；
- 执行期间 Relay 不会生成 JSONL 摘要、伪进度、Git 状态或自动重试。

### 9.3 核心质量门槛

> 对用户显式指定的 backend、model、agent 和参数，Relay 的成功率不得低于直接运行对应原生 CLI；失败时必须输出可复制的原生命令和原始错误。

## 10. 迁移实施步骤

### Phase 0：冻结复杂度并建立基线

1. 记录当前三种 backend 的直接 CLI smoke test 结果；
2. 记录相同请求经现有 Relay 执行的结果、耗时和错误；
3. 为现有脚本补齐命令构造测试，先锁定行为再重构；
4. 删除墙钟/空闲超时、自动重试、Git 状态轮询、JSONL 摘要解析和伪进度汇报；不再新增同类能力。

### Phase 1：实现薄核心

1. 建立单一核心执行器与三个轻量适配器；
2. 实现 `relay run`、`--dry-run`、`--passthrough`、实时输出和原始退出码转发；
3. 让 `relay run --backend opencode ...` 的原生命令与直接 `opencode run ...` 一一对应；
4. 通过三后端命令构造契约测试和可用后端 smoke test。

### Phase 2：迁移可选能力

1. 将配置合并改为内存处理并输出来源；
2. 将路由移至 `relay route`；
3. 保留可选原始日志镜像，不对输出作语义解析；
4. 确保核心路径没有计时器、重试、Git 命令或额外配置文件写入。

### Phase 3：兼容与弃用

1. 旧脚本继续可运行，但打印迁移提示，并内部调用薄核心；
2. 保留一个稳定版本周期的兼容层；
3. 文档、skill prompt 和示例全部改为 `relay run`；
4. 在弃用周期后删除重复的 wrapper、重复模型选择、计时/重试、Git 轮询、JSONL 解析和伪进度代码。

## 11. 发布检查清单

- [ ] 三个 backend 的直接 CLI 与 `relay run` 均完成最小 smoke test；
- [ ] `--dry-run` 命令可直接复制执行；
- [ ] 显式 `--model` / `--agent` 未被配置或路由覆盖；
- [ ] `--passthrough` 保持顺序并覆盖后端新增参数场景；
- [ ] 无 Git 仓库的工作目录可正常运行；
- [ ] 默认执行仅一次，无墙钟/空闲超时、自动重试、Git 轮询、JSONL 解析或伪进度；
- [ ] 原始 stdout/stderr 与退出码可完整复查；
- [ ] 路由与原始日志镜像可独立启用和关闭；
- [ ] 旧入口具有明确的弃用提示和迁移示例。

## 12. 维护决策准则

评审任何 Relay 新功能时，先问三个问题：

1. 这项能力是否会改变用户直接运行后端 CLI 的结果？
2. 这项能力能否作为显式开关或独立子命令，而不是默认链路的一部分？
3. 后端明天增加新模型或参数时，用户是否无需等待 Relay 更新即可使用？

只要任一答案不理想，应优先选择更薄、更透明的实现。
