# Group Icon — Diamond Mesh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the per-group emoji icon with a fixed `GroupIconView` that renders the chosen diamond-mesh design (4 Claude icons at N/E/S/W positions, fully connected by white lines, on terracotta orange).

**Architecture:** Add `ClaudeIcon` as an xcassets image set, then create a single SwiftUI `GroupIconView` parameterised by `size`. Replace every `Text(group.icon)` icon-display site (13 call sites across 10 views) with `GroupIconView(size:)`. The `group.icon` emoji field remains in the model for potential future use, but is no longer rendered as the visual identity.

**Tech Stack:** Swift 6 / SwiftUI, Canvas for connection lines, xcassets imageset, sips for PNG resize, `make build-check` for verification.

---

### Task 1: Add `ClaudeIcon` image asset

**Files:**
- Create: `Odyssey/Resources/Assets.xcassets/ClaudeIcon.imageset/Contents.json`
- Create: `Odyssey/Resources/Assets.xcassets/ClaudeIcon.imageset/ClaudeIcon.png` (256×256)
- Create: `Odyssey/Resources/Assets.xcassets/ClaudeIcon.imageset/ClaudeIcon@2x.png` (512×512)

- [ ] **Step 1: Create the imageset directory and copy source PNG as @2x**

```bash
mkdir -p Odyssey/Resources/Assets.xcassets/ClaudeIcon.imageset
cp docs/icon-concepts/source-icon.png \
   Odyssey/Resources/Assets.xcassets/ClaudeIcon.imageset/ClaudeIcon@2x.png
```

- [ ] **Step 2: Generate the @1x (256×256) variant using sips**

```bash
sips --resampleWidth 256 \
  docs/icon-concepts/source-icon.png \
  --out Odyssey/Resources/Assets.xcassets/ClaudeIcon.imageset/ClaudeIcon.png
```

Expected: `ClaudeIcon.png` created at 256×256.

- [ ] **Step 3: Write `Contents.json`**

Create `Odyssey/Resources/Assets.xcassets/ClaudeIcon.imageset/Contents.json`:

```json
{
  "images": [
    {
      "filename": "ClaudeIcon.png",
      "idiom": "universal",
      "scale": "1x"
    },
    {
      "filename": "ClaudeIcon@2x.png",
      "idiom": "universal",
      "scale": "2x"
    },
    {
      "idiom": "universal",
      "scale": "3x"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

- [ ] **Step 4: Verify asset is readable (quick build check)**

```bash
make build-check
```

Expected: BUILD SUCCEEDED with no errors about missing resources.

- [ ] **Step 5: Commit**

```bash
git add Odyssey/Resources/Assets.xcassets/ClaudeIcon.imageset/
git commit -m "feat: add ClaudeIcon image asset for group icon"
```

---

### Task 2: Create `GroupIconView`

**Files:**
- Create: `Odyssey/Views/Components/GroupIconView.swift`

- [ ] **Step 1: Create the view file**

Create `Odyssey/Views/Components/GroupIconView.swift`:

```swift
import SwiftUI

/// Diamond-mesh icon used for every AgentGroup throughout the app.
/// Four Claude icons at N/E/S/W positions, fully connected by white lines,
/// on the standard terracotta orange background.
struct GroupIconView: View {
    var size: CGFloat = 36

    private var radius: CGFloat   { size * 0.343 }
    private var nodeSize: CGFloat { size * 0.286 }
    private var lineWidth: CGFloat { max(1, size * 0.018) }
    private var dotRadius: CGFloat { size * 0.022 }

    private var nodes: [CGPoint] {
        let c = size / 2
        return [
            CGPoint(x: c,          y: c - radius),
            CGPoint(x: c + radius, y: c),
            CGPoint(x: c,          y: c + radius),
            CGPoint(x: c - radius, y: c),
        ]
    }

