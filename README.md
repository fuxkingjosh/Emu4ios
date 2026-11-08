# Emu4ios

A free, fully customizable retro game emulator for iPhone and iPad.

**33 systems, every feature free:** Game Boy · Game Boy Color · Game Boy Advance · NES / Famicom · Super Nintendo · Nintendo 64 · Nintendo DS · Virtual Boy · Pokémon mini · Genesis / Mega Drive · Sega CD · Master System · Game Gear · SG-1000 · PlayStation · PSP · TurboGrafx-16 / PC Engine (+CD) · SuperGrafx · Neo Geo Pocket (Color) · WonderSwan (Color) · Atari 2600 / 5200 / 7800 / Lynx / Jaguar · Commodore 64 · Amiga · MS-DOS · DOOM

## Features

- **Theme engine**: change every color, font and text label in the app, animated backgrounds, screen borders and glow
- **Controller editor**: move, resize, reshape and recolor every button, separately for portrait and landscape and for each system. You can also set vibration strength, button sounds, turbo buttons and extra action buttons.
- **Theme sharing**: share a theme as a link, QR code or `.e4theme` file
- **Per-game and per-system themes**
- **Screen filters**: CRT, LCD grid, original Game Boy green, Pocket, color correction, scanlines, smooth
- **Rewind and fast-forward** (up to 8×), plus save states with screenshot previews, quick save/load and auto-resume
- **Cheats**: GameShark, Action Replay, CodeBreaker and Game Genie
- **Screen gestures** you can remap: swipe to save, two-finger tap for the menu, and more
- **Gameplay clips**: save the last 15/30/60 seconds to Photos
- **Play stats** and a **"Continue Playing" Home Screen widget**
- **iCloud sync** for saves, states and themes
- **Custom app icons**
- **Bluetooth controllers and keyboards** — up to four players
- **RetroAchievements** with hardcore mode, pop-ups, progress and leaderboards
- **Cheat library**: about 22,000 games' cheats from the libretro database, one tap to add
- **Local multiplayer**: friends nearby use their own iPhone as player 2–4 (no internet needed)
- **TV mode**: AirPlay or HDMI shows the game full screen while the phone is the controller
- **Delta skin import**: `.deltaskin` files become Emu4ios themes
- **Smart import**: works out the console from inside the file (.bin/.iso/.cue/.chd/.pbp), unpacks .zip archives, WebDAV server downloads
- **DS touch screen**, analog sticks (N64/PSP), and a full keyboard + trackpad mouse for DOS, C64 and Amiga

Emu4ios includes **no games**. Players import their own game files.

## How it's built

| Part | Where |
|---|---|
| SwiftUI app | `App/Sources` |
| C bridge to the emulator core | `App/Bridge/E4Emulator.{h,c}` |
| mGBA core (GB/GBC/GBA, MPL-2.0), built for iOS | `scripts/build-mgba.sh` |
| 23 libretro cores (list, licenses and pinned versions) | `cores/cores.json`, built by `scripts/build-core.sh` |
| libretro bridge: loads cores with dlopen, OpenGL ES for N64/PSP, all input types | `App/Bridge/E4Libretro.{h,c}`, `E4GL.{h,m}` |
| RetroAchievements (rcheevos, MIT) | `App/Bridge/rcheevos`, `App/Bridge/E4Achievements.{h,c}` |
| Linux test harness for cores | `Tests/core_test.c`, `Tests/make_test_roms.py` |
| Xcode project (generated) | `project.yml` (XcodeGen) |
| Home Screen widget | `Widget/` |
| Cloud Mac builds | `.github/workflows/build.yml` |

You don't need a Mac. Every push to `main` builds the app on a free GitHub cloud Mac. Check the **Actions** tab.

## Publishing to the App Store (one-time setup)

1. **Join the Apple Developer Program** ($99/year) at developer.apple.com/programs.
2. **Create the app in App Store Connect**: go to My Apps → + → New App and use bundle ID `com.fuxkingjosh.emu4ios`.
3. **Make an API key**: in App Store Connect, go to Users and Access → Integrations → App Store Connect API → Team Keys → +, with the **Admin** role. Download the `.p8` file. You can only download it once.
4. **Add 4 secrets to GitHub** under repo **Settings → Secrets and variables → Actions → New repository secret**:
   - `ASC_KEY_ID`: the key's ID
   - `ASC_ISSUER_ID`: the Issuer ID shown above the keys list
   - `ASC_KEY_P8`: the full text of the `.p8` file
   - `APPLE_TEAM_ID`: your Team ID, from developer.apple.com → Account → Membership
5. **Upload a build**: go to **Actions → Build → Run workflow**, tick **Upload to TestFlight**, and run it.
6. **Test it** on your iPhone with the TestFlight app, then submit it for review in App Store Connect.

The App Store listing needs a privacy policy URL. You can use the link to [`PRIVACY.md`](PRIVACY.md) in this repo.

## License

Emu4ios is free software under the **GNU General Public License v3** — see [LICENSE](LICENSE).

It uses [mGBA](https://github.com/mgba-emu/mgba) (Mozilla Public License 2.0) and
[PCSX-ReARMed](https://github.com/libretro/pcsx_rearmed) (GPL-2.0-or-later).
Emu4ios is not affiliated with Nintendo or Sony Interactive Entertainment.

PlayStation games run without a BIOS file (PCSX-ReARMed's built-in BIOS). For best compatibility you can
put your own `scph5501.bin` in the Files app under **Emu4ios › BIOS**.
