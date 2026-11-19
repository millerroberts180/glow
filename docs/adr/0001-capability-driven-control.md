# ADR 0001: Capability-driven monitor control and the suite settings language

- **Status:** Accepted, 2026-11-07
- **Evidence:** `docs/research/displaybuddy-vs-monitorcontrol.md`
- **Specs:** Glow's product spec and brand guidelines, internal documents not kept in this repository

## Context

Glow's promise is a Digital OSD built from what each monitor actually supports, and honest about what it can do.

- **MonitorControl.** It controls three fixed settings. When a read fails it uses an assumed value, and it never confirms writes. The user marks which controls are unavailable.
- **DisplayBuddy.** Its controls vary "depending on your display", but nothing public says how it decides.
- **Glow today.** Glow already has evidence-carrying `CapabilityDescriptor`s, a renderer that maps each one to a control, and a write pipeline that confirms each write by reading it back. Three things are missing:
  - A path from the monitor's own capability list to those descriptors.
  - A pause in writing during sleep or while displays are reconfiguring.
  - A settings window in the suite's style.

## Decisions

### 1. Capabilities come from a catalog, never from hand-written screens

- **Parsing.** `MCCSCapabilityString` parses the monitor's capability list (VCP 0xF3, MCCS 2.2 `vcp(...)` syntax), including the values each control allows.
- **Translation.** `CapabilityCatalog` turns each code it knows into a `CapabilityDescriptor` with:
  - a plain-language label,
  - a section and an order,
  - a control kind and range,
  - its risk level,
  - option names for code lists (for example, input values 0x0F → "DisplayPort 1", 0x11 → "HDMI 1").
