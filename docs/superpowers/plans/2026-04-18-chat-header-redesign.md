# Chat Header Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the broken chat header (shows first-message topic, routing jargon, raw skill chips) with a clean group/agent identity header that leads with WHO you're talking to.

**Architecture:** Three targeted edits to `ChatView.swift` (identity row, mission section, remove chips) + one edit to `MainWindowView.swift` (window title format) + one property added to `WindowState`. No new files. No new dependencies.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, macOS 14+

---

## File Map

| File | Change |
|---|---|
| `Odyssey/Services/WindowState.swift` | Add `var chatTitle: String?` |
| `Odyssey/Views/MainWindow/MainWindowView.swift:86,488-513` | Update `WindowTitleSetter` call site + struct |
| `Odyssey/Views/MainWindow/ChatView.swift:1087-1136` | Redesign `simplifiedChatHeader` layout |
| `Odyssey/Views/MainWindow/ChatView.swift:968-1005` | Replace `agentIconButton` with `headerAvatarView` |
| `Odyssey/Views/MainWindow/ChatView.swift:1141-~1205` | Remove mode toggle + delegation badge from `simplifiedHeaderStatusPills` |
| `Odyssey/Views/MainWindow/ChatView.swift:1206-1248` | Move delegation badge into `simplifiedSessionMenu` |
| `Odyssey/Views/MainWindow/ChatView.swift:1254-1360` | Redesign `simplifiedMissionSection` |
| `Odyssey/Views/MainWindow/ChatView.swift:1360-1410` | Add delegation + mission items to `simplifiedSessionMenu` |

---

## Task 1: Add chatTitle to WindowState + update WindowTitleSetter

**Files:**
- Modify: `Odyssey/Services/WindowState.swift` (after `selectedConversationId` block, ~line 248)
- Modify: `Odyssey/Views/MainWindow/MainWindowView.swift:488-513` (WindowTitleSetter struct)
- Modify: `Odyssey/Views/MainWindow/MainWindowView.swift:86` (call site)

- [ ] **Step 1: Add chatTitle property to WindowState**

Open `Odyssey/Services/WindowState.swift`. After the `selectedGroupId` block (around line 250), add:

```swift
/// Set by ChatView when the active conversation's agent/group name is known.
/// Used by WindowTitleSetter to build the breadcrumb title.
var chatTitle: String? = nil
```

- [ ] **Step 2: Rewrite WindowTitleSetter in MainWindowView.swift**

Replace lines 488–513 with:

```swift
private struct WindowTitleSetter: NSViewRepresentable {
    let projectName: String
    let chatTitle: String?

    private var computedTitle: String {
        guard let name = chatTitle, !name.isEmpty else { return projectName }
        let isDefaultProject = projectName == "Playground" || projectName == "No Project"
        return isDefaultProject ? name : "\(projectName) / \(name)"
    }

    func makeNSView(context: Context) -> NSView {
        TitleSettingView(title: computedTitle)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? TitleSettingView)?.setTitle(computedTitle)
    }

    private final class TitleSettingView: NSView {
        private var title: String

        init(title: String) {
            self.title = title
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        func setTitle(_ newTitle: String) {
            title = newTitle
            window?.title = newTitle
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.title = title
        }
    }
}
```

- [ ] **Step 3: Update the call site at line 86**

Change:
```swift
.background(WindowTitleSetter(projectName: windowState.projectName))
```
To:
```swift
.background(WindowTitleSetter(projectName: windowState.projectName, chatTitle: windowState.chatTitle))
```

- [ ] **Step 4: Build check**

