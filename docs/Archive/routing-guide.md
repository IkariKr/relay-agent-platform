# Relay Routing Guide

## Purpose

`relay-agent` routes work to Claude, OpenCode, or Antigravity through a transparent rule table.

The routing contract is intentionally simple:

- explicit backend selection always wins
- otherwise routing follows config precedence
- rules are evaluated from top to bottom
- the first enabled matching rule wins

## Runtime Entry Point

Main unified entrypoint:

```powershell
.\scripts\run_delegate_agent.ps1
```

Most important parameter:

- `-Backend auto|claude|opencode|antigravity`
- `-AutoStrategy config`

## Routing Priority

### Highest Priority: Explicit Backend

If you run:

```powershell
.\scripts\run_delegate_agent.ps1 -Prompt "..." -Backend claude
```

or:

```powershell
.\scripts\run_delegate_agent.ps1 -Prompt "..." -Backend opencode
```

the selected backend overrides all auto-routing rules.

Backend-specific tuning does not happen through unified top-level flags anymore. Use backend-local config files under `.relay-agent/backends/`.

### Auto Routing

If you run:

```powershell
.\scripts\run_delegate_agent.ps1 -Prompt "..." -Backend auto
```

the script loads the first routing config it can find and resolves the backend from that config.

## Config Search Order

When `-Backend auto` and `-AutoStrategy config` are used, config lookup order is:

1. `-AutoConfigPath`
2. `RELAY_AGENT_CONFIG`
3. `<workdir>\.relay-agent\routing.json`
4. `<workdir>\.relay-agent.json`
5. package `auto-routing.json`
6. package `auto-routing.default.json`

The first file found wins.

Compatibility note:

- `CODEX_DELEGATE_AGENT_CONFIG` is still accepted as a legacy fallback during the rename migration window.

## Rule Table Schema

Top-level fields:

- `version`
- `defaults.preferred_backend`
- `defaults.fallback_backends`
- `defaults.on_no_match`
- `rules`

Per-rule fields:

- `name`
- `enabled`
- `backend`
- `reason`
- `when.prompt_any_regex`
- `when.prompt_all_regex`
- `when.workdir_any_regex`
- `when.workdir_all_regex`

## Matching Semantics

The router uses these rules:

- disabled rules are skipped completely
- `prompt_any_regex` means any one pattern may match
- `prompt_all_regex` means every listed pattern must match
- `workdir_any_regex` means any one workdir pattern may match
- `workdir_all_regex` means every listed workdir pattern must match
- the first enabled rule that matches wins

There is no scoring, weighting, or priority field in the current router.

## Default Fallback Behavior

If no rule matches:

- the script uses `defaults.on_no_match`
- current default template uses `preferred_backend`

If the chosen backend is unavailable:

- the script walks `defaults.fallback_backends` in order
- the fallback reason is printed in output

## Example Default Rules

The default config currently includes patterns such as:

- review, explain, plan, docs, architecture, design -> Claude
- small, quick, simple, tiny, minor, fast, fix, refactor -> OpenCode
- explicit `antigravity` or `agy` prompt hints -> Antigravity
- explicit `claude` prompt hints -> Claude
- explicit `opencode` or local/provider hints -> OpenCode

## Inspect Current Routing

List active rules:

```powershell
.\scripts\manage_auto_routing.ps1 -Action list -Workdir .
```

Explain a prompt:

```powershell
.\scripts\manage_auto_routing.ps1 -Action explain -Workdir . -Prompt "Need a quick fix for this minor bug."
```

Natural-language wrapper:

```powershell
.\scripts\manage_auto_routing_nl.ps1 -Request 'explain prompt: "Need a quick fix for this minor bug."' -Workdir .
```

## Create A Workspace Config

Initialize a workspace-local routing config:

```powershell
.\scripts\manage_auto_routing.ps1 -Action init-user-config -Workdir .
```

That creates:

```text
<workdir>\.relay-agent\routing.json
```

This is the recommended routing customization point.

Per-backend tuning lives beside it:

```text
<workdir>\.relay-agent\backends\claude.json
<workdir>\.relay-agent\backends\opencode.json
<workdir>\.relay-agent\backends\antigravity.json
```

## Add A Rule Structurally

Example:

```powershell
.\scripts\manage_auto_routing.ps1 `
  -Action add `
  -Workdir . `
  -RuleName "quick-local" `
  -Backend opencode `
  -Reason "quick local routing" `
  -PromptAnyRegex "(?i)\bquick\b","(?i)\bfix\b","(?i)\bminor\b"
```

## Add A Rule Through The Natural-Language Wrapper

Example:

```powershell
.\scripts\manage_auto_routing_nl.ps1 `
  -Request 'add rule: "quick-local", backend: opencode, reason: quick local routing, prompt keywords: quick, fix, minor' `
  -Workdir . `
  -Apply
```

## Important V1 Rule-Order Behavior

New rules added through management scripts are appended to the end of the rules list.

That means a newly added rule may not win if an earlier enabled rule already matches the same prompt.

If that happens:

1. run `list` to confirm actual order
2. run `explain` to confirm which earlier rule is winning
3. move the rule upward manually in `routing.json` if you want it to have higher priority

This is expected behavior.

## When To Use Structured vs Natural-Language Management

Use `manage_auto_routing.ps1` when:

- you want exact field control
- you want predictable scripting behavior
- you want to automate config changes

Use `manage_auto_routing_nl.ps1` when:

- you want a friendlier entrypoint
- you are comfortable providing labeled fields like `rule:`, `backend:`, and `prompt keywords:`

The natural-language wrapper is intentionally constrained; it is not a free-form conversational editor.

## Debugging Routing

Start with these commands:

```powershell
.\scripts\manage_auto_routing.ps1 -Action list -Workdir .
.\scripts\manage_auto_routing.ps1 -Action explain -Workdir . -Prompt "your real prompt here"
```

If runtime behavior is still surprising, run:

```powershell
.\scripts\run_delegate_agent.ps1 -Prompt "your real prompt here" -Backend auto -WhatIf
```

That prints the selected backend, reason, and config source without executing the backend.