    private static let pairs: [(Int, Int)] =
        [(0,1),(0,2),(0,3),(1,2),(1,3),(2,3)]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.229, style: .continuous)
                .fill(Color(red: 192/255, green: 112/255, blue: 72/255))

            Canvas { ctx, _ in
                let pts = self.nodes
                let lw  = self.lineWidth
                let dr  = self.dotRadius
                for (i, j) in Self.pairs {
                    var path = Path()
                    path.move(to: pts[i])
                    path.addLine(to: pts[j])
                    ctx.stroke(path, with: .color(.white.opacity(0.65)), lineWidth: lw)
                }
                for pt in pts {
                    ctx.fill(
                        Path(ellipseIn: CGRect(
                            x: pt.x - dr, y: pt.y - dr,
                            width: dr * 2, height: dr * 2
                        )),
                        with: .color(.white.opacity(0.8))
                    )
                }
            }

            ForEach(0..<4, id: \.self) { i in
                Image("ClaudeIcon")
                    .resizable()
                    .frame(width: nodeSize, height: nodeSize)
                    .position(nodes[i])
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    HStack(spacing: 16) {
        GroupIconView(size: 24)
        GroupIconView(size: 28)
        GroupIconView(size: 36)
        GroupIconView(size: 40)
        GroupIconView(size: 48)
        GroupIconView(size: 64)
    }
    .padding()
}
```

- [ ] **Step 2: Add file to Xcode project via xcodegen regenerate**

```bash
xcodegen generate
```

Expected: project.pbxproj updated, no errors.

- [ ] **Step 3: Build check**

```bash
make build-check
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Odyssey/Views/Components/GroupIconView.swift
git commit -m "feat: add GroupIconView — diamond mesh with 4 Claude icons"
```

---

### Task 3: Replace icons in primary group views

**Files:**
- Modify: `Odyssey/Views/GroupLibrary/GroupCardView.swift:13-17`
- Modify: `Odyssey/Views/GroupLibrary/GroupSidebarRowView.swift:180-191` (header, 28×28)
- Modify: `Odyssey/Views/GroupLibrary/GroupSidebarRowView.swift:369-374` (thread mini, 24×24)

- [ ] **Step 1: Replace in `GroupCardView`**

In `Odyssey/Views/GroupLibrary/GroupCardView.swift`, replace:

```swift
Text(group.icon)
    .font(.title2)
    .frame(width: 36, height: 36)
    .background(Color.fromAgentColor(group.color).opacity(0.15))
    .clipShape(RoundedRectangle(cornerRadius: 8))
