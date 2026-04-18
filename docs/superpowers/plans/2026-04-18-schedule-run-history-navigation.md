# Schedule Run History Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clicking a run history item in the Schedule Library dismisses the sheet, selects the conversation's project, expands the owning agent/group tree in the sidebar (including the Archived subfolder if needed), and focuses the chat.

**Architecture:** Add a `sidebarRevealConversationId` signal to `WindowState` plus a `navigateToConversation()` helper. `SidebarView` observes the signal with `onChange` and calls `expandForReveal()`. Archived-subfolder expansion is made possible by lifting `isArchivedExpanded` out of the row views into `SidebarView`-owned sets passed as bindings.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, `@Observable WindowState`

---

## Files

| File | Change |
|------|--------|
| `Odyssey/App/WindowState.swift` | Add `sidebarRevealConversationId: UUID?` and `navigateToConversation(_:projectId:)` |
| `Odyssey/Views/MainWindow/AgentSidebarRowView.swift` | Replace `@State private var isArchivedExpanded` with `var isArchivedExpanded: Binding<Bool>` |
| `Odyssey/Views/GroupLibrary/GroupSidebarRowView.swift` | Same as above |
| `Odyssey/Views/MainWindow/SidebarView.swift` | Add `expandedArchivedAgentIds`/`expandedArchivedGroupIds`, pass bindings to row views, add `onChange` + `expandForReveal` |
| `Odyssey/Views/Schedules/ScheduleDetailView.swift` | Use `navigateToConversation` in `runRow`, `historyCard`, and `ScheduleHistorySheet` |

---

### Task 1: Add `sidebarRevealConversationId` and `navigateToConversation` to `WindowState`

**Files:**
- Modify: `Odyssey/App/WindowState.swift`

- [ ] **Step 1: Open `Odyssey/App/WindowState.swift` and find the `selectedConversationId` property (around line 238). Add the new signal property directly after `selectedGroupId`.**

  After `var selectedGroupId: UUID?` and its `didSet`, add:

  ```swift
  var sidebarRevealConversationId: UUID? = nil
  ```

- [ ] **Step 2: Add `navigateToConversation(_:projectId:)` as a method on `WindowState`. Place it after the `closeSettings()` method.**

  ```swift
  func navigateToConversation(_ conversationId: UUID, projectId: UUID?) {
      if let projectId { selectProject(id: projectId, preserveSelection: true) }
      selectedConversationId = conversationId
      sidebarRevealConversationId = conversationId
      showScheduleLibrary = false
  }
  ```

- [ ] **Step 3: Build check — confirm no errors introduced.**

  ```bash
  cd /Users/shayco/Odyssey && make build-check
  ```

  Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit.**

  ```bash
  cd /Users/shayco/Odyssey
  git add Odyssey/App/WindowState.swift
  git commit -m "feat: add sidebarRevealConversationId signal and navigateToConversation to WindowState"
  ```

---

### Task 2: Lift `isArchivedExpanded` out of `AgentSidebarRowView`

**Files:**
- Modify: `Odyssey/Views/MainWindow/AgentSidebarRowView.swift`

- [ ] **Step 1: Replace the `@State` with a `@Binding` property.**

  Find line 28:
  ```swift
  @State private var isArchivedExpanded = false
  ```
  Replace with:
  ```swift
  var isArchivedExpanded: Binding<Bool>
  ```

- [ ] **Step 2: Update the `DisclosureGroup` usage. Find line 102:**

  ```swift
  DisclosureGroup(isExpanded: $isArchivedExpanded) {
  ```
  Replace with:
  ```swift
  DisclosureGroup(isExpanded: isArchivedExpanded) {
  ```

- [ ] **Step 3: Build check.**

  ```bash
  cd /Users/shayco/Odyssey && make build-check
  ```

  Expected: compiler errors about missing `isArchivedExpanded` at all `AgentSidebarRowView` call sites in `SidebarView.swift`. That's expected — Task 4 fixes those. For now just confirm the row view file itself compiles in isolation (no errors inside `AgentSidebarRowView.swift`).

  > Note: full build will fail until Task 4 updates the call sites. That's fine — proceed to Task 3.

