# Configuration UI — Hero Detail Design

**Date:** 2026-04-17  
**Status:** Approved  
**Scope:** Settings › Configuration tab visual redesign (no new features, no schema changes)

---

## Summary

Redesign the Configuration settings tab from its current plain three-pane list into a modern "Hero Detail" layout. The middle pane gains a search field and richer list rows; the detail pane gains a per-entity gradient hero header. All existing functionality (Edit sheet, Reveal in Finder, chip navigation, section routing) is preserved.

---

## Design Decisions

| Question | Decision |
|---|---|
| Layout direction | B — Hero Detail (three-pane preserved) |
| Header color | Per-entity accent color (uses existing `agent.color` / `group.color` field) |
| Search | Yes — live-filter search field in every list pane |
| Content per section | Section-aware (Agents ≠ Groups ≠ Skills ≠ MCPs) |

---

## Layout Structure

```
┌─────────────┬────────────────────┬──────────────────────────────────┐
│  Sub-nav    │  List pane         │  Detail pane                     │
│  (130px)    │  (200px)           │  (flex 1)                        │
│             │                    │                                  │
│  🤖 Agents  │  [section title]   │  ╔══════════════════════════╗    │
│  👥 Groups  │  [+ New]           │  ║  gradient hero header    ║    │
│  ⚡ Skills  │  ─────────────     │  ║  avatar  name  meta      ║    │
│  🔧 MCPs    │  🔍 search field   │  ║  [Edit] [↗ Reveal]       ║    │
│  📄 Templ.  │  ─────────────     │  ║  📌 Resident (if set)    ║    │
│  🔒 Perms   │  • row             │  ╚══════════════════════════╝    │
│             │  • row (selected)  │                                  │
│  ─────────  │  • row             │  Section chips                   │
│  📂 Folder  │  • row             │  Body (prompt / content)         │
│             │                    │  Configuration rows              │
└─────────────┴────────────────────┴──────────────────────────────────┘
```

---

## Sub-nav Pane (~130px)

- Icon + label for each section: Agents, Groups, Skills, MCPs, Templates, Permissions
- Active item: `accentColor` tinted background + bold text
- "📂 Open Config Folder" at bottom (opens `~/.odyssey/config/` in Finder)
- Templates section: renders embedded `TemplatesSettingsTab` in the detail area (existing behavior preserved — no list/detail split)
- Permissions section: list + read-only detail (no Edit button)

---

## List Pane (~200px)

### Header
- Section title (bold, 13px) + **"+ New"** button (right-aligned, accentColor)

### Search field
- Rounded field below header, full-width with 8px horizontal padding
- Placeholder: "Search {section}…" (e.g. "Search agents…")
- Live-filters list rows by name (case-insensitive contains)
- Clears on section switch

### Rows — Agents
```
[avatar 28px]  Name          [model badge]  [pin dot]
               5 skills · 2 MCPs
```
- Avatar: entity `color` background, `icon` centered, 8px corner radius
- Subtitle: "{N} skills · {N} MCPs" (omit MCPs if 0)
- Model badge: colored pill (opus=blue, sonnet=green, haiku=purple)
- Pin dot (6px blue circle): shown when `agent.isResident == true`
- Selected row: accentColor 10% background tint

### Rows — Groups
```
[avatar 28px]  Name
               agent1 · agent2 · agent3
```
- Subtitle: member agent names joined by " · " (max 3, then "+N more")
- No model badge (groups inherit per-step model)

### Rows — Skills
```
[avatar 28px]  Name
               {Category} · {N} triggers
```

### Rows — MCPs
```
[avatar 28px]  Name
               {transport} · {description}
```

---

## Detail Pane — Hero Header

A gradient banner at the top of the detail pane. Height is natural (padding 20px top/bottom).

**Gradient:** `linear-gradient(135deg, {color} 0%, {color darkened ~20%} 100%)`
- Color source: `Color.fromAgentColor(entity.color)` — existing helper
- Darken for end stop: convert `Color.fromAgentColor(entity.color)` to HSB, reduce brightness by 25% (`brightness * 0.75`). Use `UIColor(color).getHue(_:saturation:brightness:alpha:)` or a custom `Color` extension `func darkened(by fraction: Double) -> Color`.
- Decorative circles: two translucent white circles positioned top-right and bottom-right for depth

**Contents:**
```
[avatar 44px]  [Name 18px bold]           [Edit btn]  [↗ Reveal btn]
               [meta pills: type · model · status]
[📌 Resident badge]  ← only when agent.isResident == true
```

- Avatar: `rgba(255,255,255,0.2)` background, 12px corner radius, white icon/emoji
- Name: 18px, weight 800, white
- Meta: 11px, `rgba(255,255,255,0.65)`, items separated by small dot spacer
- Edit / Reveal buttons: `rgba(255,255,255,0.18)` pill, white text, 1px white/12% border
- Resident badge: `rgba(255,255,255,0.15)` pill, shown below the top row

**Meta content per section:**
- Agent: `Agent · {model} · resident` (omit "resident" if false)
- Group: `Group · {N} agents · autonomous` (omit "autonomous" if false)
- Skill: `Skill · {category}`
- MCP: `MCP · {transport}`

---

## Detail Pane — Body

Scrollable area below the hero. Three stacked sections with `14px` gap.

### Section 1 — Chips (section-aware)

