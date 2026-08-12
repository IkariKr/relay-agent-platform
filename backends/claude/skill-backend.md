## Claude Backend Notes

- Preferred thin entrypoint: `scripts/run_relay.ps1 -Backend claude`.
- Relay constructs `claude --print` and passes explicit `-Model`, `-Agent`, and `-PassThrough` values before the prompt.
- Use native Claude flags through repeated `-PassThrough` values; Relay does not impose permission mode, output format, retries, or timeouts.
