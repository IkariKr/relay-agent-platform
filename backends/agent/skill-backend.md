## Unified Backend Notes

- Preferred thin entrypoint: `scripts/run_relay.ps1`.
- `-Backend` is required and must be `opencode`, `claude`, or `antigravity`.
- `-Model`, `-Agent`, and repeated `-PassThrough` values are passed to the native CLI without Relay model scoring or intent inference.
- `-DryRun` prints the constructed native command without checking or launching a backend.
- Routing is intentionally separate: use the routing scripts only when automatic backend selection is explicitly desired.
