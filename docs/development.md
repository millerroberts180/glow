# Development

Glow is a Swift package with one executable target, `GlowApp`, and its tests. It needs macOS 14 or
later and Swift 6.1 or later. The Command Line Tools are enough; Xcode is optional. Paths to Swift
files below are under `Sources/GlowApp/`.

Glow reads what each connected display can do and builds its Display settings from it: one control per
setting the display reports, each labelled with how it is controlled and how far Glow has tested it. It
controls this Mac's real displays: external monitors over DDC/CI, the built-in display through macOS,
and anything else by dimming the picture. Three demo displays are a choice in Settings, so every screen
can be tried without a monitor attached.

## Run

```sh
swift run Glow                         # this Mac's displays
GLOW_REAL_DISPLAYS=1 swift run Glow    # real displays for one launch, even if demo displays are on
swift run Glow -GlowSimulatedMonitors all   # four simulated DDC/CI monitors instead (debug builds)
scripts/bundle.sh && open build/Glow.app
```

- **The menu bar.** Click Glow's mark, a four-point spark, in the menu bar to open Glow Desk. Your scenes show there as their symbols, and **More controls…** opens Settings › Displays. Right-click or Control-click the mark for **Refresh Displays**, **Settings…** (⌘,) and **Quit Glow**.
- **Boxes or sliders.** Brightness and volume in Glow Desk can be sliders or a row of sixteen boxes, like macOS's own brightness overlay (Settings › Controls › **Look**). Click a box to light it and the ones before it, click the top lit box to step down one, or drag to set any level between. With keyboard navigation on, the arrow keys move one box.
- **Settings › Glow** shows which version this is, or "Development build" under `swift run`, with links to the website, support, the privacy policy and the license agreement. **Quit Glow** is at the end of Settings › General.
- **No trial or license key.** Glow had both until 2026-11-16. At each launch it deletes what they left: `TrialRecord` and `LicenseKey` in its preferences, and the "Glow trial" login Keychain item (service: the bundle ID, account `trial`), which the Keychain only lets the build that made it delete (`LeftoverTrialData.swift`).
- **Demo displays.** Settings › General › **Use demo displays**. Nothing is sent to real hardware while it's on.
- **Safe mode.** Hold Shift while Glow opens. It reads your displays and changes nothing, and leaves the brightness keys to macOS, until you quit and reopen it.
- **First-run setup.** Setup opens by itself the first time Glow launches and walks through your own displays: a slider for each, then matching their brightness. Pick the display that looks right, and a grey patch fills each screen while you set the others to look the same. Save, and they stay alike as you change brightness from the menu bar or the keys. With one display, setup shows its slider instead. **Not Now** skips matching; Settings › Brightness Match does it later. The last step has **Allow…** for the brightness keys and **Open Glow at login**. Settings › General › **Open Tutorial…** runs the displays and matching again.
- **Simulated monitors.** A debug build launched with `-GlowSimulatedMonitors all`, or a comma-separated list of `dell-u3011`, `aoc-c24g2`, `lg-27md5kl` and `lg-29um69g`, replaces this Mac's displays with simulated DDC/CI monitors (`Hardware/SimulatedMonitor.swift`). Each is firmware that speaks real DDC/CI bytes: it checks framing and checksums, sends real replies, and answers with a real capability report, copied from ddcutil's published examples. Each model has quirks to exercise a different path: a read-back that lags the write, a slow monitor that ignores requests for a moment after a change, one that answers only at the alternate address, and one with no capability report and an occasional bad checksum. `SimulatedDisplayAdapter` runs Glow's real discovery, profile ladder, write pipeline and read-back over them, and never touches IOKit, DisplayServices or gamma. A name Glow doesn't know prints a line to stderr and shows no displays, never the real ones. The quirks were chosen, not measured on hardware, and simulated runs use the real preferences, so the simulated monitors can be remembered in Settings.
- **The app bundle.** `scripts/bundle.sh` builds a universal release `build/Glow.app` (`GLOW_ARCHS=arm64` for one architecture, `GLOW_CONFIGURATION=debug` for a debug build with the debug-only flags; `scripts/release.sh` always builds release). It signs with `GLOW_SIGN_IDENTITY` if set, then with "Glow Local Signing" if `scripts/signing-identity.sh` has made that identity, and otherwise ad hoc. macOS ties the Accessibility grant to the signature, so with an ad-hoc signature each rebuild needs the permission granted again. Open at login and the brightness keys are meant to be used from the bundle. `scripts/make-icon.sh` rebuilds `Resources/AppIcon.icns` from the PNGs in `design/logo/png`.
- **Debug flags** (debug builds only; all but `--setup-ui` print and exit):
  - `swift run Glow --setup-ui` opens setup at launch even after it has been completed.
  - `swift run Glow --snapshot-ui <folder>` draws every Settings pane, the popover on several desks, the menu-bar mark, the confirmation alert and every setup step to PNGs off screen, in light and dark, then exits. Setup steps go to `<folder>/setup/`, the Brightness Match pane and calibration steps to `<folder>/match/`, the popover's box and button shots (with Settings › General down to Quit Glow) to `<folder>/popover/`, the overlay and Settings › Controls to `<folder>/keys/`, and Settings › Reading, Read Again, Hide and Connection's uncatalogued codes to `<folder>/reading/`. It uses a throwaway defaults suite and deletes it afterwards. The README's and guide's screenshots in `docs/images/` come from it: `swift scripts/readme-images.swift <folder>` copies them, crops a few, and draws the README's hero.
  - `swift run Glow --probe-displays` reads every display the way discovery does and prints what it found: the matched DDC service, the capability string, each Get VCP reply and the evidence for every setting. It changes nothing.
  - `swift run Glow --ddc-selftest` changes each display's brightness by 5, confirms it by reading back, restores it and confirms that too, then dims each picture to 80 % and restores it. Only brightness is written.
  - `swift run Glow --probe-readings` rereads every display the way Settings › Reading does, read only and in safe mode, and prints what each display rereads in each tier and how long a pass, a Read Again and a Read Again with Patient take.
  - `swift run Glow --brightness-pulse <level> [standard|slow|alternate]` is for a monitor that never answers a read. Read its brightness from its own menu and watch it: Glow dims it by 10 from there twice, 3 s each time, then sets it back. Only brightness is sent, and only when exactly one external display is connected and it didn't answer.
  - `swift run Glow --simulated-selftest [-GlowSimulatedMonitors <ids>]` runs discovery against the simulated monitors, then moves each one's brightness by 5 and back through the write pipeline. It prints the bytes each monitor accepted, and fails if discovery sent any Set VCP, a monitor rejected a request, anything but brightness was written, or the restore isn't exact. No real display is read or changed.
  - `swift run Glow --hold-selftest` holds a brightness key against the demo displays behind an adapter that takes 120 ms per write and per read-back: a tap, a 2 s hold, then a tap back. It prints the store's value at each tick, every write sent, the confirmed result and the largest gap between ticks, and exits non-zero on a failure. No real display is touched.
  - `swift run Glow --scene-selftest` runs scenes, **Restore Starting Values** and **Reapply settings after wake** on the real displays, through the store and the write pipeline, with a throwaway defaults suite. It uses only brightness and contrast on a hardware or native route, moves each by 5, reads every value back, and puts the built-in display's exact level back at the end. Software dimming is left alone. It exits non-zero if a check fails.

