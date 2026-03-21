# Blackboard Patterns

## When to Activate

Use when teams or agents share a durable knowledge layer (e.g., ClaudPeer blackboard HTTP API, Redis, or JSON files under `~/.claudpeer/blackboard/`). Use for facts, tasks, decisions, and cross-session memory—not as a chat log replacement.

## Process

1. **Atomic entries** — One concept per key; prefer `feature/auth/oauth-scope` over monolithic `notes`. Values should be small JSON objects, not novels.
2. **Structured JSON** — Fields like `status`, `owner`, `evidenceUrl`, `expiresAt`. Validators or JSON Schema in CI prevent garbage shapes.
3. **Provenance and time** — Include `updatedAt`, `updatedBy` (human or agent id), and optional `source` (ticket, doc). Never anonymous overwrites.
4. **Supersession** — To change meaning, write a new key or add `supersedes: "old-key"` rather than silently editing history; keep audit trail.
5. **TTL and archival** — Define rules: e.g., `task/*` expires after 30 days to `archive/`. Automate cleanup jobs; document in runbook.
6. **Link conversations** — Store `conversationId` or PR URL so readers can open full context. The blackboard holds the pointer, not the entire thread.

## Checklist

- [ ] Keys are namespaced and atomic
- [ ] Payload is valid JSON with schema where possible
- [ ] Timestamps and authors on every write
- [ ] Supersession tracked; no silent rewrites
- [ ] TTL/archival policy documented and enforced

## Tips

Use `GET /blackboard/{scope}/{key}` style APIs consistently; scope by tenant or workspace. Rate-limit writes in multi-agent setups. For sensitive data, encrypt at rest and restrict HTTP to localhost or mTLS as in your threat model.
