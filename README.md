# ⚡ Relay · Codex Multi-Model Subagent & CLI Execution Layer

<p align="center">
  <b>English</b> | <a href="README_zh.md">简体中文</a>
</p>

> **Main Agent focuses on Planning & Decisions 🧠 ｜ Subagents & CLIs handle Execution ⚙️**  
> Seamlessly dispatch to verified Codex native subagents (e.g. DeepSeek-V4) and thin-relay to Claude Code, OpenCode, and Antigravity CLIs. Reduce parent-context bloat for delegated tasks!

[![Tests](https://img.shields.io/badge/Pester%20Tests-152%2F152%20Passing-brightgreen?style=flat-square&logo=powershell)](docs/test-matrix.md)
[![Codex](https://img.shields.io/badge/Codex%20Native-Supported-blue?style=flat-square)](docs/codex-native-subagent-roadmap.md)
[![License](https://img.shields.io/badge/License-MIT-orange?style=flat-square)](LICENSE)

---

## 🎯 Why Relay?

When building complex projects in Codex, developers often face three common challenges:

1. **Context Pollution & Attention Dilution**: A single model handling both high-level system design and low-level code iterations, console errors, and intermediate debug logs can suffer from diluted attention weights, leading to context drift and degraded high-level reasoning.
2. **Lack of Standard Native Subagent Ingestion**: Integrating third-party Responses-compatible providers as worker subagents typically requires tedious manual configuration without standard host support.
3. **Fragmented CLI Workflows**: Switching between Claude Code, OpenCode, or Antigravity CLIs is disjointed—parameter formats differ, environments are isolated, and raw output streams require manual forwarding.

> 💡 **Relay provides a unified Worker Runtime Dispatcher:**  
> Delegate concrete tasks to native subagents or external CLI tools while your main model retains high-level review and final decisions. **Prevent low-signal details from polluting the main context and reduce unnecessary parent-context growth!**

---

## ✨ Key Features

### 1️⃣ 🧬 Codex Native-Provider (Subagent)
- **Native Child Integration**: Built on Codex's native `spawn_agent` / `wait` / `send_input` protocol without custom hooks or monkey-patching.
- **Provider Pack Support**: **DeepSeek-V4** has verified live native-child evidence on specific host/provider/model combinations. Additional packs like **Gemini-3.7** are available and configured for runtime validation.

### 2️⃣ 🚀 Unified External-CLI Relay
- **Multi-Backend Forwarding**: A single unified entrypoint directly triggers **Claude Code**, **OpenCode**, and **Antigravity** native CLIs.
- **Transparent Streaming & Exit Codes**: Real-time incremental log mirroring, raw command forwarding, and accurate exit-code passthrough.

### 3️⃣ 🛡️ Secure Credential & Config Isolation
- **Token-Aware Redaction & Safe Ingestion**: API keys are ingested via interactive masked prompts or secure `--api-key-stdin` pipes and automatically redacted in logs—never leaking secrets to command-line histories or disk files.
- **Standard Worker Registry**: Extensible via declarative Worker Packs, complete with one-click health checks (`worker doctor`).

---

## 🚀 3-Minute Quickstart

### 1. Install into Codex
Send this prompt directly in your Codex chat:
```text
Please help me install this GitHub repository in Codex: https://github.com/IkariKr/relay-agent-platform
```

*(Or build and link skills locally)*
```powershell
.\scripts\build-packages.ps1
.\scripts\install-workspace-skill-links.ps1
```

---

### 2. Configure a Worker (Example: DeepSeek)

#### Method A: Prompt Codex Directly (Recommended ⭐)
Send the following in Codex, and Relay's skill protocol will handle the secure configuration and health check automatically:
```text
Please configure DeepSeek as a Relay native subagent:
- Base URL: https://xxx.example.com/v1
- Model ID: deepseek-v4-flash-response
- API Key: <your-api-key>
```

#### Method B: Manual CLI Configuration (Masked Credential Flow)
Configure provider parameters, then set credentials via masked interactive prompt:
```powershell
# 1. Configure provider overlay
.\scripts\relay.ps1 worker configure deepseek-v4-flash `
  --profile default `
  --base-url "https://xxx.example.com/v1" `
  --model "deepseek-v4-flash-response" `
  --non-interactive --json

# 2. Safely set credential (masked prompt, not saved in history)
.\scripts\relay.ps1 worker credential set deepseek-v4-flash --profile default

# 3. Run health check
.\scripts\relay.ps1 worker doctor deepseek-v4-flash --profile default
```

---

### 3. Start Delegating Tasks

#### Scenario A: Spawn a Native Subagent (Keep Main Context Clean)
Tell your main Codex agent:
```text
Please spawn a DeepSeek subagent to write unit tests for all functions in this module, and report the final test results back to me.
```

#### Scenario B: Run Tasks with External CLIs
Tell Codex:
```text
Please call OpenCode CLI (using model deepseek-v4-flash-free) to analyze the dependencies in this project and generate a summary report.
```
Or specify other CLIs:
```text
Please call Claude Code CLI to refactor this helper function.
```

---

## 📦 Family of Skills

> 💡 **Recommendation**: In Codex, **we strongly recommend using `relay-agent` directly (or @relay)**. Relay provides two explicit execution paths: Codex native-provider dispatch and thin external-CLI relay. Native auto-selection is conservative and fails closed when candidates are ambiguous.

| Skill Name | Default Mode | Role & Best Use Cases |
| :--- | :--- | :--- |
| 👑 **`relay-agent`** | **Dual Path (Recommended ⭐⭐⭐⭐⭐)** | **Unified Dispatcher**: Worker lifecycle management, conservative dispatching, and execution via Native subagents or External CLIs |
| 🟣 **`relay-claude`** | **Native CLI (`claude`)** | **Claude Code Dedicated**: Minimal thin-relay layer forwarding commands directly to the `claude` CLI |
| 🟢 **`relay-opencode`** | **Native CLI (`opencode`)** | **OpenCode Dedicated**: Dedicated execution channel calling `opencode run` |
| 🔵 **`relay-antigravity`** | **Native CLI (`antigravity`)** | **Antigravity Dedicated**: Dedicated execution channel calling `antigravity` CLI |

---

## 🏗️ Architecture Overview

```text
       [ Your Feature Request ]
                  │
                  ▼
       ┌───────────────────────┐
       │   Codex Main Agent    │ ── (Decomposes tasks / Designs architecture / Keeps context clean)
       └──────────┬────────────┘
                  │ Dispatches subtask
       ┌──────────▼────────────────────────┐
       │   Relay Worker Runtime Registry   │
       └──────────┬────────────────┬───────┘
                  │                │
       [ Native-Provider ]  [ External-CLI ]
                  │                │
  ┌───────────────▼─────────┐ ┌────▼──────────────────────────┐
  │  Codex Native Subagent  │ │ Thin Relay CLI Wrapper        │
  │  (DeepSeek / Gemini ..) │ │ (Claude / OpenCode / Anti..)  │
  └───────────────┬─────────┘ └────┬──────────────────────────┘
                  │                │
                  └────────┬───────┘
                           ▼ Returns raw worker output & artifacts
             [ Codex Main Agent Review & Accept ]
```

---

## ⚠️ Notes & Limitations

When choosing between execution modes, please keep in mind:

1. 🔑 **Prior CLI Authentication Required for External-CLI**:
   - Ensure you are already logged in to the target CLI tool (Claude Code / OpenCode / Antigravity) in your terminal.
   - If unauthenticated, the CLI will fail or prompt for credentials; Relay will surface this error and remind you to authenticate first.
2. 🙈 **Hidden Reasoning (CoT) Visibility**:
   - External-CLI mode acts as a thin execution proxy and returns raw stdout/stderr without hidden reasoning tokens.
   - Use **Codex Native-Provider mode** when you want Codex-managed child lifecycle, progress visibility, and provider isolation.

---

## 🤝 Contributing & Feedback

We welcome contributions, feature requests, and bug reports!

- 🐛 **Submit an Issue**: Found a bug or compatibility glitch? Open an issue at [GitHub Issues](https://github.com/IkariKr/relay-agent-platform/issues) with reproduction steps and logs.
- 💡 **Submit a PR**: Want to add a new Provider Pack or enhance Relay dispatching? Fork the repo and submit a Pull Request!

---

## 📚 Further Reading

- 🗺️ **[Codex Native Subagent Roadmap](docs/codex-native-subagent-roadmap.md)**: Deep dive into Codex Collab protocols and verification evidence.
- 🧪 **[Test Matrix](docs/test-matrix.md)**: 152 automated Pester tests and regression specifications.
- 📦 **[Archive & SOPs](docs/Archive/)**: Installation guides, architecture evolution, and troubleshooting manuals.

---

<p align="center">
  <sub>#AIAgent #Codex #Subagent #ClaudeCode #DeepSeek #Gemini #DeveloperTools #ContextManagement</sub>
</p>
