# Codex Delegate Claude

先说结论：如果你想让 Codex 负责拆解任务、审查结果、跑验证、控制提交，同时把真正的实现工作交给 Claude Code 或 OpenCode，这个仓库就是给你用的。

它不是“让代理自己随便跑”的那一类工具，而是一个更稳的委托工作流：

- Codex 定义目标和边界
- Worker 负责做一轮受约束的实现
- Codex 回来检查 diff、跑验证、决定是否重试
- 最后只有 Codex 会决定要不要提交

这套方式特别适合两种人：

- 想提高实现速度，但不想把代码质量和提交权直接放手的人
- 已经在用 Codex / Claude Code，但希望把“代理执行”这件事做得更可控的人

## 这个仓库到底解决什么问题

很多代理工作流卡在两个地方：

1. 代理改得很快，但 scope 很容易飘
2. 改完之后没有一个稳定的 review 和 verification 闭环

`codex-delegate-claude` 的核心思路很直接：

- 把“执行”交给后端
- 把“判断”留给 Codex
- 用脚本把超时、重试、路由和安装流程收敛成可复用能力

你可以把它理解成一个面向 Codex 的“受控代理执行层”。

## 适合谁用

如果你经常遇到下面这些场景，这个仓库会很顺手：

- 你想让 Claude Code 帮你落地代码，但不想让它直接 commit
- 你希望一个统一入口，根据任务自动选择 Claude 或 OpenCode
- 你想先 `-WhatIf` 看看路由结果，再决定是否真跑
- 你在维护自己的技能仓库，想把共享逻辑、后端适配和可安装包拆清楚

如果你只想“一条命令直接让代理全自动改完并提交”，那它反而不是为这个目标设计的。

## 3 分钟上手

### 路线 A：推荐的统一入口

```powershell
Set-Location .\packages\codex-delegate-agent
.\scripts\run_delegate_agent.ps1 -Prompt "Review this API design and point out risks." -Backend auto -WhatIf
```

这条命令适合第一次体验：

- 走 `v1` 推荐路径
- 先让路由系统告诉你它会选谁
- 不真实调用后端，不花额外执行成本

### 路线 B：明确指定 Claude

```powershell
Set-Location .\packages\codex-delegate-agent
.\scripts\run_delegate_agent.ps1 -Prompt "Review this refactor plan in detail." -Backend claude -WhatIf
```

适合你明确知道这次就要走 Claude 的情况。

### 路线 C：明确指定 OpenCode

```powershell
Set-Location .\packages\codex-delegate-agent
.\scripts\run_delegate_agent.ps1 -Prompt "Make a quick fix in this small module." -Backend opencode -WhatIf
```

适合偏本地、偏快速、小任务修复的执行场景。

## 我最推荐的使用姿势

别一上来就真跑，先按下面这个节奏：

1. 先用 `run_delegate_agent.ps1 -WhatIf` 看路由
2. 再用 `manage_auto_routing.ps1 -Action list` 看规则
3. 用 `manage_auto_routing.ps1 -Action explain` 验证某条 prompt 为什么这么分流
4. 确认没问题后，再去掉 `-WhatIf` 跑真实任务

这样做的好处很实际：

- 安装问题会更早暴露
- 路由判断更透明
- 真正执行前你就能知道风险点

## 仓库里有什么

这不是一个只有单脚本的小仓库，它已经分成了几层：

- `shared/`
  共享文档和公共 PowerShell 逻辑
- `backends/`
  各后端自己的元数据、脚本和行为说明
- `packages/codex-delegate-agent/`
  推荐使用的统一多后端包
- `packages/codex-delegate-opencode/`
  OpenCode 专用包
- `scripts/build-packages.ps1`
  用来重新生成安装包内容
- `scripts/validate-packages.ps1`
  用来校验生成结果是否一致

如果你是使用者，重点看 `packages/`。

如果你是维护者，重点看 `shared/`、`backends/` 和 `scripts/`。

## 安装建议

推荐的维护者路径是把整个仓库直接放进 Codex skills 目录，然后构建生成包：

```powershell
.\scripts\build-packages.ps1
.\scripts\install-workspace-skill-links.ps1
```

这样你会同时拿到：

- `codex-delegate-claude`
- `codex-delegate-agent`
- `codex-delegate-opencode`

如果你只是单纯想用，也可以直接复制生成好的 package。

更完整的安装说明在：

- [docs/installation.md](docs/installation.md)

## 推荐阅读顺序

如果你不想一口气把文档全看完，可以按这个顺序读：

1. [docs/quickstart.md](docs/quickstart.md)
2. [docs/package-selection.md](docs/package-selection.md)
3. [docs/routing-guide.md](docs/routing-guide.md)
4. [docs/troubleshooting.md](docs/troubleshooting.md)

如果你是维护者，再继续看：

- [docs/architecture.md](docs/architecture.md)
- [docs/release-checklist.md](docs/release-checklist.md)
- [docs/v1.0.0-release-notes.md](docs/v1.0.0-release-notes.md)

## 一句话理解这套仓库

不是让代理失控地“自己写完一切”，而是把代理变成一个可审查、可验证、可回滚、可路由的执行层。

如果你喜欢“先把边界说清楚，再把速度拉起来”的工作方式，这个仓库大概率会合你胃口。