```

with:

```swift
GroupIconView(size: 36)
```

- [ ] **Step 2: Replace in `GroupSidebarRowView` — header icon (28×28)**

In `Odyssey/Views/GroupLibrary/GroupSidebarRowView.swift`, replace the ZStack at line ~180:

```swift
ZStack {
    RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(LinearGradient(
            colors: [tint.opacity(isSelected ? 0.22 : 0.18), tint.opacity(isSelected ? 0.10 : 0.08)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ))
    RoundedRectangle(cornerRadius: 9, style: .continuous)
        .stroke(tint.opacity(isSelected ? 0.28 : 0.16), lineWidth: 1)
    Text(group.icon)
        .font(.system(size: 16))
}
.frame(width: 28, height: 28)
```

with:

```swift
GroupIconView(size: 28)
```

- [ ] **Step 3: Replace in `GroupSidebarRowView` — thread mini icon (24×24)**

In `Odyssey/Views/GroupLibrary/GroupSidebarRowView.swift`, replace the ZStack at line ~369:

```swift
ZStack {
    RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(
            LinearGradient(
                colors: [tint.opacity(0.18), tint.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(tint.opacity(0.14), lineWidth: 1)
    Text(group.icon)
        .font(.system(size: 13))
}
.frame(width: 24, height: 24)
```

with:

```swift
GroupIconView(size: 24)
```

- [ ] **Step 4: Build check**

```bash
make build-check
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add Odyssey/Views/GroupLibrary/GroupCardView.swift \
        Odyssey/Views/GroupLibrary/GroupSidebarRowView.swift
git commit -m "feat: use GroupIconView in GroupCardView and GroupSidebarRowView"
```

---

### Task 4: Replace icons in remaining views

**Files:**
- Modify: `Odyssey/Views/GroupLibrary/GroupDetailView.swift:78-81` (64×64)
- Modify: `Odyssey/Views/GroupLibrary/GroupPopoverView.swift:37-41` (40×40)
- Modify: `Odyssey/Views/GroupLibrary/AutonomousMissionSheet.swift:28` (inline)
- Modify: `Odyssey/Views/MainWindow/ChatView.swift:2438-2442` (64×64 empty state)
- Modify: `Odyssey/Views/MainWindow/AgentBrowseSheet.swift:311-315` (40×40)
- Modify: `Odyssey/Views/MainWindow/WelcomeView.swift:264` (inline)
- Modify: `Odyssey/Views/MainWindow/AddAgentsToChatSheet.swift:72` (inline)
- Modify: `Odyssey/Views/MainWindow/InspectorView.swift:659-663` (48×48)

- [ ] **Step 1: `GroupDetailView` — 64×64 header icon**

Replace:
```swift
Text(group.icon)
    .font(.system(size: 40))
    .frame(width: 64, height: 64)
    .background(Color.fromAgentColor(group.color).opacity(0.15))
    .clipShape(RoundedRectangle(cornerRadius: 16))
```
with:
```swift
GroupIconView(size: 64)
```

- [ ] **Step 2: `GroupPopoverView` — 40×40 header icon**

Replace:
```swift
Text(group.icon)
    .font(.title3)
    .frame(width: 40, height: 40)
    .background(Color.fromAgentColor(group.color).opacity(0.15))
    .clipShape(RoundedRectangle(cornerRadius: 10))
```
with:
```swift
GroupIconView(size: 40)
```

- [ ] **Step 3: `AutonomousMissionSheet` — inline icon**

Replace:
```swift
Text(group.icon)
```
with:
```swift
GroupIconView(size: 20)
```

- [ ] **Step 4: `ChatView` — 64×64 empty state header**

Replace:
```swift
Text(group.icon)
    .font(.system(size: 40))
    .frame(width: 64, height: 64)
    .background(Color.fromAgentColor(group.color).opacity(0.12))
    .clipShape(RoundedRectangle(cornerRadius: 16))
```
with:
```swift
GroupIconView(size: 64)
```

- [ ] **Step 5: `AgentBrowseSheet` — 40×40 header icon**

Replace:
```swift
Text(group.icon)
    .font(.title2)
    .frame(width: 40, height: 40)
    .background(Color.fromAgentColor(group.color).opacity(0.12))
    .clipShape(RoundedRectangle(cornerRadius: 9))
```
with:
```swift
GroupIconView(size: 40)
```

- [ ] **Step 6: `WelcomeView` — inline icon**

Replace:
```swift
Text(group.icon)
    .font(.title3)
```
with:
```swift
GroupIconView(size: 24)
```

- [ ] **Step 7: `AddAgentsToChatSheet` — inline icon**

Replace:
```swift
Text(group.icon)
```
with:
```swift
GroupIconView(size: 20)
```

- [ ] **Step 8: `InspectorView` — 48×48 icon**

Replace:
```swift
Text(group.icon)
    .font(.title)
    .frame(width: 48, height: 48)
    .background(Color.fromAgentColor(group.color).opacity(0.15))
    .clipShape(RoundedRectangle(cornerRadius: 12))
```
with:
```swift
GroupIconView(size: 48)
```

- [ ] **Step 9: Build check**

```bash
make build-check
```

Expected: BUILD SUCCEEDED, no warnings about unused `group.icon` (it remains in the model).

- [ ] **Step 10: Commit**

```bash
git add Odyssey/Views/GroupLibrary/GroupDetailView.swift \
        Odyssey/Views/GroupLibrary/GroupPopoverView.swift \
        Odyssey/Views/GroupLibrary/AutonomousMissionSheet.swift \
        Odyssey/Views/MainWindow/ChatView.swift \
        Odyssey/Views/MainWindow/AgentBrowseSheet.swift \
        Odyssey/Views/MainWindow/WelcomeView.swift \
        Odyssey/Views/MainWindow/AddAgentsToChatSheet.swift \
        Odyssey/Views/MainWindow/InspectorView.swift
git commit -m "feat: replace group emoji icon with GroupIconView across all views"
```
