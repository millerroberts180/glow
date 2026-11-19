# DisplayBuddy vs MonitorControl: how each discovers and controls monitors

Research for Glow's capability-driven Digital OSD. Written 2026-11-07.

## Evidence key

- **[Source]**: read in MonitorControl's open-source repository. Citations are `file:line` at commit `7cfe645` (2026-10-14), cloned from https://github.com/MonitorControl/MonitorControl.
- **[Docs]**: quoted from a public page, with its URL.
- **[Inference]**: my reading of the evidence. It was not confirmed by running the software.
- **[Unknown]**: no evidence was available.

## Method and limitations

- **MonitorControl.** Its source code is open, so I read the repository directly.
  - The repository has **no test target**, so there are no tests to check behaviour against.
  - Nothing was run against real monitors.
- **DisplayBuddy.** It is closed-source and paid, so only its public pages were used.
  - The public download (`/public/DisplayBuddy_3.8.0.dmg`, linked from /troubleshooting) was **not** downloaded or installed.
  - So everything said about DisplayBuddy below comes from 13 public pages (all returned HTTP 200 on 2026-11-07) and is limited to what they say.
  - The public pages never say whether DisplayBuddy reads the monitor's capability list.
- No physical monitor was attached during this work, so neither app's runtime behaviour was observed.

## 1. Discovery

| Topic | MonitorControl | DisplayBuddy |
| --- | --- | --- |
| Finding displays | **[Source]** `CGGetOnlineDisplayList`, capped at 16 displays (`Support/DisplayManager.swift:163-190`). Each is classified as an `AppleDisplay` or an `OtherDisplay`. | **[Docs]** "The main DisplayBuddy window lists all your connected monitors." (/docs/getting-started) |
| Apple displays | **[Source]** A display counts as Apple if `DisplayServicesGetBrightness` succeeds or it is built in, with a macOS 15 HDR special case (`DisplayManager.swift:508-520`). | **[Docs]** "Apple Display Protocol", "Used for Apple's own displays — like the Pro Display XDR, Apple Studio Display, and your MacBook's built-in screen." (/docs/getting-started) |
| Virtual or dummy displays | **[Source]** `isVirtual` checks `kCGDisplayIsVirtualDevice` and AirPlay; `isDummy` is a name heuristic (`DisplayManager.swift:433-455`). | **[Docs]** Software Control "also lets you control Sidecar and AirPlay displays." (/docs/getting-started) |
| Linking a display to its DDC service on Apple Silicon (DDC/CI is the standard monitor control protocol) | **[Source]** Each display is scored against candidate IORegistry services by EDID UUID, `IODisplayLocation`, product name and serial number, then assigned greedily so no service is used twice (`Support/Arm64DDC.swift:42-70, 128-164`). One model is hard-coded as a dummy, AOC 28E850 (`Arm64DDC.swift:266`). `checkIfDiscouraged` always returns `false` (`:272`). | **[Unknown]** |
| Identical monitors | **[Source]** Duplicate names get a number suffix (`DisplayManager.swift:318-`); the IORegistry match uses serial and location to tell them apart. | **[Unknown]** |
| Choosing a control method | **[Source]** Automatic: Apple display, then DDC, then software. The user can force software per display (`forceSw`). | **[Docs]** "DisplayBuddy automatically detects the best one for your monitor", and the user can change it under "clicking on your display name > Controlled using" (/troubleshooting). |
| Known blind spots | **[Docs]** No DDC over the built-in HDMI port of the 2018 Intel Mac mini, any M1 Mac, or the entry-level M2 Mac mini. EIZO uses MCCS (the monitor command set) over USB. DisplayLink is software-only (MonitorControl `README.md:94-96`). | **[Docs]** On M1 HDMI, "DDC will not work." The same page also says "the HDMI port of M2 Macs also work fine," which conflicts with other statements about M2 (/troubleshooting). |

## 2. Reading what a monitor supports

This matters most for Glow, because Glow's Digital OSD must be built from what each monitor can actually do.

