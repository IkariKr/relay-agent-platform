# ⚡ Relay · Codex 多模型子代理与 CLI 执行调度层

<p align="center">
  <a href="README.md">English</a> | <b>简体中文</b>
</p>

> **主模型专注决策规划 🧠 ｜ 子代理与 CLI 负责落地执行 ⚙️**  
> 支持在 Codex 中分流至已验证的原生子代理（如 DeepSeek-V4），一键中继 Claude Code、OpenCode、Antigravity CLI。有效减缓主上下文膨胀！

[![Tests](https://img.shields.io/badge/Pester%20Tests-152%2F152%20Passing-brightgreen?style=flat-square&logo=powershell)](docs/test-matrix.md)
[![Codex](https://img.shields.io/badge/Codex%20Native-Supported-blue?style=flat-square)](docs/codex-native-subagent-roadmap.md)
[![License](https://img.shields.io/badge/License-MIT-orange?style=flat-square)](LICENSE)

---

## 🎯 为什么需要 Relay？

在日常使用 Codex 进行复杂项目开发时，经常会遇到这几个核心问题：

1. **上下文污染与注意力分散（Attention Dilution）**：单一大模型既要做高层架构拆解，又要在主会话里塞满海量具体代码、控制台报错和调试日志。大量低信息密度的噪音会稀释大模型的注意力权重，导致后续高层决策时产生遗忘或推理漂移。
2. **缺乏标准第三方 Subagent 接入途径**：想要接入便宜好用的第三方 Responses-compatible 模型充当打工子代理，手写配置繁琐且缺乏官方统一标准。
3. **跨 CLI 工具调度割裂**：想临时调用 Claude Code、OpenCode 或 Antigravity CLI 协助跑特定任务，各工具间参数不通、环境割裂、输出难以规范收集。

> 💡 **Relay 提供统一的 Worker Runtime 调度层：**  
> 将具体任务委派给原生子代理或外部 CLI 工具执行，主模型负责审查与最终验收。**避免低信噪比细节污染主上下文，有效减缓主会话上下文的不必要增长！**

---

## ✨ 核心能力一览

### 1️⃣ 🧬 Codex 原生 Native-Provider（子代理）
- **原生通信协议**：基于 Codex 原生 `spawn_agent` / `wait` / `send_input` 机制，无需 Hook 或侵入式修改。
- **Provider Pack 扩展支持**：**DeepSeek-V4** 已在特定 Codex/Provider/Model 组合下完成真实 Native Child 全链路验证；**Gemini-3.7** 等 Worker Pack 已就绪并支持运行时验证。

### 2️⃣ 🚀 外部 CLI 统一中继（External-CLI）
- **多后端无缝调用**：一条统一入口直接调起 **Claude Code**、**OpenCode**、**Antigravity** 原生 CLI。
- **透明日志与状态流转**：实时增量日志镜像、命令与退出码原汁原味透传，排错轻松明了。

### 3️⃣ 🛡️ 安全与配置隔离
- **凭据标准注入**：支持交互式 Masked 录入或安全 `--api-key-stdin` 管道，自动做 Token 级脱敏，防止凭证泄漏到历史命令行与本地日志。
- **统一 Worker 注册表**：通过标准 Worker Pack 扩展模型，开箱即用，支持一键健康体检（`worker doctor`）。

---

## 🚀 3 分钟极速上手

### 1. 安装到 Codex
在 Codex 中直接发送：
```text
请帮我在 Codex 里安装这个 GitHub 项目：https://github.com/IkariKr/relay-agent-platform
```

*(或者在本地仓库一键生成并挂载 Skill)*
```powershell
.\scripts\build-packages.ps1
.\scripts\install-workspace-skill-links.ps1
```

---

### 2. 配置 Worker（以 DeepSeek 为例）

#### 方式 A：在 Codex 中直接发送（最推荐，零命令负担）
直接在 Codex 对话框中发送如下内容，Codex 将自动调用 Relay 协议完成安全配置与健康检查：
```text
帮我把 DeepSeek 配置为 Relay 的原生子代理：
- Base URL: https://xxx.example.com/v1
- Model ID: deepseek-v4-flash-response
- API Key: <你的 API Key>
```

#### 方式 B：使用命令行手动配置（交互式安全录入）
先写入配置元数据，再通过交互式 Masked 命令行录入密钥：
```powershell
# 1. 写入 Worker 配置元数据
.\scripts\relay.ps1 worker configure deepseek-v4-flash `
  --profile default `
  --base-url "https://xxx.example.com/v1" `
  --model "deepseek-v4-flash-response" `
  --non-interactive --json

# 2. 安全录入凭证（交互式隐藏输入，不留命令历史）
.\scripts\relay.ps1 worker credential set deepseek-v4-flash --profile default

# 3. 运行健康检查验证连通性
.\scripts\relay.ps1 worker doctor deepseek-v4-flash --profile default
```

---

### 3. 开始使用

#### 场景 A：创建原生 Subagent 分流任务（保持主上下文干净）
在 Codex 中对主模型说：
```text
请创建一个 DeepSeek 子代理，帮我补齐这个模块的所有单元测试，完成后向我汇报结果。
```

#### 场景 B：使用外部 CLI 执行特定任务
在 Codex 中对主模型说：
```text
请调用 OpenCode CLI（使用 deepseek-v4-flash-free 模型），帮我分析当前项目的依赖并生成报告。
```
或者指定其他 CLI 执行：
```text
请调用 Claude Code CLI 帮我重构这个工具函数。
```

---

## 📦 家族 Skill 模块一览

> 💡 **使用建议**：在 Codex 中**强烈推荐直接使用 `relay-agent`（或直接 @relay）**。Relay 明确区分 Native 子代理派发与 External-CLI 中继两条路径；原生自动派发采取保守策略，存在歧义时自动 fail closed 提示用户。

| Skill 包名 | 默认执行模式 | 定位与适用场景 |
| :--- | :--- | :--- |
| 👑 **`relay-agent`** | **双路径分流（推荐 ⭐⭐⭐⭐⭐）** | **统一调度总入口**：支持 Worker 注册管理、保守派发，可按需拉起 Native 原生子代理或 External-CLI 极速执行 |
| 🟣 **`relay-claude`** | **默认原生 CLI (`claude`)** | **Claude Code 专用包**：专为 Claude Code CLI 调优的极简薄执行层，直接透传命令给 `claude` CLI |
| 🟢 **`relay-opencode`** | **默认原生 CLI (`opencode`)** | **OpenCode 专用包**：直接调用 `opencode run` 命令行工具的专用中继通道 |
| 🔵 **`relay-antigravity`** | **默认原生 CLI (`antigravity`)** | **Antigravity 专用包**：直接调用 `antigravity` 原生命令行工具的专用接入通道 |

---

## 🏗️ 架构设计

```text
       【 你的业务需求 】
               │
               ▼
       ┌───────────────┐
       │  Codex 主模型 │ ── (任务拆解 / 架构设计 / 保持干净上下文)
       └───────┬───────┘
               │ 派发子任务
       ┌───────▼───────────────────────────┐
       │   Relay Worker Runtime Registry   │
       └───────┬───────────────────┬───────┘
               │                   │
   [ Native-Provider ]      [ External-CLI ]
               │                   │
  ┌────────────▼────────────┐ ┌────▼─────────────────────────┐
  │ Codex Native Subagent   │ │ Thin Relay CLI Wrapper       │
  │ (DeepSeek / Gemini ...) │ │ (Claude / OpenCode / Anti..) │
  └────────────┬────────────┘ └────┬─────────────────────────┘
               │                   │
               └─────────┬─────────┘
                         ▼ 返回原始执行输出与产物供主模型审查
             【 Codex 主模型复核与验收 】
```

---

## ⚠️ 使用须知与限制说明

在选用不同执行模式时，请留意以下几点：

1. 🔑 **External-CLI 需提前完成登录认证**：
   - 首次使用外部后端（Claude Code / OpenCode / Antigravity）前，请确保已在终端对应工具中完成登录或环境凭据配置。
   - 若未登录，CLI 会直接报错或提示认证缺失，Relay 会原样捕获并提醒你先完成对应 CLI 的登录。
2. 🙈 **内部推理过程（CoT）可见性**：
   - External-CLI 属于薄中继层，转发原始输出与退出状态，无法看到未公开的底层模型内部思考过程（Thinking Tokens）。
   - 如需利用 Codex 原生管理的子代理生命周期、进度可见性与 Provider 隔离，请选用 **Native-Provider 模式**。

---

## 🤝 参与贡献与问题反馈

如果你在使用过程中遇到了 Bug、有新的 Worker 模型需求或优化建议，欢迎交流与贡献！

- 🐛 **提交 Issue**：遇到任何报错、兼容性问题或异常退出，请前往 [GitHub Issues](https://github.com/IkariKr/relay-agent-platform/issues) 提交反馈，附带复现步骤与日志。
- 💡 **提交 PR (Pull Request)**：想接入更多 Provider Pack 或改进 Relay 调度器？欢迎 Fork 本仓库并提交 Pull Request，共同完善生态！

---

## 📚 进阶文档

- 🗺️ **[Codex 原生子代理路线图](docs/codex-native-subagent-roadmap.md)**：深入了解 Codex Collab 协议对接与验证细节。
- 🧪 **[自动化测试矩阵](docs/test-matrix.md)**：152 项 Pester 自动化测试与覆盖指标。
- 📦 **[历史文档与 SOP 归档](docs/Archive/)**：安装配置、架构演进与故障排查手册。

---

<p align="center">
  <sub>#AI编程 #Codex #Subagent #ClaudeCode #DeepSeek #Gemini #开发效率 #上下文管理</sub>
</p>
