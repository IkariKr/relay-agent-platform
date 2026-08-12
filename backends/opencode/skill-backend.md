## OpenCode Backend Notes

- Preferred thin entrypoint: `scripts/run_relay.ps1 -Backend opencode`.
- Relay constructs `opencode run --dir <workdir>` and passes explicit `-Model`, `-Agent`, and `-PassThrough` values before `-- <prompt>`.
- Pin any OpenCode model explicitly, for example `opencode/deepseek-v4-flash-free`.
- Use `-PassThrough '--auto'` or any newly introduced native OpenCode flag when needed; Relay does not select models, parse JSONL, retry, or apply timeouts.
