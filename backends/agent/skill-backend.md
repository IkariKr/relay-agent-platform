## Unified Backend Notes

- Preferred thin entrypoint: `scripts/relay.ps1 run`（兼容入口 `scripts/run_relay.ps1`，弃用窗口内可用）。
- `--backend` is required and must be `opencode`, `claude`, or `antigravity`.
- `--model`, `--agent`, and repeated `--passthrough` values are passed to the native CLI without Relay model scoring or intent inference.
- `--dry-run` prints the constructed native command without checking or launching a backend.
- Routing is intentionally separate: use `scripts/relay.ps1 route explain|run` only when automatic backend selection is explicitly desired.
