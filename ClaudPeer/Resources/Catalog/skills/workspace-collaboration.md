# Workspace Collaboration

## When to Activate

Use when multiple contributors share directories, sandboxes, or mounted volumes (local clones, shared NFS, cloud dev environments). Critical before parallel refactors or agent-generated file batches.

## Process

1. **Ownership and naming** — Agree who owns `src/`, `experiments/`, `scratch/`. Use predictable prefixes: `team-auth-`, `agent-2025-03-` for temporary trees.
2. **Reduce merge conflicts** — Prefer **feature branches** and **subfolders** per contributor for generated assets; avoid two people editing the same giant JSON or lockfile without coordination.
3. **Document tools and env** — Commit `.tool-versions`, `mise.toml`, `flake.nix`, or Docker Compose so `pnpm install` / `bun install` / `swift build` behave the same for everyone.
4. **File locks (when needed)** — For binary assets or shared staging dirs, use explicit lock files (`.lock` with owner + expiry) or chat claims—document the convention.
5. **Snapshots before destructive work** — `git stash`, `cp -a workspace workspace.bak.$(date +%Y%m%d)`, or volume snapshots before bulk deletes or codegen that might not be reversible.
6. **Permissions** — Use group ACLs or container UIDs consistently; document `chmod`/`chown` expectations for CI vs laptop paths.

## Checklist

- [ ] Directory ownership map shared
- [ ] Branch or subfolder strategy for parallel work
- [ ] Toolchain pinned and documented
- [ ] Lock or claim process for contested paths
- [ ] Backup/snapshot before risky operations

## Tips

Add a `CONTRIBUTING.md` section “Shared workspace rules.” In CI, run `git diff --check` and formatting linters to catch stepping on toes early. For agents, scope file writes to agreed subtrees only.
