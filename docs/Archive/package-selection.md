# Relay Package Guide

## Default Recommendation

If you are new to this repository, install and use `relay-agent` first.

It is the main package because it gives you:

- one stable entrypoint
- explicit backend override when you want it
- transparent auto routing when you do not
- both structured and natural-language rule management

## Package Overview

| Package | Best for | Default recommendation |
| --- | --- | --- |
| `relay-agent` | Users who want one entrypoint that can route to Claude, OpenCode, or Antigravity | Yes |
| `relay-claude` | Users who only want Claude-oriented delegation behavior | Conditional |
| `relay-opencode` | Users who only want direct OpenCode/local-provider delegation | Conditional |
| `relay-antigravity` | Users who only want direct Antigravity CLI delegation | Conditional |

## Which Package Should I Choose?

### Choose `relay-agent` if:

- you want the default platform entrypoint
- you want to start with auto routing
- you expect to use multiple backends over time
- you want rule management and routing explainability

### Choose `relay-claude` if:

- you want behavior closest to the original project shape
- you only plan to use Claude Code
- you care about Claude-specific permission or budget controls and do not need OpenCode

### Choose `relay-opencode` if:

- you want direct OpenCode execution without unified routing
- you mainly use local/provider-driven models
- you want to tune provider preference, model intent, paid fallback, or agent choice directly

### Choose `relay-antigravity` if:

- you want direct Antigravity execution without unified routing
- you prefer the current `agy --print` style flow for bounded non-interactive runs
- you want to pin Antigravity-specific model or permission-skip behavior directly

## Decision Shortcut

Use this quick rule:

1. Start with `relay-agent`.
2. Move to `relay-claude` only if you want Claude-only behavior.
3. Move to `relay-opencode` only if you want OpenCode-only behavior.
4. Move to `relay-antigravity` only if you want Antigravity-only behavior.

## Why `relay-agent` Is The Default Surface

The current platform treats `relay-agent` as the main product because it combines:

- stable explicit backend control through `-Backend claude|opencode|antigravity`
- transparent auto routing through `-Backend auto`
- inspectable routing via `manage_auto_routing.ps1`
- beginner-friendly routing management via `manage_auto_routing_nl.ps1`

That makes it the best default for public release, while the specialist packages remain available for focused usage.

## Package Layout

From the repository root:

- source repository: `relay-agent-platform`
- generated Claude package: `packages/relay-claude`
- generated OpenCode package: `packages/relay-opencode`
- generated Antigravity package: `packages/relay-antigravity`
- generated unified package: `packages/relay-agent`

If you clone the repo into your Codex skills directory, build the generated packages and link them in as sibling skills.

## Default Public Surface

The current recommendation is:

- install `relay-agent`
- treat `scripts/run_delegate_agent.ps1` as the primary runtime entrypoint
- treat `scripts/manage_auto_routing.ps1` and `scripts/manage_auto_routing_nl.ps1` as the supported rule-management entrypoints

For more detail:

- installation: `docs/installation.md`
- first-run examples: `docs/quickstart.md`
- routing behavior and config: `docs/routing-guide.md`
