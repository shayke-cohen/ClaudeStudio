# ClaudPeer Accessibility Identifiers

## When to Activate

Use whenever you add or edit SwiftUI in ClaudPeer that users, AppXray, or UI automation interact with. Required for buttons, fields, lists, dynamic rows, and meaningful containers (per project `CLAUDE.md`).

## Process

1. **Naming pattern** — Dot-separated **`viewName.elementName`** in **camelCase**, e.g., `chat.sendButton`, `sidebar.conversationList`. Never reuse an identifier across different views.
2. **Dynamic rows** — Suffix with stable id: `sidebar.conversationRow.\(conversation.id.uuidString)` so automation targets one row.
3. **Modifier choice** — Use `.accessibilityIdentifier("…")` for automation hooks. For **icon-only** controls, add **both** `.accessibilityIdentifier(...)` and `.accessibilityLabel("Human-readable action")`. Text buttons often need identifier only.
4. **Decorative noise** — Use `.accessibilityElement(children: .ignore)` on purely decorative wrappers so the tree stays navigable.
5. **Prefix map** — Align with existing prefixes: `mainWindow.*`, `sidebar.*`, `chat.*`, `inspector.*`, `newSession.*`, `agentLibrary.*`, `agentEditor.*`, `agentCard.*`, `messageBubble.*`, `toolCall.*`, `codeBlock.*`, `statusBadge.*`, `streamingIndicator`, `infoRow.*`. New surfaces pick a **unique camelCase prefix** and document it beside peers.
6. **New views** — Audit every interactive control: TextField, TextEditor, Picker, Toggle, Stepper, List/ScrollView container, toolbar items. Ship identifiers in the same PR as the feature.

## Checklist

- [ ] Pattern `viewName.elementName` camelCase with dots
- [ ] Dynamic `ForEach` rows include `.\(id.uuidString)`
- [ ] Icon-only buttons have label + identifier
- [ ] Decorative groups hidden from a11y when appropriate
- [ ] Prefix matches the view’s namespace; no duplicates
- [ ] Containers (lists/scroll) have identifiers

## Tips

Run AppXray in DEBUG with `@testId("chat.sendButton")`-style selectors. Prefer identifiers over fragile button title strings when titles localize. When splitting views, keep prefixes consistent so tests survive refactors.
