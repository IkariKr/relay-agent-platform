# Relay Architecture

This document describes the **currently implemented external-cli repository shape** after the `v2` platform migration.

For the implemented CLI registry migration record and the next platform abstraction, see:

- `docs/platform-architecture-v2.md`: implemented external-cli Backend Registry + Surface architecture
- `docs/codex-native-subagent-roadmap.md`: long-term Worker Runtime Registry and CodeX native-provider implementation plan

The short version is:

- the repo currently follows a registry + adapter + surface architecture for external CLI workers
- CLI backend addition is manifest-driven instead of hardcoded in runtime, routing, build, and validation scripts
- `Claude`, `OpenCode`, and `Antigravity` are registered CLI backends, and `relay-agent` is the router surface
- the next architecture layer is a Worker Runtime Registry; the current Backend Registry becomes its `external-cli` adapter rather than being stretched to represent provider-native children

The sections below describe the current codebase layout and the remaining historical exceptions.

Related planning documents:

- `docs/v1-roadmap.md`: public release scope, milestones, and acceptance criteria for `v1`.
- `docs/package-selection.md`: package recommendation and user-facing surface comparison.
- `docs/installation.md`: install, build, and verification flow.
- `docs/quickstart.md`: first-run commands for the public `v1` packages.
- `docs/routing-guide.md`: routing contract, config precedence, and rule management.
- `docs/troubleshooting.md`: common failure modes and recovery steps.
- `docs/release-checklist.md`: maintainer release workflow and smoke tests.
- `docs/v1.0.0-release-notes.md`: release messaging for the initial public version.
- `docs/platform-architecture-v2.md`: implemented external-cli platform architecture and migration record for `v2`.
- `docs/codex-native-subagent-roadmap.md`: CodeX-first plan for real third-party provider native children, capability probing, transport, safety, and acceptance gates.

## Layout

- `shared/`: single source of truth for reusable docs and PowerShell helpers.
- `platform/`: current external-cli contracts/runtime modules shared by the router surface; planned home for the higher-level Worker Runtime Registry, CodeX host adapter, and provider-native transports.
- `backends/`: backend-specific metadata and behavior notes.
- `surfaces/`: public surface manifests that drive generated packages.
- `packages/relay-antigravity/`: installable Antigravity package generated and validated from shared sources.
- `packages/relay-opencode/`: installable OpenCode package generated and validated from shared sources.
- `packages/relay-agent/`: unified multi-backend entrypoint package generated from shared and backend sources.
- `shared/scripts/ThinRelay.psm1`: current external-cli thin execution core; owns command construction/default merging/process invocation, but not routing policy or native child lifecycle.
- `scripts/run_relay.ps1`: current public thin wrapper; target migration is to canonical `scripts/relay.ps1 run` per Thin Relay v2 SOP.
- `scripts/route_relay.ps1`: current external-cli routing wrapper; future Worker Dispatch sits above this layer rather than replacing its backend-routing role.
- `scripts/build-packages.ps1`: regenerates package metadata and runtime copies by iterating over declared surfaces and backends.
- `scripts/validate-packages.ps1`: manifest-driven consistency checks for generated outputs.
- `scripts/connect-fork.ps1`: switches the repository to `origin=<your fork>` and `upstream=<source repo>` when the fork URL is available.
- `scripts/install-workspace-skill-links.ps1`: creates workspace-visible junctions for generated skill packages.

## Current Layout Exceptions

The repository is now on the `v2` architecture, but it still contains a few historical exceptions.

- `scripts/run_claude_delegate.ps1` lives in the top-level `scripts/` folder rather than `backends/claude/`.
- `backends/agent/` currently mixes router-surface metadata, routing runtime code, and package-generation inputs in one place.

These exceptions are survivable, but they should not be treated as the long-term ideal platform layout.

## Branching

Current repository state at this planning baseline:

- `main`: current checked-out baseline branch.
- `codex/thin-relay-v2`: existing topic branch for Thin Relay v2 work.

Historical branch names such as `feat/opencode-shared-core` and `feat/multi-backend-skill` are no longer current architecture guidance. New Worker Registry / native-provider work should start from the intended current baseline using a fresh topic branch or isolated worktree and follow the repository's normal review workflow.

## Sync Strategy

- Shared content is edited once under `shared/`.
- Backend metadata is edited once under `backends/<backend>/`.
- Surface metadata is edited once under `surfaces/<surface>/`.
- Backend package scripts are edited once under `backends/<backend>/` and copied into generated packages.
- Unified auto-routing defaults are edited once under `backends/agent/auto-routing.default.json`.
- Unified routing management logic is shared through `backends/agent/AutoRoutingCommon.psm1` and consumed by both route execution and rule management scripts.
- Natural-language rule management requests are translated by `backends/agent/manage_auto_routing_nl.ps1`, which delegates all actual changes to `manage_auto_routing.ps1`.
- Generated package files are refreshed through `scripts/build-packages.ps1`.
- Installable packages stay self-contained because the build copies the shared PowerShell module, platform runtime, and registry manifests into generated packages where needed.