- [ ] **Step 4: Commit.**

  ```bash
  cd /Users/shayco/Odyssey
  git add Odyssey/Views/MainWindow/AgentSidebarRowView.swift
  git commit -m "refactor: lift isArchivedExpanded to Binding in AgentSidebarRowView"
  ```

---

### Task 3: Lift `isArchivedExpanded` out of `GroupSidebarRowView`

**Files:**
- Modify: `Odyssey/Views/GroupLibrary/GroupSidebarRowView.swift`

- [ ] **Step 1: Replace the `@State` with a `@Binding` property.**

  Find line 29:
  ```swift
  @State private var isArchivedExpanded = false
  ```
  Replace with:
  ```swift
  var isArchivedExpanded: Binding<Bool>
  ```

- [ ] **Step 2: Update the `DisclosureGroup` usage. Find line 103:**

  ```swift
  DisclosureGroup(isExpanded: $isArchivedExpanded) {
  ```
  Replace with:
  ```swift
  DisclosureGroup(isExpanded: isArchivedExpanded) {
  ```

- [ ] **Step 3: Commit (build still failing at call sites — Task 4 fixes it).**

  ```bash
  cd /Users/shayco/Odyssey
  git add Odyssey/Views/GroupLibrary/GroupSidebarRowView.swift
  git commit -m "refactor: lift isArchivedExpanded to Binding in GroupSidebarRowView"
  ```

---

### Task 4: Update `SidebarView` — archived sets, bindings, `expandForReveal`

**Files:**
- Modify: `Odyssey/Views/MainWindow/SidebarView.swift`

- [ ] **Step 1: Add two new `@State` sets for archived expansion. Find the block of `@State` vars around line 154 (near `expandedAgentIds` and `expandedGroupIds`). Add after `expandedGroupIds`:**

  ```swift
  @State private var expandedArchivedAgentIds: Set<UUID> = []
  @State private var expandedArchivedGroupIds: Set<UUID> = []
  ```

- [ ] **Step 2: Pass `isArchivedExpanded` binding to `AgentSidebarRowView`. Find the `agentSidebarRow` function (around line 1511). Inside the `AgentSidebarRowView(...)` initializer, add after the existing `isExpanded:` binding:**

  ```swift
  isArchivedExpanded: Binding(
      get: { expandedArchivedAgentIds.contains(agent.id) },
      set: { if $0 { expandedArchivedAgentIds.insert(agent.id) } else { expandedArchivedAgentIds.remove(agent.id) } }
  ),
  ```

- [ ] **Step 3: Pass `isArchivedExpanded` binding to `GroupSidebarRowView`. Find the `groupSidebarRow` function (around line 1129). Inside the `GroupSidebarRowView(...)` initializer, add after the existing `isExpanded:` binding:**

  ```swift
  isArchivedExpanded: Binding(
      get: { expandedArchivedGroupIds.contains(group.id) },
      set: { if $0 { expandedArchivedGroupIds.insert(group.id) } else { expandedArchivedGroupIds.remove(group.id) } }
  ),
  ```

- [ ] **Step 4: Add `expandForReveal(_:)` private helper. Add this method near the bottom of `SidebarView`, alongside `conversationsForAgent` and `conversationsForGroup` (around line 1869):**

  ```swift
  private func expandForReveal(_ conversationId: UUID) {
      guard let convo = conversations.first(where: { $0.id == conversationId }) else { return }
      let isArchived = convo.isArchived

      if let groupId = convo.sourceGroupId {
          expandedGroupIds.insert(groupId)
          if isArchived { expandedArchivedGroupIds.insert(groupId) }
          return
      }

      for agent in agents {
          let inActive = conversationsForAgent(agent).contains { $0.id == conversationId }
          let inArchived = archivedConversationsForAgent(agent).contains { $0.id == conversationId }
          if inActive || inArchived {
              expandedAgentIds.insert(agent.id)
              if inArchived { expandedArchivedAgentIds.insert(agent.id) }
              return
          }
      }
  }
  ```

