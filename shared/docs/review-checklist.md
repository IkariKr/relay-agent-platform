## Codex Review Checklist

- The worker used the requested backend, model, agent, prompt, and native parameters.
- The raw worker output and exit code are available for review.
- The diff directly satisfies the requested task and does not include unrelated changes.
- Relevant tests or checks were run by Codex or a Codex subagent.
- Any retry is a deliberate new Codex decision, not an automatic replay by Relay.
- Git status, staging, commits, and pull requests remain explicit Codex actions.