## Test

```sh
swift build
./scripts/test.sh
```

`scripts/test.sh` runs `swift test`. On a Command Line Tools-only Mac it adds the framework paths that Swift Testing needs there. With Xcode selected it runs plain `swift test`. Both take `--scratch-path <dir>` to build somewhere other than `.build`, for example while a copy of Glow from `.build` is running.

## Releasing

`scripts/release.sh` builds Glow for Apple silicon, signs it with a Developer ID, notarizes and staples it, and leaves `dist/Glow-<version>.dmg` with its checksum and debug symbols. `scripts/release.sh --unsigned` makes a test DMG without an Apple account. Until there is a Developer ID, the downloadable test DMG is signed with "Glow Local Signing", the identity `scripts/signing-identity.sh` makes, so the Accessibility grant survives updates. Back up its private key: a new certificate means everyone grants Accessibility once more. [release.md](release.md) covers the one-time setup, the test DMG and its backup, crash reports and the launch checklist.

## How it works

- **Capability catalog** (`CapabilityCatalog.swift`).
  - `MCCSCapabilities.parse` reads the monitor's capability report (VCP 0xF3). It tolerates sloppy firmware formatting and rejects oversized input.
  - `CapabilityCatalog` turns each code it knows into a `CapabilityDescriptor` with a plain-language label, section, order, control kind and risk.
  - It covers brightness, contrast, volume, mute, input, colour preset, picture mode, sharpness, the RGB gains and black levels, gamma, menu language, power and hours used. Gamma, menu language and hours used are shown and never written.
  - Unknown, manufacturer and maintenance codes appear only in Settings › Connection.
  - A new setting needs one catalog entry and no UI code.
