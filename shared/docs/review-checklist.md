## Review Checklist

- The diff directly satisfies the stated goal.
- No unrelated files or generated noise were included.
- Existing dirty files were not accidentally folded into the delegated change.
- Tests or checks cover the changed behavior, or the residual risk is explicitly acceptable.
- Timeout or idle-stop runs were followed by diff inspection before any retry or commit.
- The final commit contains only reviewed, intended changes from this delegation cycle.