| Section | Label | Chip types |
|---|---|---|
| Agents | "Skills" + "MCPs" (two sub-sections) | ⚡ skill name (green) · 🔧 MCP name (orange) |
| Groups | "Members & Roles" + "MCPs" | 👑 coordinator (purple) · 📋 scribe (teal) · 👁 observer (lime) · 🔧 MCP (orange) |
| Skills | "Triggers" + "Used by" | trigger word (blue) · 🤖 agent name (green) |
| MCPs | "Transport" + "Used by" | transport/protocol tag (slate) · 🤖 agent name (green) |

**Navigation:** Entity-reference chips (skill names, MCP names, agent names in "Used by") are tappable and navigate via `WindowState.openConfiguration(section:slug:)`. Trigger-word chips (Skills › Triggers) and transport-tag chips (MCPs › Transport) are display-only — they have no destination entity.

### Section 2 — Body text

| Section | Label | Content |
|---|---|---|
| Agents | "System Prompt" | First ~150 chars of `agent.systemPrompt`, monospace, truncated with "…" |
| Groups | "Group Instruction" | First ~150 chars of `group.groupInstruction` |
| Skills | "Skill Content" | First ~150 chars of skill body (markdown, stripped) |
| MCPs | "Command" | Transport config: `command: …\nargs: …\nenv: …` (stdio) or `url: …\nheaders: …` (http) |

### Section 3 — Configuration rows

Key/value pairs, 11px text. Section-aware:

- **Agents:** Model, Max turns, Max budget, Instance policy, Working directory
- **Groups:** Routing mode, Auto-reply, Coordinator, Working directory
- **Skills:** Category, Agents using, Source
- **MCPs:** Transport, Command/URL, Agents using

---

## Dark / Light Mode

All colors adapt:

| Element | Dark | Light |
|---|---|---|
| Window background | `#1c1c1e` | `#ffffff` |
| Sub-nav background | `#2c2c2e` | `#f5f5f7` |
| List pane background | `#252527` | `#fafafa` |
| Search field fill | `#1c1c1e` | `#ebebf0` |
| Row selected tint | `#007aff18` | `#e8f0fe` |
| Body text | `#e5e7eb` | `#1c1c1e` |
| Secondary text | `#636366` | `#8e8e93` |
| Prompt box background | `#252527` | `#f5f5f7` |
| Chip: skill | `#1a3d2b` / `#4ade80` | `#dcfce7` / `#16a34a` |
| Chip: MCP | `#3d2a0d` / `#fb923c` | `#ffedd5` / `#ea580c` |
| Chip: trigger | `#0d2540` / `#60a5fa` | `#dbeafe` / `#1d4ed8` |
| Chip: coordinator | `#2d1d44` / `#c084fc` | `#f3e8ff` / `#9333ea` |
| Chip: scribe | `#0d2d2d` / `#2dd4bf` | `#ccfbf1` / `#0d9488` |
| Chip: observer | `#2d2d0d` / `#a3e635` | `#ecfccb` / `#4d7c0f` |
| Chip: transport | `#1c1c2e` / `#94a3b8` | `#f1f5f9` / `#475569` |

Hero gradient is the same in both modes (white text on color always works).

---

## Files to Change

| File | Change |
|---|---|
| `Odyssey/Views/Settings/ConfigurationSettingsTab.swift` | Add search state; update list rows to new rich layout |
| `Odyssey/Views/Settings/ConfigurationDetailView.swift` | Replace header with gradient hero; add section-aware chip sections and body sections |
| `Odyssey/Views/Components/ColorExtension.swift` | Add `Color.fromAgentColor(_:darkened:)` helper that returns a darker shade for gradient end-stop |

No new files needed. No model changes. No SwiftData schema changes. No wire protocol changes.

---

## What Does NOT Change

- All sub-nav section routing (ConfigSection enum, ConfigSelectedItem enum)
- Edit sheet (AgentEditorView, GroupEditorView, MCPEditorView) — opened as-is
- "Reveal in Finder" behavior
- Chip tap → `WindowState.openConfiguration(section:slug:)` navigation
- Templates section embedding `TemplatesSettingsTab`
- Permissions section (read-only detail, no Edit button)
- `initialSection` / `initialSlug` deep-link routing
- Accessibility identifiers (keep existing ones, add new ones for hero elements)

---

## Accessibility

New identifiers to add:

| Element | Identifier |
|---|---|
| Hero header container | `settings.configuration.heroHeader` |
| Hero Edit button | `settings.configuration.heroEditButton` |
| Hero Reveal button | `settings.configuration.heroRevealButton` |
| Hero Resident badge | `settings.configuration.heroResidentBadge` |
| List search field | `settings.configuration.listSearch` |
| List "+ New" button | `settings.configuration.listNewButton` |

---

## Verification

1. Open Settings › Configuration; confirm hero gradient matches the selected agent's `color`
2. Switch agents in the list; confirm gradient animates to new color
3. Toggle `agent.isResident`; confirm pin dot and "📌 Resident" badge appear/disappear
4. Type in search field; confirm list filters live
5. Clear search on section switch
6. Click a skill chip; confirm Settings navigates to Skills › that skill
7. Open in light mode; confirm all colors flip correctly, gradient unchanged
8. Select a Group; confirm "Members & Roles" chips show correct role colors
9. Select a Skill; confirm "Triggers" chips are blue, "Used by" chips are green
10. Select an MCP; confirm "Transport" chips are slate, command shows correctly
11. Permissions section: confirm no Edit button appears in hero
12. Templates section: confirm `TemplatesSettingsTab` renders (not the hero layout)