```bash
cd /Users/shayco/Odyssey && make build-check
```
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Odyssey/Services/WindowState.swift Odyssey/Views/MainWindow/MainWindowView.swift
git commit -m "feat: window title breadcrumb format (ProjectName / GroupName)"
```

---

## Task 2: Add resolvedChatTitle computed property + set it from ChatView

**Files:**
- Modify: `Odyssey/Views/MainWindow/ChatView.swift` (near `sourceGroup` computed var at line 2257)

- [ ] **Step 1: Add resolvedChatTitle computed property to ChatView**

Find `sourceGroup` at line 2257:
```swift
private var sourceGroup: AgentGroup? {
    guard let gid = conversation?.sourceGroupId else { return nil }
    return allGroups.first { $0.id == gid }
}
```

Directly after it, add:
```swift
private var resolvedChatTitle: String? {
    if let group = sourceGroup { return group.name }
    if let agent = primarySession?.agent { return agent.name }
    return nil
}
```

- [ ] **Step 2: Sync chatTitle into WindowState from simplifiedChatHeader**

In `simplifiedChatHeader` (line 1087), find the closing `.padding` modifiers (around line 1136):
```swift
.padding(.horizontal, 16)
.padding(.vertical, 10)
```

Add after them:
```swift
.task(id: resolvedChatTitle) {
    windowState.chatTitle = resolvedChatTitle
}
```

- [ ] **Step 3: Build check**

```bash
cd /Users/shayco/Odyssey && make build-check
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Odyssey/Views/MainWindow/ChatView.swift
git commit -m "feat: sync agent/group name into window title via WindowState.chatTitle"
```

---

## Task 3: New identity header row

Replace the topic title + routing subtitle + agentIconButton cluster with a proper identity row that shows the group/agent name, a type badge, and per-member status dots.

**Files:**
- Modify: `Odyssey/Views/MainWindow/ChatView.swift`

- [ ] **Step 1: Add headerAvatarView property**

Find `agentIconButton` at line 968. Add a new computed property BEFORE it (so around line 967):

```swift
@ViewBuilder
private var headerAvatarView: some View {
    if let convo = conversation, convo.sessions.count > 1 {
        HStack(spacing: -6) {
            ForEach(convo.sessions.prefix(3), id: \.id) { s in
                if let ag = s.agent {
                    Image(systemName: ag.icon)
                        .foregroundStyle(Color.fromAgentColor(ag.color))
                        .font(.caption)
                        .padding(5)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
        }
        .xrayId("chat.groupAvatarStack")
    } else if let agent = primarySession?.agent {
        Image(systemName: agent.icon)
            .foregroundStyle(Color.fromAgentColor(agent.color))
            .font(.title3)
            .frame(width: 32, height: 32)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .xrayId("chat.agentAvatar")
    } else {
        Image(systemName: "bubble.left.and.bubble.right.fill")
            .foregroundStyle(.blue)
            .font(.title3)
            .xrayId("chat.chatIcon")
    }
}
```

- [ ] **Step 2: Add headerIdentityInfo property**

After `headerAvatarView`, add:

```swift
@ViewBuilder
private var headerIdentityInfo: some View {
    VStack(alignment: .leading, spacing: 3) {
        // Name row with type badge
        HStack(spacing: 6) {
            if let group = sourceGroup {
                Text(group.name)
                    .font(.headline)
                    .lineLimit(1)
                    .xrayId("chat.identityName")
                Text("GROUP")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.indigo.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.indigo)
                    .xrayId("chat.identityTypeBadge")
            } else if let agent = primarySession?.agent {
                Text(agent.name)
                    .font(.headline)
                    .lineLimit(1)
                    .xrayId("chat.identityName")
                Text("AGENT")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.blue)
                    .xrayId("chat.identityTypeBadge")
            } else {
                Text("Chat")
                    .font(.headline)
                    .xrayId("chat.identityName")
            }
        }

        // Member status dots (group) or agent status (1:1)
        if let convo = conversation, convo.sessions.count > 1 {
            HStack(spacing: 8) {
                ForEach(convo.sessions, id: \.id) { session in
                    if let ag = session.agent {
                        HStack(spacing: 3) {
                            let isActive = appState.sessionActivity[session.id.uuidString]?.isActive == true
                            Circle()
                                .fill(isActive ? Color.green : Color.secondary.opacity(0.35))
                                .frame(width: 5, height: 5)
                            Text(ag.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .xrayId("chat.memberStatus.\(session.id.uuidString)")
                    }
                }
            }
        } else if let session = primarySession {
            HStack(spacing: 3) {
                let isActive = appState.sessionActivity[session.id.uuidString]?.isActive == true
                Circle()
                    .fill(isActive ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 5, height: 5)
                Text(isActive ? "Running" : "Idle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .xrayId("chat.agentStatus")
        }
    }
}
```

- [ ] **Step 3: Update simplifiedChatHeader to use new identity views**

Replace lines 1087–1136 (`simplifiedChatHeader`) with:

```swift
private var simplifiedChatHeader: some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .center, spacing: 10) {
            headerAvatarView

            if isEditingTopic {
                TextField("Conversation name", text: $editedTopic)
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)
                    .focused($topicFieldFocused)
                    .frame(maxWidth: 320)
                    .onSubmit { commitRename() }
                    .onExitCommand { cancelRename() }
                    .xrayId("chat.topicField")
            } else {
                headerIdentityInfo
            }

            Spacer()

            simplifiedHeaderStatusPills

            if let convo = conversation {
                simplifiedSessionMenu(convo)
            }
        }

        simplifiedMissionSection

        if hasRecoverableInterruption {
            recoveryBanner
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .task(id: resolvedChatTitle) {
        windowState.chatTitle = resolvedChatTitle
    }
}
```

Note: `headerChips` line is intentionally omitted — removed in Task 6.

- [ ] **Step 4: Build check**

```bash
cd /Users/shayco/Odyssey && make build-check
```
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Odyssey/Views/MainWindow/ChatView.swift
git commit -m "feat: identity header row with group/agent name, type badge, member status"
```

---

## Task 4: Segmented mode control + move delegation to ⋯

Replace the `executionModeToggleButton` capsule with a compact `Interactive / Auto` segmented picker. Move `delegationBadgeButton` into the ⋯ menu.

**Files:**
- Modify: `Odyssey/Views/MainWindow/ChatView.swift`

- [ ] **Step 1: Add executionModeSegmented property**

After `executionModeToggleButton` (around line 1562), add:

```swift
@ViewBuilder
private var executionModeSegmented: some View {
    if supportsExecutionModeToggle {
        Picker(
            "Mode",
            selection: Binding(
                get: { isAutonomousModeEnabled },
                set: { _ in handleExecutionModeToggle() }
            )
        ) {
            Text("Interactive").tag(false)
            Text("Auto").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 130)
        .xrayId("chat.executionModeSegmented")
        .accessibilityLabel("Execution mode")
    }
}
```

- [ ] **Step 2: Find executionModeToggleButton and delegationBadgeButton calls in simplifiedHeaderStatusPills**

Run:
```bash
grep -n "executionModeToggleButton\|delegationBadgeButton\|delegationBadge" /Users/shayco/Odyssey/Odyssey/Views/MainWindow/ChatView.swift | head -20
```

Note the line numbers — you'll remove those calls in the next step.

- [ ] **Step 3: Remove executionModeToggleButton and delegationBadgeButton from simplifiedHeaderStatusPills**

In `simplifiedHeaderStatusPills`, delete:
- The line(s) that call `executionModeToggleButton`
- The line(s) that call `delegationBadgeButton(convo)` or similar

These are now handled by `executionModeSegmented` (in the header row) and the ⋯ menu (Task 5).

- [ ] **Step 4: Add executionModeSegmented to simplifiedChatHeader HStack**

In `simplifiedChatHeader` (from Task 3 code), the controls area is:
```swift
simplifiedHeaderStatusPills

if let convo = conversation {
    simplifiedSessionMenu(convo)
}
```

Change to:
```swift
simplifiedHeaderStatusPills

executionModeSegmented

if let convo = conversation {
    simplifiedSessionMenu(convo)
}
```

- [ ] **Step 5: Build check**

```bash
cd /Users/shayco/Odyssey && make build-check
```
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Odyssey/Views/MainWindow/ChatView.swift
git commit -m "feat: segmented Interactive/Auto mode control in chat header"
```

---

## Task 5: Relocate delegation badge + add mission to ⋯ menu

The delegation badge (`Auto-Answer ▾`) must stay in the view tree — its popover is anchored to it and can't be triggered from a `Menu`. Move it out of `simplifiedHeaderStatusPills` into the `simplifiedChatHeader` HStack directly. Add mission items to ⋯ menu.

**Files:**

- Modify: `Odyssey/Views/MainWindow/ChatView.swift`

- [ ] **Step 1: Remove delegationBadgeButton call from simplifiedHeaderStatusPills**

Run to find the exact call line:

```bash
grep -n "delegationBadge\b" /Users/shayco/Odyssey/Odyssey/Views/MainWindow/ChatView.swift | head -10
```

In `simplifiedHeaderStatusPills`, delete the line(s) calling `delegationBadgeButton(...)`.

- [ ] **Step 2: Add delegationBadgeButton directly to simplifiedChatHeader HStack**

In the `simplifiedChatHeader` controls area (from Task 4):

```swift
simplifiedHeaderStatusPills

executionModeSegmented

if let convo = conversation {
    simplifiedSessionMenu(convo)
}
```

Change to:

```swift
simplifiedHeaderStatusPills

executionModeSegmented

if let convo = conversation {
    delegationBadgeButton(convo, isActive: convo.delegationMode != .off)
    simplifiedSessionMenu(convo)
}
```

This preserves the popover anchor while removing it from the status-pill cluster.

- [ ] **Step 3: Add Mission items to simplifiedSessionMenu**

In `simplifiedSessionMenu(_ convo:)` (line 1360), after the existing `Divider()` near the top, add:

```swift
Section("Mission") {
    Button {
        beginMissionEdit()
    } label: {
        Label(
            currentMissionText == nil ? "Set Mission…" : "Edit Mission…",
            systemImage: "scope"
        )
    }
    .xrayId("chat.sessionMenu.mission")

    if currentMissionText != nil {
        Button {
            scheduleDraft = makeScheduleDraft(from: latestUserChatMessage)
            showingScheduleEditor = true
        } label: {
            Label("Schedule…", systemImage: "calendar.badge.clock")
        }
        .xrayId("chat.sessionMenu.schedule")
    }
}
```

- [ ] **Step 4: Build check**

```bash
cd /Users/shayco/Odyssey && make build-check
```
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Odyssey/Views/MainWindow/ChatView.swift
git commit -m "feat: delegation badge relocated to header row; mission items added to ⋯ menu"
```

---

## Task 6: Redesign mission section — dashed link when empty, active bar when set

Replace the verbose empty state ("No mission yet | Add mission | Schedule") with: nothing (dashed `+ Add mission` link only) when empty, and a green bar when active.

**Files:**
- Modify: `Odyssey/Views/MainWindow/ChatView.swift:1254-1360` (`simplifiedMissionSection`)

- [ ] **Step 1: Replace simplifiedMissionSection**

Replace lines 1254–1360 with:

```swift
private var simplifiedMissionSection: some View {
    Group {
        if isEditingMission {
            // Editing state — keep existing editor UI unchanged
            VStack(alignment: .leading, spacing: 8) {
                TextField("Describe the mission for this thread", text: $editedMission, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($missionFieldFocused)
                    .lineLimit(2...5)
                    .onSubmit { commitMissionEdit() }
                    .xrayId("chat.missionEditor")

                HStack(spacing: 8) {
                    Button("Save") { commitMissionEdit() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .xrayId("chat.missionSaveButton")

                    Button("Cancel") { cancelMissionEdit() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .xrayId("chat.missionCancelButton")
                }
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
            .xrayId("chat.missionCard")

        } else if let mission = currentMissionText {
            // Active mission bar
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "scope")
                    .font(.caption)
                    .foregroundStyle(.green)

                Text(mission)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(isMissionExpanded ? nil : 2)
                    .xrayId("chat.missionText")

                Spacer()

                Button(isMissionExpanded ? "Less" : "More") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isMissionExpanded.toggle()
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .xrayId("chat.missionToggleButton")

                Button("Edit") { beginMissionEdit() }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                    .xrayId("chat.missionEditButton")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.18), lineWidth: 1))
            .xrayId("chat.missionActiveBar")

        } else {
            // Empty state: subtle dashed link
            Button { beginMissionEdit() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                        .font(.caption2)
                    Text("Add mission")
                        .font(.caption2)
                }
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [3]))
                        .foregroundStyle(.quaternary)
                )
            }
            .buttonStyle(.plain)
            .xrayId("chat.missionAddLink")
        }
    }
}
```

- [ ] **Step 2: Build check**

```bash
cd /Users/shayco/Odyssey && make build-check
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Odyssey/Views/MainWindow/ChatView.swift
git commit -m "feat: mission section — dashed add link when empty, green bar when active"
```

---

## Task 7: Remove headerChips from header layout

The skill/MCP chips are already accessible via the ⋯ menu's configuration links. Remove them from the visible header.

**Files:**
- Modify: `Odyssey/Views/MainWindow/ChatView.swift:1087-1136`

- [ ] **Step 1: Confirm headerChips is removed from simplifiedChatHeader**

The `simplifiedChatHeader` written in Task 3 already omits `headerChips`. Verify:

```bash
grep -n "headerChips" /Users/shayco/Odyssey/Odyssey/Views/MainWindow/ChatView.swift
```

Expected: no call inside `simplifiedChatHeader`. If it still appears there, remove it.

The `headerChips` property itself can remain defined — it's not harmful to keep dead code for now, and removing it is a separate cleanup.

- [ ] **Step 2: Build check + smoke test**

```bash
cd /Users/shayco/Odyssey && make feedback
```
Expected: BUILD SUCCEEDED + sidecar smoke passed

- [ ] **Step 3: Commit**

```bash
git add Odyssey/Views/MainWindow/ChatView.swift
git commit -m "feat: remove skill/MCP chips from chat header"
```

---

## Task 8: AppXray visual verification

With the app running (DEBUG build), confirm the new header renders correctly.

- [ ] **Step 1: Discover and connect AppXray**

```
mcp__appxray__session action:"discover"
```
Then:
```
mcp__appxray__session action:"connect" (use token from discover)
```

- [ ] **Step 2: Screenshot + tree check**

```
mcp__appxray__inspect
```

Verify:
- Window title shows `GroupName` or `ProjectName / GroupName` (not `Odyssey — ...`)
- Header shows group/agent name + GROUP/AGENT badge
- Member status dots visible
- No skill chips in header
- Mission shows dashed `Add mission` link (if no mission set) or green bar (if set)
- `Interactive / Auto` segmented control present
- ⋯ button present

- [ ] **Step 3: Test mode toggle**

```
mcp__appxray__act selector:"@testId('chat.executionModeSegmented')" action:"click"
```
Verify mode changes.

- [ ] **Step 4: Test mission add link**

```
mcp__appxray__act selector:"@testId('chat.missionAddLink')" action:"click"
```
Verify mission editor opens.

- [ ] **Step 5: Final commit if any fixups applied**

```bash
cd /Users/shayco/Odyssey
git add -p
git commit -m "fix: chat header post-redesign visual fixups"
```
