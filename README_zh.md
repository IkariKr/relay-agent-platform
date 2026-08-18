# ⚡ Relay · Codex 多模型子代理与 CLI 执行调度层

<p align="center">
  <a href="README.md">English</a> | <b>简体中文</b>
</p>

> **主模型专注决策规划 🧠 ｜ 子代理与 CLI 负责落地执行 ⚙️**  
> 支持在 Codex 中无缝拉起 DeepSeek、Gemini 原生子代理，一键中继 Claude Code、OpenCode、Antigravity CLI。保持上下文干净，大幅节省 Token 消耗！

[![Tests](https://img.shields.io/badge/Pester%20Tests-152%2F152%20Passing-brightgreen?style=flat-square&logo=powershell)](docs/test-matrix.md)
[![Codex](https://img.shields.io/badge/Codex%20Native-Supported-blue?style=flat-square)](docs/codex-native-subagent-roadmap.md)
[![License](https://img.shields.io/badge/License-MIT-orange?style=flat-square)](LICENSE)

---

## 🎯 为什么需要 Relay？

在日常使用 Codex 进行复杂项目开发时，经常会遇到这几个核心问题：

1. **上下文污染与注意力分散（Attention Dilution）**：单一大模型既要做高层架构拆解，又要在主会话里塞满海量具体代码、控制台报错和调试日志。大量低信息密度的噪音不仅导致 Token 消耗极快，更会稀释大模型的注意力权重，导致后续高层决策时产生遗忘或推理漂移。
2. **缺乏原生高性价比 Subagent 支持**：想要接入便宜又好用的 DeepSeek、Gemini 等第三方模型充当打工子代理，手写配置繁琐且缺乏官方标准支持。
3. **跨 CLI 工具调度割裂**：想临时调用 Claude Code、OpenCode 或 Antigravity CLI 协助跑特定任务，各工具间参数不通、环境割裂、输出难以规范收集。

> 💡 **Relay 提供统一的 Worker Runtime 调度层：**  
> 将具体任务委派给第三方原生子代理或外部 CLI 工具执行，主模型仅接收精简摘要与最终产物。**避免低信噪比细节污染主上下文，保持大模型注意力始终聚焦在全局设计与决策上，同时大幅降低 Token 成本！**

---

## ✨ 核心能力一览

### 1️⃣ 🧬 Codex 原生 Native-Provider（子代理）
- **真·原生通信**：基于 Codex 原生 `spawn_agent` / `wait` / `send_input` 机制，无需 Hook 或侵入式修改。
- **高性价比模型即插即用**：零门槛接入 **DeepSeek-V4**、**Gemini-3.7** 等第三方模型作为专属 Subagent，重活累活交给子代理，主模型专注高层审查。

### 2️⃣ 🚀 外部 CLI 统一中继（External-CLI）
- **多后端无缝调用**：一条统一入口直接调起 **Claude Code**、**OpenCode**、**Antigravity** 原生 CLI。
- **透明日志与状态流转**：实时增量日志镜像、命令与退出码原汁原味透传，排错轻松明了。

### 3️⃣ 🛡️ 安全与配置隔离
- **凭据标准注入**：API Key 通过安全管道（stdin）传入并自动做 Token 级脱敏，防止凭证泄漏到历史命令行与本地日志。
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
- Model ID: deepseek-v4-flash
- API Key: <你的 API Key>
```

#### 方式 B：使用命令行手动配置
通过标准输入安全注入密钥（API Key 走标准输入，不留痕）：
```powershell
# 1. 查看可用 Worker 列表
.\scripts\relay.ps1 worker list

# 2. 安全配置 Provider
"sk-your-api-key" | .\scripts\relay.ps1 worker configure deepseek-v4-flash --base-url "https://xxx.example.com/v1" --model "deepseek-v4-flash"

# 3. 运行健康检查验证连通性
.\scripts\relay.ps1 worker doctor deepseek-v4-flash
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

> 💡 **使用建议**：在 Codex 中**强烈推荐直接使用 `relay-agent`（或直接 @relay）**，享受自动路由与原生 Subagent + CLI 的全能调度能力。三个单后端包默认直接调用底层原生 CLI。

| Skill 包名 | 默认执行模式 | 定位与适用场景 |
| :--- | :--- | :--- |
| 👑 **`relay-agent`** | **智能双引擎（推荐 ⭐⭐⭐⭐⭐）** | **统一调度总入口**：支持 Worker 注册管理、自动路由，可按需拉起 Native 原生子代理或 External-CLI 极速执行 |
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
                         ▼ 仅返回摘要与执行产物
             【 Codex 主模型复核与验收 】
```

---

## ⚠️ 使用须知与限制说明

在使用 **External-CLI（外部命令行模式）** 时，请留意以下几点：

1. 🔑 **需提前完成 CLI 登录认证**：
   - 首次使用外部后端（Claude Code / OpenCode / Antigravity）前，请确保已在终端对应工具中完成登录或环境凭据配置。
   - 若未登录，CLI 会直接报错或提示认证缺失，Relay 会原样捕获并提醒你先完成对应 CLI 的登录。
2. 🙈 **CLI 模式无法查看内部思考过程（CoT）**：
   - External-CLI 属于黑盒式极速执行中继，主会话仅能实时捕获该命令的标准输出、错误日志与退出状态，**无法看到底层模型未公开的内部推理/思考过程（Thinking Tokens）**。
   - 如需查看完整的推理交互和多轮会话上下文，推荐使用 **Native-Provider（原生子代理模式）**。

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
  <sub>#AI编程 #Codex #Subagent #ClaudeCode #DeepSeek #Gemini #开发效率 #Token优化</sub>
</p>
