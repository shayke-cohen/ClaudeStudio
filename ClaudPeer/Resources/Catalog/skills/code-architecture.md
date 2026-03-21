# Code Architecture

## When to Activate

Use when splitting features into modules, reducing coupling, or preparing for scale and team parallelism—before folders become junk drawers.

## Process

1. **Define responsibilities** — One reason to change per module (e.g. `SidecarProtocol` for wire types, `SessionManager` for SDK lifecycle). Write a one-paragraph charter at the package README level.
2. **Minimize cycles** — Layer graph: UI → app state → services → adapters → domain. Break cycles with protocols or dependency inversion; use `swift package` targets to enforce acyclic imports.
3. **Explicit interfaces** — Expose narrow facades; keep internals `internal`/`fileprivate`. Prefer composition over inheritance for UI and services.
4. **Isolate I/O** — Push networking, disk, and process spawning behind protocols (`SidecarManaging`, `AttachmentStoring`) to simplify tests and swaps.
5. **Validate with scenarios** — Walk “add a new sidecar command” and “swap persistence” as thought experiments. If both touch every file, boundaries need work.

## Checklist

- [ ] Module boundaries match team ownership or deploy units
- [ ] No dependency cycles between targets/packages
- [ ] IO and third-party SDKs behind adapters
- [ ] Public surface documented and minimal
- [ ] Change scenarios remain localized

## Tips

Favor feature folders co-locating UI + tests for small apps; use layers when multiple clients share logic. Keep configuration (`AppState`, env) at the edges, not sprinkled globally. Align folder names with Xcode targets and `sidecar/src` modules.
