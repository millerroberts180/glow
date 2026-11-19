# ADR 0003: Collapsing Glow's mark into Line Apps' line

- **Status:** Accepted, 2026-11-13
- **Shared code:** `Sources/GlowApp/LineAppsFold.swift`, the same file in Tuck, Pulse and Hum; the copy in the line-apps repository (`Shared/LineAppsFold.swift`) is the one to change first

## Context

Line Apps is a menu-bar app in the bundle that shows a short line. A click collapses Tuck's, Pulse's, Hum's and Glow's icons into it, and the line bends into the Line Apps curl; another click brings them back. It says so with a distributed notification, `com.millerroberts.lineapps.fold` or `.unfold`, carrying the line's mid x.

The other three apps make their status items in AppKit and hide them with `isVisible`. Glow's mark is a SwiftUI `MenuBarExtra`, its only scene, which SwiftUI makes and owns.

## Decisions

### 1. The mark goes with `MenuBarExtra(isInserted:)`

- `MenuBarMark.shared.isInserted` is bound to the scene. `LineAppsFold` sets it false to collapse the mark and true to bring it back.
- SwiftUI makes the status item anew each time it's inserted, so the fold finds the button in its window each time (`StatusItemMenu.statusButton(in:)`) to fade it.

### 2. `isInserted` is announced only when it changes

- Taking the mark out, SwiftUI writes `false` back through the binding. With `@Published`, each write announced a change, which made the scene anew, which wrote again: Glow's main thread stayed at about 100% for as long as the mark was out (a sample showed `scenesDidChange` and `makeMainMenu` in a loop).
- `MenuBarMark` is a plain `ObservableObject` whose `isInserted` sends `objectWillChange` only for a real change. While collapsed, Glow sits at 0.0% CPU.

### 3. The mark comes back where it was

- macOS forgets a hidden status item's place and brings it back at the far left. The fold notes `NSStatusItem Preferred Position Item-0` (SwiftUI's name for Glow's one item) as the mark goes and writes it back just before it's inserted again.
- SwiftUI reads `NSStatusItem Visible Item-0` as it makes the item. A quit while collapsed can leave it false, so `MenuBarMark` clears it before the scene is made, and the fold clears it each time the mark comes back.

### 4. A way in while collapsed

Opening Glow again, from Finder or Glow in the line's right-click menu, opens Settings (`applicationShouldHandleReopen`).

### 5. Collapsed holds only while Line Apps runs

Glow reads the state (`folded` in Line Apps' defaults) at launch only if Line Apps is running, and while collapsed it watches for Line Apps terminating, so the mark is never left out of reach.

## Consequences

- Checked on a macOS 15 test Mac, a virtual machine, from the release bundle: the mark collapses and comes back at its place, Glow Desk and the right-click menu work after it does, and Glow stays at 0.0% CPU while collapsed.
- `HostedWindow` closes Glow Desk by clicking the mark; with the mark collapsed there is no Desk to close.
- Three notification observers, and a fourth only while collapsed. Nothing runs between changes.
