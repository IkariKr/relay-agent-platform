## Thin Relay v2 Workflow

1. Let Codex own the task.
   - Codex main agent or a native Codex subagent owns decomposition, visible progress, review, verification, retries, and Git decisions.
   - Use a native subagent for long-running work when you want the Codex UI to show progress and retain task context.

2. Select the worker explicitly.
   - Use one of `opencode`, `claude`, or `antigravity`.
   - Preserve an explicit model, agent, prompt, working directory, and native CLI parameters.
   - Use `relay route` only when the caller deliberately asks for routing; `relay run` always uses a concrete backend.

3. Run one native command.
   - Use `scripts/run_relay.ps1 -Backend <backend> -Prompt <prompt>`.
   - Add `-Model`, `-Agent`, and repeated `-PassThrough` values only when required.
   - Relay prints the native command, forwards the backend's raw stdout/stderr, and returns its exit code.

4. Review outside Relay.
   - Relay does not retry, time out, parse JSONL, manufacture progress, poll Git, run tests, stage, or commit.
   - Codex reviews the result and decides whether to continue with a new, more precise task.
