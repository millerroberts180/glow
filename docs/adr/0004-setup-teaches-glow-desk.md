# ADR 0004: Setup teaches what Glow Desk does

- **Status:** Accepted, 2026-11-19
- **Supersedes in part:** ADR 0001, "Setup"; `QA_REPORT.md`, "Keys, popover, setup and reading, 2026-11-09", Setup

## Context

Setup had four steps:

1. **Welcome:** an 88 pt mark and Get Started.
2. **Your displays:** setup's own slider for each display, with a line on how Glow sets it.
3. **Match their brightness**, or **Set your brightness** with one display.
4. **You're set:** "In the menu bar", the brightness keys with **Allow…**, and open at login.

Much of it told rather than showed. The sliders were setup's own, not Glow Desk's, so they ignored the Look setting (Boxes). With one display, steps 2 and 3 showed the same slider. Accessibility was asked for on the last page, where nothing used it. "In the menu bar" described Glow Desk without opening it.

I wanted setup cut to what teaches, looking and behaving like the app it teaches.

## Decisions

### 1. Each step teaches one thing

| Before | After | Why |
| --- | --- | --- |
| Welcome | Folded into Your displays: the mark at 32 pt and one line. | A page that only says hello teaches nothing. |
| Your displays | Glow Desk's own rows, and "Click ✦ in the menu bar to open Glow Desk.", ticked when it opens. | The real view, and where to find it. |
| Match their brightness | Kept, with **Not Now**. Shorter copy. No Try-it slider, move-together check button or keys line. | Matching is the one thing setup does that's worth doing first. The rest repeated Glow Desk. |
| Set your brightness (one display) | Removed. With fewer than two displays to match, or in safe mode, the step isn't listed. | One display has nothing to match, and its slider is already on the first step. |
| You're set: In the menu bar | Removed. | The first step now points at the mark and ticks when Glow Desk opens. |
| You're set: the brightness keys | Its own step: **Allow…** with one line on why, then a press of a real key, ticked when it changes a display. | The permission is asked for where the next thing needs it. |
| You're set: open at login | The last step, **Open at login**, with the line on where the tutorial is. | Unchanged, apart from the page around it. |

### 2. Your displays is Glow Desk's own view

- `DeskDisplays`, Glow Desk's list of rows, moved out of `MenuBarView` into `DisplayRow.swift`. Glow Desk and setup both use it, at Glow Desk's 308 pt width. The route labels, sliders or boxes, volume and the paused notice are the same code.
- In setup the rows have no **Display Settings…** context menu. Setup has no way into Settings, and the menu isn't what the step teaches.
- One caption explains the route labels on the rows, only when there are rows: "Native and Hardware control change a display's own brightness; Software dimming dims its picture."

### 3. Ticks come from the app's own events

- `GlowStore.glowDeskOpens` counts `MenuBarView.onAppear`, where Glow Desk already starts its settle animation each time it opens.
- `GlowStore.keyPressesMoved` counts the presses `handleBrightnessKey` takes that change a display. A press at the end of the range, or while writes are paused, is taken but ticks nothing.
- `SetupModel` notes both counts when setup opens, so only what happens after that counts. Neither is saved.
- No timers. VoiceOver hears "Done." and the task once when it ticks.

### 4. The keys step

- It asks for Accessibility only when access is off: "It uses it for those keys only, and never sees what you type." The tap listens to system-defined media-key events only. As before, the step notices the grant by checking once a second, on this step only.
- Once access is on, it says which displays the keys change, from Glow Desk's **Brightness keys** choice, and asks for a press.
- When Glow would leave the keys to macOS (demo displays, safe mode, Mac chosen in Glow Desk, or no displays yet), it says so rather than asking for a press that can't tick.

### 5. The tutorial

- Settings › General › **Open Tutorial…** runs the same steps with no permission and no open at login.
- Its keys step shows only once Glow can take the keys. Without access there's nothing for it to teach, and **Allow…** is in Glow Desk and Settings › Controls.

### 6. Choices that left setup

- **Move matched displays together:** setup's save still turns it on, as before, but setup no longer shows the check button to turn it off. It's in Settings › Brightness Match.
- Which displays the keys change was never chosen in setup. Glow Desk's **Brightness keys** and Settings › Controls have it.
- **Open at login** is still in setup, and in Settings › General.

## What I checked

- `scripts/test.sh`: 321 tests, 0 failures. `SetupTests.swift` has 38: 8 new, 4 rewritten, 2 deleted with the states they tested.
- `swift build`: no warnings.
- `--snapshot-ui`: 52 setup images, every step and state, light and dark. I opened each one. The Glow Desk and Settings images in `docs/images` came out byte-identical. Only `setup-light.png` and `setup-dark.png` changed.
- The snapshot path is still demo- and mock-only. Its setup desks use `MockDisplayAdapter`, and a key press is sent to the store directly, never through the tap.

## Deferred

- I haven't tried these on a real Mac:
  - `onAppear` running on each real open of Glow Desk;
  - the grant being noticed, and a real key ticking the step;
  - VoiceOver hearing the ticks;
  - Increase Contrast;
  - open at login being applied.
- With one display, Your displays has empty space below the row.
- The setup window is still 640 × 600.

## Consequences

- Setup draws no displays of its own. A change to Glow Desk's rows shows in setup too.
- `GlowStore` has two counters, in memory only.
- The `title1` and `cardTitle` type styles are gone, with the steps that used them.
