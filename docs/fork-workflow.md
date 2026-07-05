# Fork Workflow

This repository still starts from the upstream Claude-only skill, but it now carries shared sources and an OpenCode package.

## Current Recommendation

1. Fork `IkariKr/codex-delegate-claude` on GitHub.
2. Point local `origin` to your fork.
3. Keep the original repository as `upstream`.
4. Do feature work on topic branches such as `feat/opencode-shared-core`.
5. Periodically fetch and merge or rebase from `upstream/main`.

## Local Commands

Preview current remotes:

```powershell
git remote -v
```

Connect your fork once you have the URL:

```powershell
.\scripts\connect-fork.ps1 -ForkUrl https://github.com/<you>/codex-delegate-claude.git
```

Refresh upstream later:

```powershell
.\scripts\sync-upstream.ps1
```

## Why This Shape

- `shared/` is the single source of truth.
- `backends/` keeps Claude and OpenCode differences isolated.
- `packages/` holds installable outputs.
- The root package remains Claude-compatible so upstream syncing stays practical.