- **Evidence.** Reported settings start as "Reported, not tested". Only a successful harmless read (`CapabilityDiscovery`, which never writes) makes one editable. A refused read marks it "Reported, but test failed".
  - A display that sends no capability report but answers reads gets one read of each catalogued setting. Those that answer are "Answered, not listed by the display". Only low-risk sliders and switches become editable; input, power, presets and picture modes stay read-only until a report lists them (ADR 0001, decision 14).
- **Rendering.** The Digital OSD is drawn only from `DisplaySnapshot.osdSections` through `CapabilityRenderer`, as a slider, picker, toggle, action, read-only value or unavailable state. `ControlStatus` is the single status component.
  - Settings has no native pop-ups or checkboxes (`SettingsControls.swift`). A few short choices are a row of Glow buttons (`ChoiceButtons`), a long list is a menu behind a Glow trigger with a small chevron (`MenuPicker`), and a yes-or-no choice, such as whether a scene includes a setting, is a check button VoiceOver reads as a checkbox (`CheckButton`).
- **Writes** (`DisplayWritePipeline`, `WriteCoalescer`).
  - Each value is validated, writes run in order per display, and stale display layouts are rejected.
  - The latest value wins, with one write in flight per display and setting. A new value goes out at once; while one is in flight only the newest waits, and the values it overtakes are never sent.
  - The last value of a run (a held key, a dragged slider) is confirmed by reading it back, with retries. The values before it skip the read-back. Only a confirmed value counts as set by Glow (ADR 0001, decision 4).
  - Writes **pause** during sleep, wake and display reconfiguration.
  - Input and power changes ask first, naming the display and the consequence. Scenes never apply destructive settings.
