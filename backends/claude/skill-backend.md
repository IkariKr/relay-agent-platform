## Claude Backend Notes

- Preferred wrapper:
  `scripts/run_claude_delegate.ps1`
- The wrapper calls:
  `claude -p --permission-mode <mode> --output-format <format>`
- Use `acceptEdits` by default and do not allow the worker to commit.
- `stream-json` is available when you need partial messages, but `json` keeps logs smaller for routine runs.
- The Claude wrapper preserves the existing retry model with `-MaxTurns`.
