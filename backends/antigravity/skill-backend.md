## Antigravity Backend Notes

- Preferred thin entrypoint: `scripts/relay.ps1 run --backend antigravity`.
- Relay constructs `agy --add-dir <workdir> --print` and passes explicit `--model`, `--agent`, and `--passthrough` values.
- Use native Antigravity flags through repeated `--passthrough` values; Relay does not set permissions, parse output, retry, or apply timeouts.