- [ ] **Step 5: Add `onChange` observer on the sidebar body. Find `var body: some View { sidebarWithSheets` (around line 202). Add the modifier to the `sidebarWithSheets` chain, alongside the existing `.alert(...)` modifiers:**

  ```swift
  .onChange(of: windowState.sidebarRevealConversationId) { _, convId in
      guard let convId else { return }
      expandForReveal(convId)
      windowState.sidebarRevealConversationId = nil
  }
  ```

- [ ] **Step 6: Build check — should now succeed.**

  ```bash
  cd /Users/shayco/Odyssey && make build-check
  ```

  Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Commit.**

  ```bash
  cd /Users/shayco/Odyssey
  git add Odyssey/Views/MainWindow/SidebarView.swift
  git commit -m "feat: expand agent/group/archived sidebar tree when navigating to conversation from schedule run"
  ```

---

### Task 5: Use `navigateToConversation` in `ScheduleDetailView`

**Files:**
- Modify: `Odyssey/Views/Schedules/ScheduleDetailView.swift`

- [ ] **Step 1: Update `runRow(_:)`. Find the `onTapGesture` in `runRow` (around line 245):**

  Current:
  ```swift
  .onTapGesture {
      if let convoId = run.conversationId {
          windowState.selectedConversationId = convoId
      }
  }
  ```

  Replace with:
  ```swift
  .onTapGesture {
      if let convoId = run.conversationId {
          let convo = conversations.first { $0.id == convoId }
          windowState.navigateToConversation(convoId, projectId: convo?.projectId)
      }
  }
  ```

- [ ] **Step 2: Update `historyCard(_:)` — the `ScheduleRunListSheet` closure. Find around line 204:**

  Current:
  ```swift
  ScheduleRunListSheet(runs: scheduleRuns) { convoId in
      windowState.selectedConversationId = convoId
      showingAllRuns = false
  }
  ```

  Replace with:
  ```swift
  ScheduleRunListSheet(runs: scheduleRuns) { convoId in
      let convo = conversations.first { $0.id == convoId }
      windowState.navigateToConversation(convoId, projectId: convo?.projectId)
      showingAllRuns = false
  }
  ```

- [ ] **Step 3: Update `ScheduleHistorySheet` — its `onSelect` closure (around line 428). Find:**

  Current:
  ```swift
  ScheduleRunListSheet(runs: runs) { convoId in
      if let convo = conversations.first(where: { $0.id == convoId }) {
          if let projectId = convo.projectId {
              windowState.selectProject(id: projectId, preserveSelection: true)
          }
          windowState.selectedConversationId = convoId
      }
      dismiss()
  }
  ```

  Replace with:
  ```swift
  ScheduleRunListSheet(runs: runs) { convoId in
      let convo = conversations.first { $0.id == convoId }
      windowState.navigateToConversation(convoId, projectId: convo?.projectId)
      dismiss()
  }
  ```

- [ ] **Step 4: Build check.**

  ```bash
  cd /Users/shayco/Odyssey && make build-check
  ```

  Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit.**

  ```bash
  cd /Users/shayco/Odyssey
  git add Odyssey/Views/Schedules/ScheduleDetailView.swift
  git commit -m "feat: schedule run history items navigate to chat and expand sidebar tree"
  ```

---

### Task 6: Full feedback check

- [ ] **Step 1: Run full feedback suite.**

  ```bash
  cd /Users/shayco/Odyssey && make feedback
  ```

  Expected: build succeeded + sidecar smoke passes.

- [ ] **Step 2: Manual smoke test.**

  1. Open Odyssey, open the Schedule Library (clock icon in sidebar)
  2. Select a schedule with at least one completed run that has a `conversationId`
  3. Click a run row — verify: sheet dismisses, sidebar expands the owning agent/group, conversation is selected and visible
  4. Re-open Schedule Library, click "View all (N)" — repeat the same verification from the all-runs sheet
  5. Test with an archived conversation run: verify the "Archived" subfolder also expands

