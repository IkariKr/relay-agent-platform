## Claude Backend Notes

- Preferred thin entrypoint: `scripts/relay.ps1 run --backend claude`.
- Relay constructs `claude --print` and passes explicit `--model`, `--agent`, and `--passthrough` values before the prompt.
- Use native Claude flags through repeated `--passthrough` values; Relay does not impose permission mode, output format, retries, or timeouts.
