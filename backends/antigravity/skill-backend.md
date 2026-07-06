## Antigravity Backend Notes

- Preferred wrapper:
  `scripts/run_antigravity_delegate.ps1`
- The wrapper calls:
  `agy --print --add-dir <workdir>`
- Use `--print` for bounded non-interactive runs and keep prompts narrow because the current public CLI does not yet expose a stable ACP/JSON-RPC transport.
- `--model` is available when Codex has a strong reason to pin the session model.
- `--dangerously-skip-permissions` is enabled by default in the backend config so the wrapper can complete a bounded turn without waiting for interactive approval.
