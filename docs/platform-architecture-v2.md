# Codex Delegate Platform Architecture V2

## Status

- Status: implemented architecture
- Trigger: add `Antigravity CLI` support without repeating the current two-backend hardcoding pattern
- Goal: turn the repository from a dual-backend skill family into a backend-extensible agent platform

## Implementation Status

- Phase 1 complete: manifests, registry loader, and routing `v2` compatibility normalization are landed.
- Phase 2 complete: the unified runtime now validates backend ids through the registry and reads backend-local config instead of exposing backend-specific top-level tuning flags.
- Phase 3 complete: package build and validation iterate over declared backends and surfaces.
- Phase 4 complete: `antigravity` is integrated as a registered backend and generated specialist surface.
- Phase 5 complete: deprecated unified-surface backend-specific compatibility flags have been removed.
- Root surface decision complete: the repo root remains the generated `claude` specialist surface driven by `surfaces/claude/surface.json`.

## Why The V1 Shape Did Not Scale

Before the migration, the repository was effective for `Claude` + `OpenCode`, but it did not scale well beyond that pair.

At that time the codebase was centered around three public surfaces:

- root `codex-delegate-claude`
- generated `packages/codex-delegate-opencode`
- generated `packages/codex-delegate-agent`

That shipped `v1` quickly, but it also baked backend knowledge into too many places:

- `run_delegate_agent.ps1` hardcodes `claude` and `opencode`
- routing defaults assume exactly one preferred backend and one fallback backend
- routing validation and NL management assume a fixed backend set
- build and validation scripts enumerate known packages explicitly
- the unified runtime exposes backend-specific flags directly, which does not scale as more CLIs are added

Adding `agy` on top of this shape would work tactically, but it would make the repository less coherent and harder to evolve into a real agent platform.

## Historical Hardcoded Seams In V1

The scaling problem is not abstract. It is visible in the current source layout.

The most important hardcoded seams are:

- `backends/agent/run_delegate_agent.ps1`
  hardcodes explicit backend names, backend availability checks, and backend-specific parameter forwarding
- `backends/agent/AutoRoutingCommon.psm1`
  hardcodes the available backend map and two-backend fallback behavior
- `backends/agent/manage_auto_routing.ps1` and `manage_auto_routing_nl.ps1`
  validate and parse backend names as a fixed known set instead of querying a registry
- `scripts/build-packages.ps1`
  enumerates known packages and copies specific backend scripts explicitly
- `scripts/validate-packages.ps1`
  validates a fixed list of generated files rather than all declared surfaces/backends
- `backends/agent/auto-routing.default.json`
  assumes one preferred backend and one fallback backend

These are exactly the places that would otherwise need new `if backend == antigravity` branches.

## External Patterns Reviewed

The redesign should stay grounded in patterns already working in strong GitHub projects.

### 1. Continue: config-driven provider registry

Reference:

