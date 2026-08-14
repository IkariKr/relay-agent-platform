## OpenCode Backend Notes

- Preferred thin entrypoint: `scripts/relay.ps1 run --backend opencode`.
- Relay constructs `opencode run --dir <workdir>` and passes explicit `--model`, `--agent`, and `--passthrough` values before `-- <prompt>`.
- Pin any OpenCode model explicitly, for example `opencode/deepseek-v4-flash-free`.
- Use `--passthrough --auto` or any newly introduced native OpenCode flag when needed; Relay does not select models, parse JSONL, retry, or apply timeouts.
