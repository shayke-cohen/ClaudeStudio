# Swift / macOS Skills Suite — Design Spec

**Date:** 2026-04-18  
**Status:** Approved

---

## Overview

A suite of six skills for Swift/macOS development: five generic (any Swift project) and one Odyssey-specific. Each skill is narrow enough to trigger on precise symptoms, so Claude loads only what is relevant rather than a monolithic debugging guide.

All skills live in `~/.claude/skills/` using the superpowers flat namespace convention.

---

## Skill Inventory

| Skill name | Type | Scope |
|---|---|---|
| `swift-actor-isolation` | Technique | Any Swift 6 project |
| `swiftui-macos-crashes` | Technique | Any macOS SwiftUI app |
| `macos-crash-logs` | Reference | Any macOS app |
| `swiftdata-debugging` | Technique | Any SwiftData project |
| `xcode-build-failures` | Reference | Any Xcode project |
| `odyssey-concurrency` | Technique | Odyssey only |

---

## Skill Designs

### 1. `swift-actor-isolation`

**Trigger description:**
> Use when Swift 6 build produces actor isolation errors, `@MainActor` constraint violations, `Sendable` warnings, or the app crashes with `assumeIsolated` or async context issues.

**File:** `~/.claude/skills/swift-actor-isolation/SKILL.md`

**Content sections:**
- Overview: Swift 6 strict concurrency model in one paragraph
- Error → fix quick-reference table (most common compiler errors with their canonical solutions)
- `@MainActor` annotation patterns: function, class, closure
- `Task { @MainActor in }` vs `await MainActor.run { }` — when to use each
- `MainActor.assumeIsolated(_:)` — safe use cases and when it crashes
- `nonisolated` keyword — escaping the actor without breaking safety
- Sendable conformance patterns: `@unchecked Sendable`, `Sendable` structs, actors as Sendable
- Anti-patterns section: what NOT to do (force-casting, DispatchQueue.main as workaround)

**Supporting files:** none (all inline, target <400 words)

---

### 2. `swiftui-macos-crashes`

**Trigger description:**
> Use when a macOS SwiftUI app crashes in drag/drop, List reorder, sheet presentation, ForEach with unstable IDs, or environment object propagation.

**File:** `~/.claude/skills/swiftui-macos-crashes/SKILL.md`

**Content sections:**
- Overview: macOS SwiftUI has macOS-only bugs not present on iOS
- `dropDestination` + actor isolation crash: the exact pattern (callback runs on non-main actor, calling `@MainActor` state → wrap in `Task { @MainActor in }`)
- `List + .onMove` vs `draggable/dropDestination`: when each is safe on macOS 14
- Sheet lifecycle crashes: presenting from wrong context, `@Environment` availability
- `@Environment(\.modelContext)` threading: must be accessed on MainActor
- ForEach id stability: unstable IDs cause identity crashes on rerender
- Known macOS-only SwiftUI bugs table: symptom → workaround, macOS version affected

**Supporting files:** none

---

### 3. `macos-crash-logs`

**Trigger description:**
> Use when reading a macOS crash report (.ips file), symbolication is needed, or Console.app shows cryptic frames from a crashed process.

**File:** `~/.claude/skills/macos-crash-logs/SKILL.md`

**Content sections:**
- Where logs live: `~/Library/Logs/DiagnosticReports/`, Xcode Organizer, Console.app
- `.ips` file anatomy: header fields (exception type, signal, process), crashed thread index, thread stacks
- Exception type decoder: EXC_BAD_ACCESS (nil deref / use-after-free), SIGABRT (assert/precondition), EXC_CRASH (Swift runtime trap), EXC_BREAKPOINT (Swift forced unwrap)
- Reading strategy: crashed thread first → find topmost app frame → ignore system frames above it
- `atos` symbolication: exact command with dSYM path, load address extraction
- Console.app filter recipe: process name + subsystem + fault level
- Sidecar-specific: TypeScript sidecar crashes appear in Console as Bun process logs, not `.ips`

**Supporting files:** none

---

### 4. `swiftdata-debugging`

**Trigger description:**
> Use when SwiftData throws runtime errors, `@Query` returns unexpected results, model context operations crash, or schema migration fails on app launch.

**File:** `~/.claude/skills/swiftdata-debugging/SKILL.md`

