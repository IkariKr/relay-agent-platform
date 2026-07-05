## OpenCode Backend Notes

- Preferred wrapper:
  `scripts/run_opencode_delegate.ps1`
- The wrapper calls:
  `opencode run --dir <workdir> --format json`
- Use `--auto` by default so the worker can complete a bounded coding turn without interactive approvals.
- OpenCode currently relies on timeout controls rather than a native `max-turns` flag, so keep prompts narrow and prefer one concrete edit cycle per run.
- Pass `-Model` or `-Agent` only when Codex has a strong reason to override the local OpenCode defaults.
