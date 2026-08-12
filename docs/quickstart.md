# Relay v2 Quick Start

Relay v2 is a thin execution layer. Codex owns task planning, visible subagent progress, review, verification, and Git decisions. Relay only builds and runs one native CLI command.

## Run a backend explicitly

Use `scripts/run_relay.ps1` with a concrete backend:

```powershell
./scripts/run_relay.ps1 `
  -Backend opencode `
  -Model opencode/deepseek-v4-flash-free `
  -Agent build `
  -PassThrough '--auto','--format','json' `
  -Prompt 'Review this repository and report only actionable findings.'
```

Supported backends are `opencode`, `claude`, and `antigravity`. `-Model`, `-Agent`, and every `-PassThrough` token are passed to the native CLI without model ranking or intent inference.

## Preview before spending tokens

```powershell
./scripts/run_relay.ps1 -Backend claude -Model sonnet -Prompt 'Explain this file.' -DryRun
```

`-DryRun` only constructs and prints the native command. It does not check or launch the backend CLI.

## Pass a native option

Pass each token separately to avoid ambiguity with Relay parameters:

```powershell
./scripts/run_relay.ps1 -Backend opencode `
  -PassThrough '--file','README.md','--auto' `
  -Prompt 'Summarize the attached file.'
```

Relay inserts native options before the prompt separator. New native CLI features can be used immediately through `-PassThrough`.

## Use Codex subagents for long work

For a long-running task, ask Codex to create a native subagent and have that subagent call Relay. The Codex UI then owns progress, interruption, context, review, and any deliberate follow-up. Relay does not enforce wall-clock or idle timeouts, retry calls, poll Git, parse JSONL, or manufacture progress.

## Optional backend routing

Routing is separate from `run`:

```powershell
./scripts/route_relay.ps1 -Action explain -Prompt 'Do a quick local code change.'
./scripts/route_relay.ps1 -Action run -Prompt 'Do a quick local code change.'
```

Routing uses the readable rule table in `.relay-agent/routing.json` or the bundled default. It selects only a backend; it never replaces an explicit model or agent.

## Optional raw logs

```powershell
./scripts/run_relay.ps1 -Backend opencode -LogDir ./relay-logs -Prompt 'Run the task.'
```

Use this only when you need local raw worker output in addition to the live terminal output.
