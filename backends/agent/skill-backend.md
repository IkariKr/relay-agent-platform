## Unified Backend Notes

- Preferred wrapper:
  `scripts/run_delegate_agent.ps1`
- This wrapper is a routing layer for multi-backend delegation.
- Start with `-Backend auto` and a conservative `-AutoStrategy prefer-claude`.
- Use `-Backend opencode` when you explicitly want OpenCode's local model/provider pipeline.
- Use `-Backend claude` when you want the existing Claude behavior or need Claude-specific permission controls.
- The first version is intentionally thin: it standardizes the entrypoint without hiding backend-specific parameters.
