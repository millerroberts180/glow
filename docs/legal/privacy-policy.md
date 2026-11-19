# Glow privacy policy

> **Draft for legal review. Not in force.** No lawyer has reviewed this draft. Text in [square brackets]
> is a placeholder to fill in before Glow is released. It describes Glow as the code stands on
> 2026-11-16. Check it again whenever Glow starts to store, read or send something new.

Last updated: [date]

Glow is a menu-bar app for macOS that controls your displays, made by [owner's full legal name or
business] ("we"). This policy says what Glow keeps, what it reads and what it sends.

**In short:** Glow works on your Mac. It has no account, no analytics, no advertising and no tracking,
and it never connects to the internet. What it keeps stays on your Mac, and we never receive it.

## What Glow keeps, only on your Mac

- **Your settings**, in macOS's preferences for Glow (`~/Library/Preferences/`, under Glow's bundle ID,
  `com.millerroberts.Glow`). They hold the choices you make in Settings and setup, and:
  - your scenes, and the values each one sets;
  - your Brightness Match curves, which say how bright each matched display should be for a given
    brightness of the display you matched them to;
  - for each display you use with Glow, the values Glow last set on it, such as brightness, contrast
    and volume, so they can be put back at launch or after a wake if you choose. Input and power are
    never kept;
  - the settings you chose to hide on a display, and the display you chose for the brightness keys.

  Glow tells your displays apart by the maker's number, model number and serial number each display
  reports to your Mac. Those numbers, kept with the values above, are the only details of your displays
  it stores.
Glow keeps no other files. The settings it changes on your monitors are kept by the monitors
themselves, as they would be if you had used their own buttons.

Earlier test versions of Glow had a trial. They kept the dates of the days it counted in Glow's
preferences and in an item named "Glow trial" in your login keychain, and any license key entered in
the preferences. Glow now deletes these each time it opens. macOS doesn't let one version of an app
delete a keychain item that another version made, so the "Glow trial" item can stay; it holds only
those dates, and Glow no longer reads it.

## What Glow reads but does not keep

- **Your displays.** To find out what each display can do, Glow reads what macOS knows about it (its
  name, maker, model and serial numbers, size and date of manufacture, and how it is connected), and
  asks each external monitor over DDC/CI, through its video cable, which settings it supports and what
  they are set to. It reads the brightness of your built-in display and Apple displays from macOS, and
  each display's color tables. Glow shows these in Settings and keeps only what is listed above.
- **Your Mac's model name**, such as "MacBook Air", to name the built-in display.
- **The brightness keys.** With the Accessibility permission, Glow is told about your keyboard's
  special keys (brightness, volume, media and the like), never about typing. It acts on the two
  brightness keys, and whether Shift, Option, Control or Command is held with them; every other key goes
  on to macOS unchanged. When the keys are set to change the display under the pointer, Glow asks macOS
  where the pointer is as you press one.
- **Sleep and wake.** macOS tells Glow when your Mac and its displays sleep and wake, so Glow can put
  your settings back after a wake if you turn that on.

## What leaves your Mac

Nothing reaches us. Glow has no network code at all: no analytics, crash reporting or update check of
its own, and it sends no data to us or anyone else. The commands it sends to your monitors go only to
them, through their video cables.

Some links in Glow open other software, under that software's own privacy terms, and only when you
click them: the website, privacy policy, license agreement and support links in Settings › Glow open in
your browser, and the support link goes to Glow's issue tracker on GitHub. Allow…, for the brightness
keys, opens System Settings.

macOS itself may contact Apple about Glow, for example to check its notarization the first time you
open it, or to send a crash report if you have chosen to share analytics with Apple. Apple's privacy
policy covers that.

## Your choices

- Delete a scene (Settings › Scenes), forget your Brightness Match curves (Settings › Brightness Match ›
  Forget Match), or hide a setting on a display, from within Glow.
- Withdraw the Accessibility permission in System Settings › Privacy & Security › Accessibility. The
  brightness keys then go back to macOS.
- Turn off Open at login in Settings › General.
- To remove everything Glow has kept: quit Glow and move it to the Trash, then delete its preferences
  (in Terminal, `defaults delete com.millerroberts.Glow`), and delete any "Glow trial" item an earlier
  version left in Keychain Access. The settings Glow set on your
  monitors stay on them; change them from each monitor's own menu.

Because we never receive your Glow data, we cannot see, export or delete it for you; it is all on your
Mac, under your control.

## Children

Glow is not directed at children, and we do not knowingly collect information from anyone.

## Changes

If a new version of Glow changes what it keeps, reads or sends, we will update this policy before that
version is released, and change the date above.

## Contact

[Support email]
[owner's full legal name or business, and postal address]
