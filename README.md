# Relay

> Relay is the new name for the former `codex-delegate-*` skill family.
>
> 把 agent 变成可控执行层，而不是失控自动驾驶。

如果你也有这种感觉:

- 想让 agent 干活更快
- 但又不想把 review、验证、提交权一起交出去
- 还希望不同后端能统一接入、统一路由、统一管理

那这个仓库大概率就是你要找的东西。

`Relay` 不是“让代理自己一路改到天亮”的全自动脚本，它更像一个面向 Codex 的委托平台:

- Codex 负责拆解任务、收紧边界、复核结果
- Claude / OpenCode / Antigravity 负责做一轮有约束的实现
- 最后由 Codex 决定要不要重试、验证、提交

这里的 `Codex`，指的是你当前使用的 Codex / CodeX 主控端。

一句话说，`Relay` 是一套把“代理执行”做成可审查、可验证、可回滚、可路由流程的基础设施。

## 这个项目到底在解决什么

很多 agent 工作流的真实痛点，不是“模型不够聪明”，而是这两件事:

1. 改得很快，但 scope 很容易飘
2. 改完之后，没有稳定的 review 和 verification 闭环

`Relay` 的思路非常直接:

- 把执行交给后端
- 把判断留给 Codex
- 把路由、重试、安装、包装、共享逻辑收敛成可维护的脚本和 package

它的工作流大致是这样:

```text
[ 你的需求 ]
    |
    v
[ Codex 总控 ]
    |  拆解任务、设置边界、选择后端
    v
[ Relay 路由 ]
    |--> relay-claude
    |--> relay-opencode
    `--> relay-antigravity
           |
           v
      [ 返回实现结果 ]
           |
           v
[ Codex 复核 ]
    |  决定接受、重试、验证或打回
    v
[ 最终结果 ]
```

所以它更适合认真做工程的人，而不是只追求“一条命令全自动提交”的玩法。

## 给使用者

如果你属于下面这些场景，`Relay` 会很顺手:

- 你想让 Claude Code 落地实现，但不想让它直接 commit
- 你想统一接入多个 worker，而不是每个后端各玩各的
- 你希望把不同后端统一成一套稳定入口

如果你要的是“代理自己改、自己测、自己提交、自己收尾”，那它就不是按这个产品哲学设计的。

### 先记住这个定位

`Relay` 现在提供的是一套多后端委托能力:

- `relay-agent`
  默认推荐的统一入口，支持自动路由和显式后端选择
- `relay-claude`
  只走 Claude 的专用包
- `relay-opencode`
  只走 OpenCode 的专用包
- `relay-antigravity`
  只走 Antigravity CLI 的专用包

如果你是第一次接触，直接从 `relay-agent` 开始就对了。

### 3 分钟感受一下

下面这几句，都是直接发给 Codex 对话框的。

1. 安装

```text
请帮我在 Codex 里安装这个 GitHub 项目：https://github.com/IkariKr/relay-agent-platform
```

2. 使用

```text
/relay
```

Codex 会走默认统一入口，按当前配置选择后端，然后开始这一轮委托执行。

3. 指定 Claude

```text
/relayclaude
```

Codex 会直接走 Claude 这条后端链路。

如果你想把边界收得更紧，也支持继续补参数，比如 `backend`、`model`、`prompt`。

### 使用者继续往下看

- [docs/quickstart.md](docs/quickstart.md)
- [docs/package-selection.md](docs/package-selection.md)
- [docs/troubleshooting.md](docs/troubleshooting.md)

## 给维护者

如果你不是单纯想使用它，而是准备继续扩后端、改路由、调打包、做发布，那从这里开始看。

### 仓库结构

这个仓库不是“只有几个脚本拼起来”的一次性产物，它已经拆成了几层:

- `shared/`
  共享文档和公共 PowerShell 逻辑
- `backends/`
  后端元数据、脚本和后端说明
- `packages/relay-agent/`
  统一入口 package
- `packages/relay-claude/`
  Claude package
- `packages/relay-opencode/`
  OpenCode package
- `packages/relay-antigravity/`
  Antigravity package
- `scripts/build-packages.ps1`
  重新生成 packages
- `scripts/validate-packages.ps1`
  校验生成结果

维护时重点看 `shared/`、`backends/`、`scripts/` 和 `docs/`。

### 安装和维护建议

更推荐的维护方式，是把整个仓库放进 Codex skills 目录，然后生成并链接 package:

```powershell
.\scripts\build-packages.ps1
.\scripts\install-workspace-skill-links.ps1
```

这样会得到四个可安装 skill:

- `relay-agent`
- `relay-claude`
- `relay-opencode`
- `relay-antigravity`

如果你只是想快速使用，也可以直接复制已经生成好的 package。

完整安装说明在这里:

- [docs/installation.md](docs/installation.md)

### 维护者推荐阅读顺序

- [docs/installation.md](docs/installation.md)
- [docs/routing-guide.md](docs/routing-guide.md)
- [docs/architecture.md](docs/architecture.md)
- [docs/platform-architecture-v2.md](docs/platform-architecture-v2.md)
- [docs/release-checklist.md](docs/release-checklist.md)

## 最后一句话

`Relay` 不是为了让 agent 更“放飞”，而是为了让多 agent 协作这件事，第一次变得足够可控、可解释、可工程化。

如果你喜欢“边界先说清，再把速度拉满”的工作方式，这个项目应该会很对味。