- **MonitorControl does not read the monitor's capability list.** It never asks for VCP 0xF3, the code a monitor uses to report its own controls.
  - **[Source]** "capabilit" appears nowhere in its Swift code. `Enums/Command.swift` is a full list of MCCS codes, but it is only used to address commands.
  - **[Source]** It sets up just three controls per external display: volume, contrast and brightness (`DisplayManager.swift:192-202`). Mute, using code 0x8D, comes along with volume (`Model/OtherDisplay.swift:146-161`).
  - **[Source]** Reading the monitor is optional. It happens only when the startup action is "read" and polling is on (`OtherDisplay.swift:91-143`). The polling setting is a retry count: none 0, minimal 1, normal 5, heavy 20, or custom (`OtherDisplay.swift:15-27`).
  - **[Source]** If a read fails, MonitorControl **assumes** a value (volume 12.5 %, contrast 75 %, brightness 100 %), or uses the last saved one. It then writes that value back to the monitor (`restoreDDCSettingsToDisplay`, `OtherDisplay.swift:93-101, 120-135`). So a value it displays may never have come from the monitor.
  - **[Source]** Which controls are unavailable is **set by the user**, not detected. Display settings have a checkbox per control (`unavailableDDC`, where checked means available), plus overrides for polling mode, longer delay, min/max values, curve, invert and code remapping (`View Controllers/Preferences/DisplaysPrefsCellView.swift`; `OtherDisplay.swift:368-378, 482-497`).
- **DisplayBuddy:**
  - **[Docs]** "Simple View: quick access to brightness, contrast, and volume." "Expanded View: additional controls like input source, power, rotation, and resolution (depending on your display)." (/docs/getting-started)
  - **[Inference]** "Depending on your display" suggests it varies controls per monitor, but no page says how. It might read the capability list, test each control, or use a built-in model list.
  - **[Unknown]** Whether it reads VCP 0xF3, how it shows a control a monitor doesn't support, and whether it keeps any record of why a control is or isn't shown.
  - **[Docs]** The CLI takes input as a name or a raw DDC code: "Input source (e.g., hdmi1, displayport1, or a DDC code like 17)" (/docs/command-line-ai). So it has some mapping from input names to VCP 0x60 values.

**What this means for Glow.**
- Neither product shows clear evidence of a capability scan that tells the user what it found.
- MonitorControl's own source shows the cost of not having one: a small fixed set of controls, guessed values presented as current, and the user left to tick checkboxes for what works.
- So Glow's plan is a real advantage, as long as it stays honest about evidence:
  - Read the capability list where the monitor provides it.
  - Mark each listed control "Reported, not tested" until a harmless read confirms it.
  - Never present an assumed value as a value read from the monitor.

## 3. Changing a setting

| Step | MonitorControl | DisplayBuddy |
| --- | --- | --- |
| Apple Silicon link | **[Source]** The private `IOAVServiceWriteI2C`/`ReadI2C` calls at I2C address 0x37 with data address 0x51 (`Support/Arm64DDC.swift:6-7`), declared in `Bridging-Header.h`. | **[Docs]** "DisplayBuddy talks directly to your monitor over DDC." (/features) |
| Intel link | **[Source]** IOFramebuffer I2C (`IOI2CSendRequest`). A reply is checked by checksum, reply type `0x02` and result code; a non-zero result means "unsupported" and returns `nil` (`Support/IntelDDC.swift:63-121`). | **[Unknown]** |
| Timing and retries | **[Source]** Defaults: up to 5 attempts (4 retries), 2 write cycles each, 10 ms wait after a write, 50 ms before a read, 20 ms between retries (`Arm64DDC.swift:92-117`). "Longer delay" adds a 40 ms minimum before a reply (`OtherDisplay.swift:106`). | **[Unknown]** |
| Confirming a write | **[Source]** None. The write's result is thrown away (`_ = Arm64DDC.write(...)`, `OtherDisplay.swift:413`), and the value is never read back. | **[Unknown]** |
| Rapid changes | **[Source]** While the user drags, only the newest value is sent (`writeDDCNextValue`/`writeDDCLastSavedValue`, `OtherDisplay.swift:380-419`). | **[Unknown]** |
| Sleep and display changes | **[Source]** Writes are blocked while `sleepID != 0` or `reconfigureID != 0` (`OtherDisplay.swift:381`). After a display change it waits 1 s, then resets gamma and shades (`AppDelegate.swift:137-158`). After waking it sets displays up again 3 s later (`AppDelegate.swift:193-215`). | **[Unknown]** |
| Software fallback | **[Source]** A gamma table (`CGSetDisplayTransferByTable`), or a "shade" overlay window for virtual displays (`DisplayManager.swift:44-161`). In combined mode, hardware brightness handles the upper range and gamma the lower (`OtherDisplay.swift:334-362, 512-514`). | **[Docs]** "When a monitor refuses DDC, DisplayBuddy dims through gamma control automatically." (/features) "It doesn't affect the real hardware." (/docs/getting-started) |
| Value mapping | **[Source]** Per-control min/max overrides, a curve multiplier and inversion. Volume never maps to hardware 0; mute uses 0x8D, value 1 for mute and 2 for unmute (`OtherDisplay.swift:146-255, 482-497`). | **[Unknown]** |
| Other ways in | Media keys and custom shortcuts. | **[Docs]** Wi-Fi control for LG webOS and Samsung Tizen "displays that ignore DDC" (/features). Also presets, schedules, Shortcuts, AppleScript, Spotlight, a CLI and MCP: "everything you can do in the UI, you can do from a script." (/docs/command-line-ai) |
| Startup safety | **[Source]** A safe mode, and settings are wiped when the stored build number is out of range (`AppDelegate.swift:114-127`). | **[Unknown]** |