- **Adapters.** `MockDisplayAdapter` drives the demo displays. `HardwareDisplayAdapter` (`Hardware/`) drives the real ones. It gives each setting one route:
  - **Hardware control** (DDC/CI) for settings an external monitor answers a read for, listed in its report or not.
  - **Native control** for the built-in display's brightness, through macOS's DisplayServices (loaded at run time; it's private).
  - **Software dimming** for brightness on a display whose DDC brightness can't be read: Glow dims the picture through its gamma table, and the backlight doesn't change. It's labelled "Inferred" and says why.
- **DDC/CI on Apple silicon** (`IOAVTransport.swift`, `DDCPacket.swift`).
  - `DDCPacket` builds and checks the bytes: Get VCP, Set VCP, the capability request and save, each with its checksum. Bad checksums, "unsupported" replies and silent (all-zero) replies are told apart.
  - `DDCSession` sends them over an `I2CBus`, with the timing and retries of a `DDCTransportProfile`, and reassembles the capability string from 32-byte fragments within a deadline. `DDCLink` runs a session on one bus, one queue per bus: for a real display, a private `IOAVBus` over IOAVService, the private I2C path to an external display.
  - `DDCServiceMatcher` pairs each display with its IORegistry service by framebuffer location and EDID fields, best score first, so no service serves two displays.
  - Discovery reads only (`DDCDiscovery.swift`). It asks for the capability string and reads each listed OSD setting once. Those readings are the baseline. Codes the display reports that aren't in the catalog are read once too, with Get VCP only, and listed in Settings › Connection with their raw values; nothing can write them. A monitor that doesn't answer gets the honest note and software dimming, never a guessed value.
  - If the standard profile gets no reply, discovery tries slower timing, then the alternate address (source 0x50), with one Get VCP of brightness each. Retries stop once an exchange has blocked past the profile's window, and the ladder stops once a request has blocked for 3 s and then been refused (`DDCProbe.stallLimit`), since no other profile changes that. The profile that answered is kept for that display on that route while Glow runs. After a silent result, wake gets one quick try, and **Refresh Displays** tries every profile again.
  - Discovery publishes as it goes (`discover(generation:progress:)`). Every display shows at once, an external one as "Checking connection…", and each takes its place as its own probe finishes. On Refresh Displays, a shown monitor keeps its row until its new probe finishes.
  - Settings › Connection and Copy Report show each try with its timing and reason, the working profile, the raw capability string or "None", and every raw reading with its evidence.
  - Intel Macs build and run, but their IOFramebuffer DDC path isn't built, so external displays there get software dimming only.
- **Software dimming** (`SoftwareDimmer.swift`). It scales the display's own ColorSync table, never below 10 %, and only reports a level when the table is Glow's dimming of it. The table goes back to ColorSync on quit, on `SIGINT`/`SIGTERM`/`SIGHUP` and on switching to demo displays. Glow forgets the table of a display that goes away.
- **Brightness keys** (`Keys/`). A `CGEventTap` reads the brightness keys once Accessibility is allowed (`KeyAccess`); Settings › Controls asks for it. Glow takes each press and moves every target display by one step itself, the built-in display included. A step is 1/16 of the range like macOS, or 1 %, 2 %, 5 % or 10 % (Settings › Controls › **Brightness step**), and a press lands on the step's grid (with 5 %, 47 goes to 50). With fine adjustment on, Option-Shift moves a quarter step, never less than 1 % (1/64 for Like macOS). Hold a key and brightness moves 1 % every 20 ms, about two seconds from end to end, until you let go: Glow paces the hold with its own timer, and the keyboard's repeats only show the key is still down. The ramp stops at key-up, the other key, the range end, a pause, or the keys going to macOS, and after a short silence if a key-up is lost. "Mac only", demo displays, safe mode, and presses with Command, Control or Option alone go to macOS untouched. While writes are paused, Glow swallows the press rather than let macOS move a different display.
- **The overlay** (`Overlay.swift`). With **Show overlay on change** on, a panel on the display that changed shows the new level the moment it's proposed, updates in place while a key is held, and fades 1.5 s after the last change (no fade with Reduce Motion). The Boxes look is drawn as macOS's is: a sun or speaker, 16 boxes with the one the level falls in partly filled, the display's name, and "Software dimming" when Glow dims in software. The Slider look is a card with a thin level bar. A failed write shows in red.
- **Brightness Match** (`Match/`). Settings › Brightness Match › **Match Displays…** lines up how bright displays look. It's an appearance match, not color calibration.
  - It needs two displays whose brightness Glow can set, by any route. The reference is the built-in display unless you choose another.
  - A borderless grey patch, the same on every display, fills each screen being matched (demo displays get tiles in the window). You set each display with its slider or ←/→. **Quick Match** compares once, at the reference's brightness now. **Guided Match** compares at five levels, from dim to full.
  - Every change goes through the write pipeline, so it's confirmed by reading back and waits out sleep and reconfiguration. Cancel, Esc or closing the window puts each display back where it was and closes the patches. Saving puts the reference back and moves the others to match it.
  - Each match is a monotone, piecewise-linear curve for each display, clamped to its range (`MatchCurve`). Quick Match is a ratio through zero. Matches are saved in `GlowSettings.brightnessMatch`, keyed by display identity, with the method, the date and the route each display was matched over. A match made over one route is "out of date" on another and isn't followed.
  - The brightness keys, when they change every display, move matched displays along their curves. A display's own slider still sets that display alone, unless **Move matched displays together** is on, and then a reference's slider moves the displays matched to it.
  - On a software-dimmed display, matching dims the picture, not the backlight, and the pane says so.
- **Scenes** (`Scenes/`). A scene is a set of values per display, kept by display identity and setting.
  - **New Scene from Current Settings** (Settings › Scenes, or **+** beside the scenes in the popover) starts from what each connected display reads now. Only confirmed readings are used, never a guess. Input is left out unless you add it, and is then marked "Asks first". Power can never be part of a scene.
  - The editor names a scene, gives it a symbol and chooses which settings it includes, at which values. Until you type a name, the name follows the symbol: the moon makes it "Night". Other names nothing, so the scene goes back to the name Glow gave it. Scenes can be renamed, reordered and deleted. A display that isn't connected keeps its saved values, which can only be removed until it's back.
  - Applying a scene sends each value through the write pipeline and says exactly how much took: "Applied 2; 1 couldn’t be updated", with what was skipped and why. Settings a display doesn't support on this connection are skipped. A scene whose displays are all away says so and sends nothing. An input change is confirmed first, goes last, and can be left as it is while the rest applies.
  - A scene is **Active** while every display it names shows its values.
  - Demo displays come with three example scenes that live only in memory. Your own scenes are untouched while demo displays are on and come back when they're off.
  - **Restore Starting Values** (Settings › Displays) puts back what Glow read from a display at launch, as a scene of its own through the same checks. Settings that weren't read aren't touched.
  - **Reapply settings after wake** (Settings › Reading, off by default) waits until writes resume after a wake, then puts back what Glow last set and saw confirmed, where a display lost it. It never changes an input or power, and does nothing in safe mode.
- **Reading** (`Reading/`, ADR 0002). Glow rereads each display so a change made with the monitor's own buttons, or by macOS, shows up.
  - **Keep readings fresh** (Settings › Reading): Off, **While Glow is open** (the default: brightness, volume and mute every 5 s and every other setting every minute while Glow Desk or a Glow window is open), or Always (every 45 s and 10 min in the background).
  - A value a reread finds changed is updated everywhere and marked "Changed on the display" for a minute, in Settings › Displays and in Glow Desk's row. The built-in display says "Changed outside Glow", since macOS moves it too.
  - Reading never writes. Rereads pause while writes are paused, skip a setting with a change on its way and a display Glow wrote to in the last 2 s, and run on the display's own DDC queue, so a read never interleaves with a write. A display that doesn't answer is asked less often, from 30 s doubling to 15 min; one on software dimming is never read over DDC/CI. A reading that doesn't fit the setting, or a built-in brightness of exactly 0, is dropped and the last value kept.
  - **Read Again** in each display's Reading section rereads everything it reports, with the age ("Read 3 min ago") and what changed. **Read All** is in Settings › Reading.
  - **At launch:** read each display (the default), or put back what Glow last set and saw confirmed on each real display, with Reapply after wake's rules: never input or power, never in safe mode, for demo displays or while paused.
  - **Patience:** Normal, or Patient for displays that answer slowly or sit behind a hub. Patient raises each display's waits and retries to at least Slower timing's for reads and writes.
  - **Hide on This Display** (Control-click a setting in Settings › Displays) is for a setting a display reports that does nothing. It leaves the Digital OSD, Glow Desk and scenes, stays in Connection tagged "Hidden by you", and **Show** in the display's Hidden by you section brings it back. It's kept per display identity; demo displays can't hide anything.
- **Settings.** `GlowSettings` is saved as versioned JSON under `settings.v1`. Each field is decoded on its own, so an old or partial blob keeps its defaults. Scenes are saved there under `scenes` with a version of their own, and a damaged scene is dropped without losing the rest. The focused display, **Reapply settings after wake**, the brightness step, the look, and Settings › Reading's choices are saved there too. What Glow last set on each real display and the settings hidden on it each have their own versioned store inside it. Saved settings from before real displays existed had demo displays on by default; that's only kept if someone chose it. Open at login uses `SMAppService`. It can only register from an installed app, and under `swift run` the window says so.

## Not built yet

- DDC/CI on Intel Macs (IOFramebuffer I2C).
- Retrying one silent setting on the alternate DDC address (ADR 0001, decision 8). The alternate address is tried per connection, during discovery (decision 13).

## Documents

- [research/displaybuddy-vs-monitorcontrol.md](research/displaybuddy-vs-monitorcontrol.md): how two existing apps discover and control monitors.
- [adr/0001-capability-driven-control.md](adr/0001-capability-driven-control.md): the decisions that follow from both.
- [adr/0002-reading-displays.md](adr/0002-reading-displays.md): how Glow keeps readings fresh without ever writing.
- [release.md](release.md): signing, notarizing and the launch checklist.
- [legal/](legal/): drafts of the license agreement and privacy policy, for legal review.
- [QA_REPORT.md](../QA_REPORT.md): what was verified, and what wasn't.
- [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md): MonitorControl's licence, for the parts of its DDC approach Glow adapts.
