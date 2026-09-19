<p align="center">
  <img src="docs/images/hero.jpg" alt="Talky" width="820">
</p>

# Talky

**Traditional Chinese voice typing for the Mac. Double-tap the right ⌘ in any text field, speak, and clean written Chinese lands at your cursor.**

Your voice never leaves your computer. Whether the transcript goes to an AI for tidying, and which one, is your call.

[繁體中文](README.md)

<p align="center">
  <a href="https://github.com/intentionltd888/talky/releases/latest/download/Talky.dmg"><b>Download Talky.dmg</b></a>
  ・ Free, open source (MIT) ・ Apple silicon Mac, macOS 14 or later
</p>

<p align="center">
  <a href="https://github.com/intentionltd888/talky/releases"><img src="https://img.shields.io/github/downloads/intentionltd888/talky/total?label=downloads&color=003CFF" alt="total downloads"></a>
</p>

<p align="center">
  <img src="docs/images/demo.gif" alt="Double-tap right ⌘ → speak → tap again, tidy text is pasted at the cursor" width="760">
</p>

---

## Three steps

1. In any text field (Notes, a browser, LINE, Terminal) **double-tap the right ⌘**. A panel appears at the bottom of the screen and transcribes as you speak.
2. When you are done, **tap it again**. The panel says it is tidying.
3. The tidied text is **pasted at your cursor**. The panel says "pasted" and disappears on its own.

Made a mistake mid-sentence? Just say "no wait, ..." and only the corrected version is kept.
Where pasting is impossible (a password field, for example) the text goes to the clipboard and the panel tells you to press ⌘V.

<p align="center">
  <img src="docs/images/panel_polish.png" alt="Listening: text appears as you speak" width="640">
</p>

## Why

Almost every dictation tool on the Mac treats Simplified Chinese or English as its first language, and mixed Chinese-English sentences tend to get "helpfully" translated. Talky starts from the opposite three premises:

1. **Traditional Chinese (Taiwan usage) is the first language**, not a language pack.
2. **Mixed Chinese and English stays as spoken.** "這個 implementation 很 elegant" stays exactly like that.
3. **Taiwan's input environment**: Zhuyin IME on, browsers, terminals, Electron apps. It has to paste into all of them.

## Privacy: audio stays on your Mac

- **Speech recognition runs entirely on your Mac** (whisper.cpp with whisper large-v3-turbo, about 1.5GB, downloaded on first launch, works offline afterwards). Audio is never uploaded anywhere.
- **The only thing that can leave your computer is the recognised text**, and only if you chose a cloud tidying option, to your own AI account. Choose the built-in model and nothing leaves.
- Exactly two kinds of outbound connection: model download (direct from HuggingFace, SHA256 checked against a value compiled into the app) and the tidying service you picked. **No telemetry, no account, no update check.**
- External tidying tools are called fully isolated: no tools, none of your project settings, an empty neutral working directory, environment stripped. They do one thing: turn this spoken sentence into written Chinese.
- Any API key you enter lives only in the macOS Keychain. Exported diagnostics never contain keys.

## What does the tidying (compatibility)

"Tidying" means turning speech into writing: drop fillers, apply corrections, normalise to Traditional Chinese with full-width punctuation. The first-run wizard picks for you; change it any time under Settings → Advanced.

| Option | Where the transcript goes | Compatible with |
|---|---|---|
| **Your own AI subscription** (recommended) | To your account, on your own quota. Talky never touches it | Claude Code (Pro / Max), ChatGPT desktop or Codex CLI (Plus / Pro). If not installed, Talky installs it in-app, opens the browser for you to sign in, and binds it as soon as you are back. No Terminal |
| **Built-in local model** (no account) | Nowhere | Qwen3-4B, 2.5GB auto-download; 12GB RAM or more recommended |
| **Ollama** | Local | Any Ollama model, default `qwen3:4b` |
| **Your own endpoint** | Wherever you point it | OpenAI-compatible chat/completions, Anthropic Messages API (pay-as-you-go, key stored in Keychain) |
| **No tidying** | Nowhere | Traditional Chinese conversion and punctuation only, raw transcript pasted |

