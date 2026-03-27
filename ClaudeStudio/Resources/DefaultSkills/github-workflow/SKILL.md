---
name: github-workflow
description: Guidelines for using GitHub issues, PRs, reviews, releases, and projects via gh CLI.
category: ClaudeStudio
triggers:
  - github
  - gh cli
  - create issue
  - open pr
  - pull request
  - code review
  - release
  - github project
---

# GitHub Workflow

You are working in a GitHub repository. Use the `gh` CLI (via Bash tool) to create durable, externally-visible work artifacts. Use PeerBus for real-time agent coordination.

## Prerequisites

Before using GitHub workflows, verify:
1. `gh auth status` — must succeed
2. Workspace has a GitHub remote

If either fails, skip GitHub workflows and work normally.

## When to Use GitHub

- **Issues** for work that should survive the session: bugs, features, tasks, blockers.
- **PRs** for code changes that need review or visibility.
- **Reviews** when another agent's code needs a quality gate.
- **Releases** when shipping a milestone.
- **Projects** for tracking progress across multiple issues.
- Do NOT use GitHub for ephemeral coordination — that's PeerBus.

## Multi-Agent Conventions

- Delegated code work → create issue + PR, link them.
- Another agent's PR → review it. Never approve your own PR.
- Reference agents by name in issue/PR comments for traceability.
- When creating issues from decomposed tasks, assign labels and link parent issues.

## Safety Policy

- **Free:** create issue, create PR, comment, request review, list/view anything, check CI status.
- **Confirm with user first:** merge PR, close issue, delete branch, force push, create release.
- **Never:** force-push to main/master, delete repositories, modify branch protection rules.

## Issue Conventions

- Use labels: `agent-created`, `priority:{low,medium,high,critical}`, `type:{bug,feature,task}`.
- Close with a resolution summary, not just "done".
- Link related issues and PRs.

## PR Conventions

- Reference the issue number in PR description.
- Use draft PRs for work-in-progress.
- Check CI status before requesting review.
- Keep PRs focused — one concern per PR.

## Release & Project Conventions

- Create releases with changelogs summarizing what changed.
- Use GitHub Projects to track issue progress through stages.