## 4. Explaining capabilities and failures to the user

- **MonitorControl:**
  - **[Source]** Each display is labelled with its method in Display settings: "Hardware (DDC)", "Software (gamma)", "Software (shade)", "Hardware (Apple)" or "No Control ⚠️", with an explanatory tooltip (`View Controllers/Preferences/DisplaysPrefsViewController.swift:75-136`).
  - **[Source]** That label applies to the whole display, not to each control. Uses technical terms (DDC, gamma).
  - **[Source]** First-run onboarding covers only permissions and launch at login (`View Controllers/Onboarding/OnboardingViewController.swift`).
- **DisplayBuddy:**
  - **[Docs]** Troubleshooting asks the user to: "switch this mode to Custom", turn on the monitor's "dedicated DDC / CI setting", try another cable or hub, and "try out different modes to see what works for your display" (/troubleshooting).
  - **[Docs]** It names what affects compatibility: "Your Mac model, the GPU, the connection (adaptors, hubs cause issues), and your display itself and how well it implements the DDC spec." (/troubleshooting)
  - **[Docs]** It offers a compatibility estimate "from opted-in DisplayBuddy users" (/will-it-work-with-my-monitor). The page itself showed no results.
  - **[Unknown]** How the app itself shows an unsupported or failed control.

## 5. Principles Glow takes from this

Each principle follows from the evidence above. Applying them is decided in `docs/adr/0001-capability-driven-control.md`.

1. **Base the OSD on capabilities, recorded per connection, with the evidence for each.** MonitorControl uses three fixed controls and leaves the rest to user checkboxes. Glow reads the capability list (VCP 0xF3) when the monitor provides it, and records for every control whether it was reported, tested, contradicted or inferred.
2. **Don't present a guessed value as a reading.** MonitorControl assumes values when a read fails. Glow shows "No reading yet" instead, and never writes a guessed value back to the monitor at startup.
3. **Confirm writes.** MonitorControl discards the write result. Glow keeps its read-back confirmation and its limited retries (only after a timeout or a read-back mismatch). It marks a control "Reported, but test failed" when the monitor contradicts its own capability list.
4. **Pause writes during sleep and display changes.** Copied from MonitorControl's `sleepID`/`reconfigureID` guard. In Glow this lives inside the write pipeline, alongside its existing check for a changed display layout.
5. **Explain the control method in plain words, per control.** Both apps label the method, but only per display. Glow labels each control: "Hardware control", "Native control", "Software dimming", "Not available on this connection". Technical codes appear only in Connection details.
6. **Let people correct what Glow found, per connection.** MonitorControl's per-control overrides prove they're needed. Glow records them as user-set evidence, separate from what it discovered, so "hidden by you" never looks like "unsupported".
7. **Make disruptive controls ask first.** Changing input or power can blank the screen the user is looking at. Neither source says how its app protects against this. Glow asks for confirmation before any control marked disruptive or destructive.
8. **Fall back to software only with a clear label.** DisplayBuddy and MonitorControl both dim through gamma or shades automatically. Glow does the same, always labelled "Software dimming", and never counts it as hardware support.