- **Rendering.** The OSD shows descriptors grouped by `CapabilitySection` and drawn by `CapabilityRenderer`. A newly catalogued code (sharpness, black stabiliser, a vendor's KVM switch) needs one catalog entry and **no UI code**.
- **Unknown codes.** Codes the catalog doesn't know are kept as `reportedOnly` / `unavailable` entries and shown **only in Connection details**, labelled "Reported, not interpreted". Glow never writes a code whose meaning it doesn't know.

### 2. What each piece of evidence allows

| Evidence | Where it comes from | Editable? |
| --- | --- | --- |
| `reportedOnly` | Listed in the capability string, not yet read | No; shown read-only as "Reported, not tested" |
| `safelyProbed` | A harmless read (Get VCP Feature) succeeded | Yes, if access and route allow it |
| `contradictory` | Listed, but the read or write failed or the read-back didn't match | No; shown as "Reported, but test failed" |
| `inferred` | Worked out from the connection type, not reported by the monitor | Read-only context |
| `unavailable` | Not reported, and the connection can't carry it | Shown only in Connection details |

- A value Glow could not read shows "No reading yet". Glow never shows an assumed value and never writes one back to the monitor (the opposite of MonitorControl's behaviour).

### 3. Transport adapters sit behind `DisplayAdapter`

- **The adapters:** Apple native (DisplayServices), DDC on Apple Silicon (IOAVService I2C at 0x37/0x51), DDC on Intel (IOFramebuffer I2C), and software (gamma table or shade overlay).
- **What this build ships.**
  - The demo adapter.
  - Discovery through public CoreGraphics, which never claims it can write.
  - The catalog and parser, ready for a DDC transport.
- **What it doesn't ship.** The private-API DDC transport. It needs testing against real monitors, which wasn't possible here, so hardware writes stay disabled and say so.

### 4. Writes go through one pipeline that can pause

`DisplayWritePipeline` keeps four protections:
- it validates every value;
- it allows only one write at a time per display;
- it retries only after a timeout or a read-back mismatch, at most twice;
- it rejects a write if the display layout has changed.

It adds `suspend(reason:)` / `resume()`. `GlowStore` calls them on screen sleep and wake, on system sleep and wake, and on display reconfiguration, waiting about a second for things to settle (copied from MonitorControl's `sleepID`/`reconfigureID` guard). While paused, a write fails with `.suspended`, which the user sees as "Glow paused changes while your displays reconnect." Nothing is queued, so nothing is replayed onto a display that has changed.

*Amended 2026-11-09, for held brightness keys:* the latest value wins, with one write in flight per display and setting (`WriteCoalescer` in `GlowStore`). While a write is in flight only the newest proposal waits, and values it overtakes are never sent. A value with a newer one behind it may skip its read-back, but it is still validated, refused while paused or on a changed layout, and kept in order per display by the pipeline. The last value of each run always gets the read-back and its retries. Only then is it marked confirmed and recorded in `setByGlow`. A refused write ends its run and drops whatever was waiting, so a pause still replays nothing. `confirmWrite` drops anything waiting before it reads back.

### 5. Disruptive controls ask first

Input and power changes can blank the display the user is looking at. Any capability whose `risk` is not `.none` gets `requiresConfirmation == true`, and the UI must confirm before writing it. Scenes may include disruptive settings only when the user adds them; destructive ones (power off) are never applied automatically.

### 6. Visual language: the suite's settings style, with Glow's tokens

Glow matches the other Line Apps (Pulse, Hum and Tuck), which share one settings-window structure:
- a sidebar of tinted pane tiles,
- a 46 pt pane header,
- grouped forms in which every control explains itself,
- `VisualChoice` tiles,
- `ActionButtonStyle`,
- versioned `Codable` settings,
- `SMAppService` for open at login,
- a snapshot harness.

Glow adopts this structure. Glow's brand guidelines still supply colour, status and wording, through the token file `GlowTokens` in `Theme.swift`.

**Size.** The brand guidelines ask for an 880–1,100 pt window with a 220 pt sidebar. The suite uses 620×540 with a 150 pt sidebar.
- **Decision:** a fixed **760 × 600 pt** window with a **168 pt** sidebar.
- **Why:** the Displays pane holds the whole Digital OSD (a label, a detail line, a control and a value per row), and Connection details holds a table. These need more width than Pulse's panes. 880 pt or more would look empty, which the suite explicitly avoids.
- It may move by up to ±40 pt if the snapshots show a reason.

**Sidebar.** The brand doc names six destinations; they keep the doc's names but are grouped the suite's way:
- **General** alone at the top.
- **Desk:** Displays, Brightness Match, Scenes.
- **Keyboard:** Controls.
- **Support:** Connection details.

**Menu bar.** The product spec makes the menu-bar popover (Glow Desk) the main everyday surface, so Glow keeps a popover rather than the suite's lean `NSMenu`. The suite's lean-menu rule still applies to *configuration*: the popover holds controls and status, and everything configurable lives in Settings.

**Setup.** First-run setup follows the same apps' step flow. It is built after Settings and reuses Settings' components. Re-run from General ("Open Tutorial…"), it shows only the teaching steps.

**Superseded in part, 2026-11-19,** by [ADR 0004](0004-setup-teaches-glow-desk.md). Setup keeps the step flow, but it has no brand welcome, and its displays step is Glow Desk's own view rather than Settings' components.

## Consequences

- New monitor features are added as catalog entries and tests, not as new screens.
- The OSD's honesty depends on adapters reporting evidence correctly. Adapter tests must cover every evidence transition.
- Glow's settings window is wider than the other suite apps'. That is deliberate and confined to Glow.
- Hardware DDC needs a separate, flagged pass on real hardware before Glow can claim "Hardware control" outside demo mode.

## Addendum, 2026-11-07: shaping the DDC transport

Four more decisions. None changes the shipped behaviour above; each shapes the DDC transport when it is built.

7. **Transport quirks are a per-connection profile.**
   - `DDCTransport` will take a `DDCTransportProfile` value. Its defaults match the standard: source byte `0x51`, one send, no SCS, checksum enforced.
   - Optional fields: alternate source `0x50`, write repeats, write and read waits, retries, ignoring read checksums, and SCS after a write.
   - Any non-default value appears in Connection details as evidence. It is never inferred from a brand name.
8. **Alternate addressing is recorded per setting.** If a setting (for example, input on some LG models) only answers from the alternate source, its evidence says "Answered on alternate address". Its existing confirmation rule still applies.
9. **The baseline is what Glow read.**
   - Discovery stays read-only, and Glow stores the values it read as the display's baseline.
   - A future "Restore" returns to that baseline. Glow never moves the picture because a feature was detected.
   - Reapplying on wake is opt-in and waits until the pipeline resumes. Holding Shift at launch starts Glow without restoring any values.
10. **User-defined settings, when added, are catalog entries with their own evidence.**
    - Each is labelled "Added by you" and becomes editable only after a successful read.
    - Each always asks for confirmation and is never applied by a scene.
    - The OSD never offers a free-form raw write.
    - CEC over DisplayPort AUX, TV network protocols, DisplayLink relay and EDID overrides stay out of scope until there is a reason and hardware to test on.

## Addendum, 2026-11-08: adaptive profiles, and displays that send no report

The first real external monitor, an AOC 32G2WG3 behind an Anker USB-C hub, never answered DDC/CI. Every read blocked for about 6 s, and then IOAVService gave up (`0xE0114103`). That held on every timing and address tried. An EDID read over the same I2C path answered in 1.5 ms (`QA_REPORT.md`, hardware section). Five decisions follow. Decisions 11–13 build decisions 7 and 8; 14 and 15 extend the evidence table.

11. **Discovery climbs a ladder of profiles.**
    - The ladder is `DDCTransportProfile.ladder`: **Standard**, then **Slower timing**, then **Alternate address** (source `0x50`).
      - Slower timing sends twice, waits 20 ms before sending and 200 ms for a reply, and tries seven times within 3 s.
    - The first profile asks for the capability report.
      - With no report, it sends one Get VCP of brightness (`0x10`).
      - Each later profile starts with that Get VCP, and asks for the report only after a reply. A silent connection costs one wait per profile, not two.
    - Retries stop once a single exchange has run past the profile's retry window (1 s on Standard). A bus that blocks for seconds before it refuses a read won't answer a retry.
    - The first profile that gets any reply, even "unsupported", becomes the connection's working profile.
      - Connection details and Copy Report show every try, with its timing and reason, and how the working profile differs from Standard.
      - Glow never picks a profile from a brand name.
12. **Each connection keeps its profile while Glow runs.**
    - The key is vendor, product, serial and route: the framebuffer path, or the service ID when there's no path. The same monitor on another port or hub starts at the top of the ladder.
    - After wake or a display change, the working profile is tried first.
    - A connection that no profile reached gets a single quick standard Get VCP, so wake isn't held up for 24 s. Refresh Displays tries every profile again.
    - Nothing is saved across launches.
13. **The alternate address belongs to the connection, not to each setting.** This changes decision 8.
    - The address is part of the working profile, so every setting on that connection uses it.
    - Retrying one silent setting on the other address isn't built.
14. **"Answered, not listed by the display"** (`answeredUnlisted`).
    - When no usable report arrives but the display answers, Glow reads each catalogued OSD setting once. It never reads an action.
    - A read that comes back with a value Glow can name gets this evidence.
    - Such a setting is editable only if it has no risk, isn't read-only, and is a slider or a switch: brightness, contrast, volume, mute, sharpness, the RGB gains and the black levels.
    - Input, power, colour preset and picture mode stay read-only until a report lists them. With no report, the display never said which values it takes, and input and power can blank the screen. Once a report lists one, decision 5's confirmation applies.
    - A setting that is silent or refused, or that answers with a value Glow can't name, stays out of the OSD; its raw reading is still in Connection details. Nobody reported it, so "Reported, but test failed" would be untrue.
    - Every write is still confirmed by reading it back (decision 4).

    | Evidence | Where it comes from | Editable? |
    | --- | --- | --- |
    | `answeredUnlisted` | No capability report; a Get VCP returned a value Glow can name | Low-risk sliders and switches only; everything else read-only |

15. **Some catalog entries are read-only.** Glow shows gamma (`0x72`), menu language (`0xCC`) and hours used (`0xC0`), and never writes them.
    - Hours used is a counter.
    - Changing the menu language from Glow could leave someone with an OSD they can't read.
    - Gamma is read-only by choice. Glow decodes only MCCS's common absolute form, (value + 100) / 100, so a write could land on a different curve than the label says.
    - `CapabilityCatalog.encode` returns nil for all three.

## Addendum, 2026-11-09: displays that are already connected at launch

At launch the AOC behind the Anker hub held up every display. Discovery returned all of them at once, so for about 25 s Glow showed nothing, not even the built-in display. Then the AOC came back on software dimming, after four waits of about 6 s each. Two decisions follow. Decision 17 changes decision 11's ladder.

16. **Discovery shows each display as soon as it can.**
    - Every display appears at once. An external display that's still being probed shows as "Checking connection…" with no settings, and no software brightness yet, so nothing is set before Glow knows how to set it.
    - Each external display then takes its place as its own probe finishes. A slow or silent monitor holds up no other display.
    - On Refresh Displays, a monitor that's already shown keeps what it showed until its new probe finishes, so the rows don't blank.
    - The topology generation still moves when discovery starts. A display shown by the new discovery takes writes at once. A monitor kept from before on Refresh Displays has the old generation, so a write to it is refused as stale until its new probe finishes, as during any refresh before.
17. **A connection that stalls, then refuses, ends the ladder.**
    - A capability request or Get VCP that blocks for 3 s or more (`DDCProbe.stallLimit`) and then fails to send or read stops discovery on that connection. No timing or address changes that, so the other profiles aren't tried.
    - A refusal that comes at once still climbs the ladder.
    - The note says why: "Glow stopped there: the connection waited 6.1 s, then refused the request…". Refresh Displays tries again, from the top.