**Content sections:**
- Overview: SwiftData's threading model — `ModelContext` is not thread-safe
- Main context vs background context: `@MainActor` view context vs `ModelActor` background
- Never pass `ModelContext` across actor boundaries — use `PersistentIdentifier` instead
- `@ModelActor` pattern for background mutations
- `modelContainer(for:)` setup: where it lives, what happens if called twice
- Migration versioning: `VersionedSchema`, `SchemaMigrationPlan`, `MigrationStage`
- Common runtime errors decoded: "Object not found in store", "multiple persistent stores", "model not registered"
- `@Query` gotchas: predicate syntax, sort descriptor types, relationship fetch

**Supporting files:** none

---

### 5. `xcode-build-failures`

**Trigger description:**
> Use when Xcode build fails with SPM resolution errors, XcodeGen project mismatches, code signing failures, or missing file references after adding new Swift files.

**File:** `~/.claude/skills/xcode-build-failures/SKILL.md`

**Content sections:**
- XcodeGen flow: when to run `xcodegen generate`, what it regenerates, common `project.yml` mistakes
- SPM resolution failures: derived data cache clear commands, `~/.swiftpm/cache` nuke, `Package.resolved` conflicts
- Code signing: identity vs profile mismatch, automatic vs manual, team ID lookup
- Derived data nuke recipe: exact `rm -rf` path + Xcode restart sequence
- "File not found" after adding files: XcodeGen not re-run vs file not in `project.yml` sources
- Build setting conflicts: `project.yml` overrides vs Xcode UI edits (Xcode wins until regenerate)

**Supporting files:** none

---

### 6. `odyssey-concurrency`

**Trigger description:**
> Use when working on Odyssey and hitting actor isolation errors in AppState, SidecarManager callbacks, SwiftData view queries, or WebSocket message handlers.

**File:** `~/.claude/skills/odyssey-concurrency/SKILL.md`

**Content sections:**
- Requires: cross-reference to `swift-actor-isolation` for generic patterns
- `AppState` contract: `@MainActor @ObservableObject` — every property mutation and method call must be on main thread
- `SidecarManager → AppState` data flow: always via `AsyncStream`, never direct method calls from ws callbacks
- WebSocket `onMessage` threading: Bun WebSocket callbacks arrive on a background thread; always wrap AppState calls in `Task { @MainActor in }`
- SwiftUI views in Odyssey: `@Query` directly in views, no ViewModel layer, `@Environment(\.modelContext)` for writes
- `ModelContainer` is main-actor-bound in `OdysseyApp.swift` — background SwiftData work must use `@ModelActor`
- `drainPendingAutoPrompt()` pattern: must be called on MainActor, triggered from `.connected` sidecar event
- Specific patterns Odyssey uses: `Task { @MainActor in }` preferred over `await MainActor.run` for fire-and-forget; `MainActor.assumeIsolated` only inside synchronous closures confirmed to run on main thread

---

## File Structure

```
~/.claude/skills/
  swift-actor-isolation/
    SKILL.md
  swiftui-macos-crashes/
    SKILL.md
  macos-crash-logs/
    SKILL.md
  swiftdata-debugging/
    SKILL.md
  xcode-build-failures/
    SKILL.md
  odyssey-concurrency/
    SKILL.md
```

---

## Quality Constraints

- Every `SKILL.md` frontmatter description starts with "Use when..." and contains no workflow summary
- Descriptions written in third person, max 500 characters
- Target word counts: generic skills <400 words each; `odyssey-concurrency` <300 words (relies on cross-reference)
- No narrative storytelling — only patterns, tables, and code snippets
- Code examples: Swift only, complete and runnable, one per skill
- `odyssey-concurrency` cross-references `swift-actor-isolation` rather than duplicating content

---

## Success Criteria

- Claude loads `swift-actor-isolation` when a build error mentions `@MainActor` or `Sendable`
- Claude loads `swiftui-macos-crashes` when a crash involves `dropDestination` or `List`
- Claude loads `macos-crash-logs` when a `.ips` file or Console.app output is pasted
- Claude loads `swiftdata-debugging` when `@Query`, `ModelContext`, or migration is mentioned
- Claude loads `xcode-build-failures` when XcodeGen, SPM, or signing is the problem
- Claude loads `odyssey-concurrency` when working in Odyssey files that touch `AppState` or `SidecarManager`
- Generic skills trigger on non-Odyssey Swift projects too
