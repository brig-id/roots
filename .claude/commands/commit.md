---
description: Generate a Conventional Commits + gitmoji message from staged changes
---

Generate a commit message for the current repository.

Steps:
1. Run `git diff --staged --stat` then `git diff --staged` to see staged changes.
2. Run `git rev-parse --show-toplevel` to find the repo root, then read `scopes.json` there for valid scopes.
3. Read `/workspaces/roots/commit-convention.json` for the full type→emoji mapping.
4. Pick the most fitting type, the most specific emoji from `alternatives` if it matches better than the primary, and a scope from `scopes.json` (or omit the scope if none fits well).
5. Format: `<type>(<scope>): <emoji> <description>` — description ≤72 chars, English, lowercase, imperative mood, no trailing period.
6. If staged changes span multiple logical concerns, use the dominant type for the subject line and a bullet list in the body.

Present the proposed message. If $ARGUMENTS are provided, treat them as additional context or constraints (e.g. a scope hint or description hint).