- [continue-dev/continue](https://github.com/continuedev/continue)

Relevant pattern:

- model/provider choices are declared through configuration and provider-specific adapters, not by scattering provider names through every call site

Takeaway for this repo:

- backend discovery should be manifest-driven
- routing should validate against a registry, not a hardcoded `ValidateSet`

### 2. Goose: stable protocol boundary, multiple clients

Reference:

- [aaif-goose/goose discussion on small, stable ACP client support](https://github.com/aaif-goose/goose/discussions/6973)

Relevant pattern:

- keep a small stable boundary between the core runtime and the outer surfaces
- allow multiple user-facing clients without duplicating the entire engine

Takeaway for this repo:

- separate backend execution contracts from package presentation
- keep routing, process supervision, and package generation in one platform layer

### 3. OpenHands SDK: composable runtime pieces

Reference:

- [All-Hands-AI/OpenHands](https://github.com/All-Hands-AI/OpenHands)

Relevant pattern:

- split the system into composable agent, runtime, tool, and model concerns rather than binding everything to one entrypoint script

Takeaway for this repo:

- separate backend adapter logic, routing logic, and surface generation logic
- make each concern replaceable without editing every public script

### 4. Antigravity CLI: evolving headless integration surface

References:

- [google-antigravity/antigravity-cli](https://github.com/google-antigravity/antigravity-cli)
- [Feature request: stable machine-readable integration mode for non-interactive CLI hosts](https://github.com/google-antigravity/antigravity-cli/issues/546)
- [Issue: add ACP stdio JSON-RPC mode](https://github.com/google-antigravity/antigravity-cli/issues/31)

Relevant pattern:

- the public product is strong, but the non-interactive integration surface is still evolving
- the executable name in the ecosystem is currently `agy`, even when the product name is `Antigravity CLI`

Takeaway for this repo:

- the backend contract must distinguish product name from executable name
- backend capabilities must be declared explicitly instead of assuming every backend supports the same headless controls

## Architecture Decision

The repository should move to a **registry + adapter + surface** architecture.

That means:

1. Backends are registered by manifest.
2. The unified agent runtime resolves and invokes backends through that registry.
3. Public skills/packages are generated from surface manifests, not from backend-specific branching in build scripts.
4. Specialist packages remain backend-native.
5. The unified package exposes only generic platform controls; backend-specific tuning moves into backend-local config.

This keeps the current user-facing products intact while allowing new backends such as `agy` to be added with bounded surface area.

## Target Repository Shape

The existing `backends/`, `packages/`, and `docs/` folders can stay, but the repository needs a true platform layer and explicit surface manifests.

```text
platform/
  contracts/
    backend-manifest.schema.json
    surface-manifest.schema.json
    routing.schema.json
  runtime/
    DelegateCommon.psm1
    BackendRegistry.psm1
    RoutingEngine.psm1
    SurfaceInvoker.psm1
  generation/
    BuildPackages.psm1
    RenderSkillMarkdown.psm1
    RenderAgentYaml.psm1
  validation/
    ValidatePackages.psm1

backends/
  claude/
    backend.json
    run_claude_delegate.ps1
    skill-backend.md
  opencode/
    backend.json
    run_opencode_delegate.ps1
    skill-backend.md
  antigravity/
    backend.json
    run_antigravity_delegate.ps1
    skill-backend.md

surfaces/
  claude/
    surface.json
  opencode/
    surface.json
  antigravity/
    surface.json
  agent/
    surface.json

packages/
  codex-delegate-opencode/
  codex-delegate-agent/
  codex-delegate-antigravity/

docs/
```

## Backend Contract

Each backend must become a self-describing adapter rather than an implied convention.

Each `backends/<id>/backend.json` should define:

- `id`
- `display_name`
- `command`
- `product_name`
- `package_name`
- `runner_script`
- `default_surface`
- `capabilities`
- `config_schema_version`
- `docs_path`

Minimum `capabilities` to track:

- `json_output`
- `whatif_supported`
- `timeout_wrapped`
- `interactive_approval_control`
- `file_attachment_support`
- `model_selection_support`

Why this matters:

- the platform can validate whether a backend supports a feature before advertising or routing to it
- `agy` can join the platform even if its controls differ from `Claude` or `OpenCode`
- `Antigravity CLI` can be presented by product name while still resolving the actual command `agy`

## Surface Contract

Backends and public packages are not the same thing and should stop being treated as the same thing.

Each `surfaces/<id>/surface.json` should define:

- `id`
- `package_name`
- `display_name`
- `mode`: `single-backend` or `router`
- `default_backend` for specialist surfaces
- `allowed_backends` for router surfaces
- `public_scripts`
- `default_prompt`
- `doc_entry`

This creates a clean distinction:

- backend = how work is executed
- surface = how users enter the platform

Under this model:

- `codex-delegate-claude` is a specialist surface backed by `claude`
- `codex-delegate-opencode` is a specialist surface backed by `opencode`
- `codex-delegate-antigravity` is a specialist surface backed by `antigravity`
- `codex-delegate-agent` is a router surface backed by the backend registry

### Migration of `backends/agent/`

One of the most important cleanup steps is to stop treating `agent` as if it were a backend.

During migration:

- `backends/agent/agent.json` should become `surfaces/agent/surface.json`
- `backends/agent/run_delegate_agent.ps1` should move into the platform runtime layer
- `backends/agent/AutoRoutingCommon.psm1` should move into the platform runtime layer
- routing management scripts under `backends/agent/` should become router-surface scripts, not backend adapters

The `agent` id should be reserved for the router surface and must never appear as a backend id in `backends/*/backend.json`.

## Unified Runtime Design

### 1. Keep a generic public runtime

`codex-delegate-agent` should stop growing backend-specific top-level flags.

The unified runtime should keep only platform-level parameters such as:

- `-Prompt`
- `-Backend auto|<registered id>`
- `-AutoStrategy`
- `-AutoConfigPath`
- `-Workdir`
- `-MaxTurns`
- `-TimeoutSeconds`
- `-IdleTimeoutSeconds`
- `-PollSeconds`
- `-StatusSeconds`
- `-TailLines`
- `-FullLog`
- `-WhatIf`

### 1.1 Explicit backend validation changes

The migration originally started from a unified runtime that used PowerShell `ValidateSet` for:

- `-Backend auto|claude|opencode`
- `-AutoStrategy config|prefer-claude|prefer-opencode`

In `v2`, `-Backend` should move from parse-time `ValidateSet` enforcement to runtime registry validation.

That means the documented error contract changes from:

- parse-time rejection by PowerShell

to:

- runtime error such as `backend '<id>' is not registered`

This change should be documented as part of the compatibility window so downstream scripts are not surprised by the different failure mode.

### 2. Move backend-specific tuning out of the unified entrypoint

Advanced backend options should live in backend-local config files:

```text
.codex-delegate-agent/
  routing.json
  backends/
    claude.json
    opencode.json
    antigravity.json
```

This is the key scaling decision.

It avoids a future where `run_delegate_agent.ps1` needs `Claude*`, `Opencode*`, `Antigravity*`, and every later backend family as first-class parameters.

The same migration window also deprecated strategy values that encoded specific backend names such as:

- `prefer-claude`
- `prefer-opencode`

Long-term, those preferences belong in routing config through:

- `defaults.preferred_backend`
- `defaults.fallback_backends`

### 3. Keep specialist packages backend-native

Specialist packages should continue exposing backend-native controls directly.

That means:

- `codex-delegate-claude` can keep `PermissionMode`, budget, and tool controls
- `codex-delegate-opencode` can keep model/provider/agent controls
- `codex-delegate-antigravity` can expose whatever `agy` genuinely supports

The platform does not need to force every backend into the same user-facing CLI.

It only needs to force them into the same internal contract.

## Routing V2

The routing model should stay simple, but it must stop assuming exactly two backends.

### Keep

- explicit backend selection wins
- first enabled matching rule wins
- rule evaluation stays top-to-bottom
- routing remains user-inspectable and user-editable

### Change

Replace singular fallback fields with list-based fallback:

```json
{
  "version": 2,
  "defaults": {
    "preferred_backend": "claude",
    "fallback_backends": ["opencode", "antigravity"],
    "on_no_match": "preferred_backend"
  }
}
```

Rule shape can stay mostly the same:

- `rules[].backend` remains a single backend id
- backend ids are validated against the registry
- if the selected backend is unavailable, the runtime walks `fallback_backends` in order

### Compatibility rule

The loader should continue accepting old `v1` config files that use:

- `defaults.fallback_backend`

During load, that field should normalize to:

- `defaults.fallback_backends = ["<old value>"]`

This avoids breaking current users while opening the door to more backends.

### Historical implementation status

This compatibility behavior is a **target-state contract**, not a description of the current `v1` code.

Before the Phase 1 migration landed, the existing routing module still assumed:

- one singular `fallback_backend`
- a binary backend availability model
- explicit knowledge of `claude` and `opencode`

That means `v2`-style list-based `fallback_backends` must not be treated as safely supported until the Phase 1 loader and resolver work lands.

### Resolver migration contract

The resolver migration must be specified explicitly because the current implementation hardcodes a two-backend toggle.

The `v2` resolver must:

1. read `fallback_backends` as an ordered list
2. resolve backend availability from the backend registry, not from dedicated `HasClaude` / `HasOpenCode` booleans
3. walk fallback candidates in order until one registered and available backend succeeds
4. produce a visible routing reason when the primary selection is unavailable and a later fallback wins

The current boolean-input shape of `Resolve-AutoConfiguredBackend` should be treated as a deprecated implementation seam during migration.

## Build And Validation V2

### Build

`scripts/build-packages.ps1` should become a thin orchestration layer that:

1. loads all backend manifests
2. loads all surface manifests
3. generates skill metadata for each declared surface
4. copies backend runners based on surface mode
5. syncs platform runtime modules into generated packages

It should not contain literal knowledge like:

- `"opencode"`
- `"agent"`
- destination package paths for each known backend

Those decisions belong in manifests.

### Validation

`scripts/validate-packages.ps1` should validate by iteration, not enumeration.

It should:

1. validate that every backend manifest has a runnable script and docs
2. validate that every surface manifest resolves to a generated package
3. validate generated package files against the declared source-of-truth files
4. validate routing configs against the current routing schema

This turns validation from a per-backend checklist into a platform invariant.

### Validation invariants by phase

The migration should add stronger invariants in stages instead of waiting for the final manifest-driven validator.

#### Phase 0: strengthen current v1 validation

Add and document these invariants immediately:

- every backend id referenced by `auto-routing.default.json` must correspond to a shipped backend runner
- every backend id referenced by routing defaults must also be accepted by the unified runtime entrypoint
- generated unified-package routing assets must not reference a backend that the package cannot execute

This gives the current validator a real platform-safety role before the full registry architecture is implemented.

#### Phase 1+: move to manifest-driven validation

After manifests land, validation should iterate over declared backends and surfaces rather than a hardcoded file list.

## Compatibility Strategy

This redesign was implemented as an **evolutionary migration**, not a flag day rewrite.

### Preserve in the first migration wave

- package names:
  - `codex-delegate-claude`
  - `codex-delegate-opencode`
  - `codex-delegate-agent`
- root repo continuing to act as the `claude` specialist surface
- current specialist backend scripts
- current `v1` routing semantics

### Change in the first migration wave

- backend registry becomes the source of truth
- unified runtime resolves dynamic backend ids
- routing fallback becomes list-based internally
- build/validation become manifest-driven

### Deprecate, not delete

In the unified surface, `Claude*` and `Opencode*` flags were treated as compatibility shims for one migration window.

That window is now closed. Backend-specific tuning is configured through backend-local config objects under `.codex-delegate-agent/backends/`.

## What This Means For Antigravity

Once the platform layer exists, adding `agy` should become a bounded backend task:

1. add `backends/antigravity/backend.json`
2. add `backends/antigravity/run_antigravity_delegate.ps1`
3. add `backends/antigravity/skill-backend.md`
4. add `surfaces/antigravity/surface.json`
5. optionally add `codex-delegate-antigravity` as a generated specialist package
6. add or update routing defaults to mention `antigravity` only in config, not in code branches

The `antigravity` backend manifest should use:

- `id = "antigravity"`
- `product_name = "Antigravity CLI"`
- `command = "agy"`

That is the desired outcome of this redesign:

- backend addition becomes data-driven and adapter-bounded
- the unified platform no longer needs backend-specific architecture edits in every subsystem

## Recommended Migration Order

### Phase 1: platform contracts

- introduce backend and surface manifests
- introduce runtime registry loader
- introduce routing schema `v2` with compatibility normalization

### Phase 2: unified runtime decoupling

- refactor `run_delegate_agent.ps1` to dynamic backend resolution
- move backend-specific options behind backend-local config
- keep existing compatibility flags temporarily

### Phase 3: build and validation generalization

- make `build-packages.ps1` manifest-driven
- make `validate-packages.ps1` manifest-driven
- generate specialist packages from surface definitions

### Phase 4: Antigravity integration

- add the `antigravity` backend adapter
- add specialist package generation
- add routing defaults and docs

### Phase 5: post-migration cleanup

- remove deprecated unified-surface backend-specific flags
- consider renaming repo-level concepts from "skill family" to "platform"
- keep the root package as the generated Claude specialist surface defined by `surfaces/claude/surface.json`

## Architecture Summary

The current architecture is no longer "Claude plus extra exceptions".

It is now:

- one platform runtime
- many backend adapters
- many user-facing surfaces
- manifest-driven generation and validation
- routing that understands any registered backend

That is the minimum clean architecture that makes `agy` a normal extension instead of another special case.
