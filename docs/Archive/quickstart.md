# Relay v2 Quick Start

Relay v2 is a thin execution layer. Codex owns task planning, visible subagent progress, review, verification, and Git decisions. Relay only builds and runs one native CLI command.

## Run a backend explicitly

Use `scripts/relay.ps1 run` with a concrete backend:

```powershell
./scripts/relay.ps1 run `
  --backend opencode `
  --model opencode/deepseek-v4-flash-free `
  --agent build `
  --passthrough --auto --passthrough --format --passthrough json `
  -- "Review this repository and report only actionable findings."
```

Supported backends are `opencode`, `claude`, and `antigravity`. `--model`, `--agent`, and every `--passthrough` token are passed to the native CLI without model ranking or intent inference.

> 兼容入口：`scripts/run_relay.ps1` 在弃用窗口内继续可用，但会打印迁移提示并转调同一 core。Compatibility note: `scripts/run_relay.ps1` still works during the deprecation window but prints a migration notice and delegates to the same core.

## Preview before spending tokens

```powershell
./scripts/relay.ps1 run --backend claude --model sonnet --dry-run -- "Explain this file."
```

`--dry-run` only constructs and prints the native command. It does not check or launch the backend CLI.

## Pass a native option

Pass each token separately through `--passthrough` to avoid ambiguity with Relay parameters:

```powershell
./scripts/relay.ps1 run --backend opencode `
  --passthrough --file --passthrough README.md --passthrough --auto `
  -- "Summarize the attached file."
```

Relay inserts native options before the prompt separator. New native CLI features can be used immediately through `--passthrough`.

## Use Codex subagents for long work

For a long-running task, ask Codex to create a native subagent and have that subagent call Relay. The Codex UI then owns progress, interruption, context, review, and any deliberate follow-up. Relay does not enforce wall-clock or idle timeouts, retry calls, poll Git, parse JSONL, or manufacture progress.

## Optional backend routing

Routing is separate from `run`:

```powershell
./scripts/relay.ps1 route explain -- "Do a quick local code change."
./scripts/relay.ps1 route run -- "Do a quick local code change."
```

Routing uses the readable rule table in `.relay-agent/routing.json` or the bundled default. It selects only a backend; it never replaces an explicit model or agent, and it never selects a native-provider worker.

## Optional raw logs

```powershell
./scripts/relay.ps1 run --backend opencode --log-dir ./relay-logs -- "Run the task."
```

Use this only when you need local raw worker output in addition to the live terminal output. The mirror is real-time, not a replay after exit.
