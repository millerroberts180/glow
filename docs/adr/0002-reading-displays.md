# ADR 0002: Reading displays, keeping readings fresh, and correcting what Glow found

- **Status:** Accepted, 2026-11-09
- **Builds on:** ADR 0001 (decisions 2, 4, 9, 12 and 14)
- **Evidence:** `docs/research/displaybuddy-vs-monitorcontrol.md` §5 (principle 6)

## Context

Glow reads each display once, at discovery, then shows that reading until the next discovery. A person who presses the monitor's own buttons, or a Mac whose brightness keys macOS handles, leaves Glow showing a value that isn't true anymore. Settings has no say in how often Glow looks, what it does at launch, or how long it waits for a slow monitor. And a setting a monitor reports but ignores (a sharpness that changes nothing) stays in the OSD forever.

## Decisions

### 1. Glow rereads, in two tiers, and only reads

- **Frequent:** brightness, volume and mute, the settings people change on the monitor itself.
- **Rare:** every other readable OSD setting.
- **Reads never cause writes.** A reread updates what Glow shows and nothing else. It never moves a matched display, never reapplies anything, and never counts as "set by Glow".
- What gets reread: OSD settings that read successfully at discovery (`safelyProbed`, `answeredUnlisted`) over hardware or native routes. Software dimming is Glow's own state, so it isn't reread. Text facts (resolution, refresh rate) come back with rediscovery.

| Keep readings fresh | Frequent tier | Rare tier |
| --- | --- | --- |
| Off | never | never |
| While Glow is open (default) | every 5 s while the popover or Settings shows | every 60 s while open |
| Always | every 5 s while open, every 45 s otherwise | every 60 s while open, every 10 min otherwise |

Read Again, Read All and the launch read ignore the choice; they're asked for.

### 2. A reread gives way to everything else

- It waits while writes are paused (`pauseReason`: sleep, wake, display change) and while discovery runs.
- It skips any setting with a `pendingValue`, and any display the adapter is writing to or wrote to in the last 2 s.
- After each read it checks again: a value read while someone changed the setting is dropped, never applied.
- One pass per display at a time, one read at a time. On hardware every exchange also runs on the display's serial bus queue (`DDCBus`), so a read and a write never interleave on the wire.
- Changes reach `displays` through one funnel in `GlowStore` that merges one setting at a time and leaves a setting with a change in flight exactly as it was.

### 3. A display that doesn't answer is left alone

- A display with no hardware-route setting is never read over DDC/CI. The AOC on the dock answers nothing, and its brightness is software dimming, so Glow sends it nothing.
- A pass in which every DDC read times out backs that display off: 30 s, then doubling to 15 min. One answer resets it. Read Again ignores the back-off once, because someone asked.

### 4. "Changed on the display"

- When a reread finds a value that differs from what Glow showed, Glow updates it everywhere (OSD, popover, scenes' "current" check) and marks the setting for 60 s. The mark reads "Changed on the display", or "Changed outside Glow" for a built-in display, whose brightness macOS can change.
- The mark lives on the descriptor (`changedOnDisplayAt`), so any surface can show it.

### 5. At launch: read, or put back what Glow last set

- **Read each display** (default) is what Glow always did.
- **Put back what Glow last set** writes, after the first discovery, the values Glow last set and saw confirmed on each real display.
  - Those values are kept across launches in their own versioned store (`LastSetValues`), recorded whenever `setByGlow` changes.
  - It uses Reapply after wake's allowed set and rules exactly: a descriptor must exist, must not ask first, and must differ from the reading. Then the scene write path (plan, confirmed writes). Input and power are never written, on top of that.
  - Never in safe mode, never for demo displays, never while writes are paused.

### 6. Patience is a transport profile adjustment

- **Normal** uses the profile discovery found.
- **Patient** keeps that profile's address and send count, and raises its waits and retries to at least Slower timing's: 120 ms for a reply, 100 ms after a change, 7 tries over up to 3 s.
- It applies to every read and write from then on, by reopening each connection's link with the adjusted profile. Discovery still climbs the ladder (ADR 0001, decision 11).

### 7. Everything the display reports, read once and never written

- Reported codes that aren't in the catalog and aren't housekeeping are read once with Get VCP, after the catalog settings and within discovery's 20 s budget, and again on Read Again.
- MCCS's write-only commands (0x01, 0x04–0x0A, 0xB0) are never read.
- Connection lists them under "Reported, not in Glow’s catalog" with the raw current and maximum. They keep `access: .unavailable` and `reportedUninterpreted`, and the catalog has no encoding for them, so no path can write them.

### 8. Hide: a correction the person makes

- Any OSD setting a real display reports over DDC/CI can be hidden on that display. It's stored per display identity in its own versioned store (`DisplayCorrections`).
- A hidden setting gets the presentation `hiddenByYou`. That takes it out of the OSD, the popover and scenes (none of them shows a setting that isn't `.osd`), but Connection still lists it, labelled "Hidden by you", so hidden never looks like unsupported.
- Displays lists what's hidden on each display, each with Show.
- Demo displays can't hide anything.

### 9. Settings › Reading

A new pane holds Keep readings fresh, At launch, Patience, Read All, and the Wake section moved from General.

## Consequences

- Rereads cost bus time: about 3 reads every 5 s per DDC display while Glow is open. Off is one click away.
- A monitor whose OSD menu blocks DDC/CI while it's open will time out for a while, and back-off covers it.
- Hidden settings can't be applied by an old scene; the scene reports them as skipped.
- Reapply after wake and launch restore share rules but not code: `GlowStore+Scenes.swift` isn't this change's to edit. They should become one helper.
