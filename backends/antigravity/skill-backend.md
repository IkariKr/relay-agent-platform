## Antigravity Backend Notes

- Preferred thin entrypoint: `scripts/run_relay.ps1 -Backend antigravity`.
- Relay constructs `agy --add-dir <workdir> --print` and passes explicit `-Model`, `-Agent`, and `-PassThrough` values.
- Use native Antigravity flags through repeated `-PassThrough` values; Relay does not set permissions, parse output, retry, or apply timeouts.