Fallbacks are ordered: cloud fails (not signed in, timeout) → local model if available → raw transcript. **It never silently pretends to succeed.** The panel shows which path was taken.

## Translate mode: speak Chinese, paste another language

**Double-tap the left ⌘** for translate mode. When you are done, double-tap either ⌘ to translate into the language highlighted on the panel, or click a language chip to translate into that one and send immediately. Each app remembers the language you last used with it.

Eight core languages: English, Japanese, Korean, Thai, Vietnamese, Indonesian, Spanish, French. German, Portuguese (Brazil), Simplified Chinese and written Cantonese can be enabled in Settings.
Politeness is set once, not per language: pick an **audience** (friend / colleague / stranger) and Japanese です・ます, Korean 해요体, French tu/vous follow. Thai sentence endings ครับ／ค่ะ take a separate one-time gender setting.

<p align="center">
  <img src="docs/images/panel_translate.png" alt="Translate mode: click a language chip" width="640">
</p>

## Website

The full story is at [intentionltd888.github.io/made/talky](https://intentionltd888.github.io/made/talky/): how much faster, messy in / clean out, translate mode, how your voice stays on your Mac, FAQ.

<p align="center">
  <a href="https://intentionltd888.github.io/made/talky/#speed"><img src="docs/images/site_speed.jpg" alt="Six minutes typed. One minute said." width="820"></a>
  <a href="https://intentionltd888.github.io/made/talky/#rules"><img src="docs/images/site_rules.jpg" alt="You say it messy. It pastes it clean." width="820"></a>
  <a href="https://intentionltd888.github.io/made/talky/#translate"><img src="docs/images/site_translate.jpg" alt="Say it in Chinese. Paste it in Japanese." width="820"></a>
</p>

## Install

1. [Download Talky.dmg](https://github.com/intentionltd888/talky/releases/latest/download/Talky.dmg), open it, drag Talky into Applications. Or just double-click Talky inside the DMG: it copies itself into Applications, pins itself to the Dock and opens. The DMG is Developer ID signed and notarised by Apple, so there is no security warning.
2. Open Talky from Applications. The first launch runs a five-step wizard: Microphone → Accessibility → tidying option → try a sentence → done. All you do by hand: click Allow, flip one switch in System Settings, say one sentence.
3. **Accessibility cannot be skipped.** Without it, double-tapping right ⌘ does nothing at all (hotkey detection and pasting into other apps both need it). Once granted, the app hooks the hotkey within 2 seconds.

Requirements: Apple silicon (M1 or later), macOS 14 or later. Intel Macs are not supported: the speech model takes over ten seconds per sentence on CPU, which is unusable.

**Want an AI to set it up for you?** Settings → Advanced has a paragraph at the top. Copy it into your own AI assistant and it will walk you through, following the [AGENTS.md](AGENTS.md) that ships inside the app bundle. The final check is you double-tapping right ⌘ yourself.
Terminal people: `bash scripts/setup.sh` prepares everything in one go.

If a meeting-notes app from the same maker is already installed, Talky reuses its downloaded speech model and glossary instead of fetching the same 1.5GB again. That logic lives entirely in `app/Sources/SharedPaths.swift`, one file, easy to remove.

## Build from source

```bash
xcode-select --install          # first time only
bash scripts/vendor-fetch.sh    # prepare the speech / tidying engines (copies an existing build if found, otherwise builds from source, 10–20 min)
bash build.sh                   # produces build/Talky.app
open build/Talky.app
```

- No Xcode project. It is a single `swiftc app/Sources/*.swift` invocation. `vendor/` (engine binaries) and `build/` (output) are not in git.
- Engines are pinned to fixed versions (`bash scripts/vendor-build.sh`) so behaviour does not drift with whatever is installed on your machine.
- Signing: a Developer ID certificate is used automatically if present, otherwise **ad-hoc**. The cost of ad-hoc is that after every rebuild, Accessibility looks enabled in System Settings but does not apply to the new binary (macOS cannot tell it is the same app). Wizard step 2 has a "clear the old record and reopen" button for exactly this. To pick a certificate: `TALKY_SIGN_ID="Apple Development: Your Name (XXXXXXXXXX)" bash build.sh`.
- Installer for others: `bash scripts/make-dmg.sh` builds the DMG, `bash scripts/notarize.sh` submits it to Apple and staples the ticket.
- Pre-publish hygiene scan: `bash scripts/check-clean.sh` must be green.

## Command line

```bash
/Applications/Talky.app/Contents/MacOS/Talky --doctor
# microphone / accessibility / model / tidying sign-in / is Talky running / is the hotkey armed / ports, all at once

/Applications/Talky.app/Contents/MacOS/Talky --ime-polish "呃就是那個我們明天下午三點要開會嘛,對對對"
# no UI, no audio: runs the tidying route and prints the result plus the path actually taken
```

Engine ports are `127.0.0.1:8932` (speech) and `127.0.0.1:8947` (local tidying), bound to localhost only.

## Where your data lives

| What | Where |
|---|---|
| Models | `~/Library/Application Support/Talky/models/` |
| Glossary | `~/Library/Application Support/Talky/glossary.txt` |
| Memo (last 20 dictations, click the Dock icon) | Local `UserDefaults`, never leaves the machine |
| Log | `~/Library/Logs/Talky/talky.log` |
| Settings | `defaults read ltd.intention.talky` |

## Not done yet

Listed honestly so you do not mistake it for a bug:

- Live transcription currently re-transcribes the last 45 seconds every 1.4 seconds. **VAD sentence splitting** is not in yet, so long dictations wait for one full re-pass after you stop.
- "Check for updates" and auto-update (Sparkle). New versions currently ship as a new DMG.
- Arbitrary hotkey recording ("Reset shortcut" offers right ⌘ / right ⌥ / fn only).
- Homebrew cask, GitHub Actions packaging.
- Pasting is "synthesised ⌘V then restore clipboard" only. Native field insertion is not implemented.
- With the lid closed (including clamshell mode with an external display), macOS cuts the built-in microphone at the hardware level and software cannot work around it. We tested. Use an external microphone for closed-lid dictation.

## Issues and contributing

- Something broke: Settings → General → "Export diagnostics to Desktop", then attach that txt to an [issue](https://github.com/intentionltd888/talky/issues/new/choose). It contains no keys.
- Want to help test: walk through [TESTING.md](TESTING.md), 25 items, each "do one thing, see one result".
- Want to change code: read [CONTRIBUTING.md](CONTRIBUTING.md) first. Most of the code comments are in Traditional Chinese.

## Follow

Talky is made by [INTENTION®](https://www.intention.ltd/). To see what we are working on, or to tell us what you think:

- Instagram: [@intention.ltd](https://www.instagram.com/intention.ltd)
- Website: [intention.ltd](https://www.intention.ltd/)
- Ideas and feedback: [Discussions](https://github.com/intentionltd888/talky/discussions). Something broke: open an [issue](https://github.com/intentionltd888/talky/issues/new/choose)

## License

Code is MIT, see [LICENSE](LICENSE).

The *talky logotype and the INTENTION® wordmark under `app/Resources/Brand/` are trademarks and **not covered by the MIT license**. They are included only so the app can display its own identity; see [app/Resources/Brand/TRADEMARK.md](app/Resources/Brand/TRADEMARK.md).

Open source used: [whisper.cpp](https://github.com/ggml-org/whisper.cpp) (MIT), [llama.cpp](https://github.com/ggml-org/llama.cpp) (MIT), the whisper large-v3-turbo speech model (MIT), the Qwen3-4B-Instruct tidying model (Apache 2.0).

Made by [INTENTION®](https://www.intention.ltd/), Taipei.
