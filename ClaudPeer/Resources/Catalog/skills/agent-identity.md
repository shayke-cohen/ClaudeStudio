# Agent Identity

## When to Activate

Use when configuring coding agents, chat assistants, or autonomous workers with tools (filesystem, network, shell). Use at prompt design, policy review, or when behavior drifts from intended role.

## Process

1. **Define mission** — One paragraph: purpose, success metrics, and **out of scope** actions (e.g., “no production deploys without human approval”).
2. **Tool and permission boundaries** — List allowed tools/commands; default deny for destructive ops (`rm -rf`, `DROP DATABASE`). Align with **least privilege** on tokens (read-only GitHub PAT until needed).
3. **Escalation rules** — When to stop and ask: ambiguous requirements, security-sensitive changes, or external communications. Name the human role to ping.
4. **Stable, versioned prompts** — Store system prompts in git (`prompts/agent-v3.md`); tag releases. Changelog prompt changes like code.
5. **Disclose limitations** — State what the agent cannot see (private URLs, live prod data) to prevent false confidence.
6. **Re-ground to avoid drift** — Periodic reminders in long sessions: restate mission, constraints, and current task; prune stale context that contradicts the role.

## Checklist

- [ ] Mission and explicit non-goals documented
- [ ] Tool permissions mapped to least privilege
- [ ] Escalation triggers and human owners defined
- [ ] Prompts version-controlled with change history
- [ ] Limitations stated to users and operators

## Tips

Separate **persona** (tone) from **policy** (hard rules)—policies belong in unskippable preambles or host-level denylists. Audit with red-team prompts monthly. For multi-agent setups, give each agent a distinct name and scope to simplify logs and blame.
