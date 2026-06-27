
<p align="center">
  <img height="120" alt="Scribe logo" src="Scribe/Assets.xcassets/ScribeLogo.imageset/ScribeLogo.png" />
</p>

<h1 align="center">Scribe</h1>

<p align="center"><em>On-device AI autocomplete for macOS. Free. Private. Fast.</em></p>

---

## What it does

Scribe watches wherever you're typing across macOS — Notes, Mail, Messages, Chrome, VS Code, Slack, etc. — and shows AI-powered ghost-text completions inline. Press **Tab** to accept. No cloud. No API key. Runs the model locally via llama.cpp.

## Requirements

- macOS 14 Sonoma or later
- A GGUF model file (recommended: `gemma-4-E2B-i1-Q4_K_M.gguf`)
- ~4 GB RAM free for the model

## Setup

1. Open `Scribe.xcodeproj` in Xcode
2. Select the **Scribe Dev** scheme and run
3. Grant Accessibility permission when prompted
4. Open **Settings → AI → Import Model** and select your `.gguf` file
5. Start typing anywhere — ghost text appears after a short pause

## Model

Scribe is tuned for **Gemma 4 E2B** base models (2B parameters, Q4\_K\_M quantization). Drop your GGUF file anywhere; import it via Settings. The app picks the best quant variant automatically.

Other GGUF base models work too (Qwen, Mistral, etc.) — import any file and Scribe will use it.

## Build from source

```bash
git clone <this-repo>
cd jot
# Create signing config (replace XXXXXXXXXX with your Apple Team ID)
echo 'DEVELOPMENT_TEAM = XXXXXXXXXX\nCOTABBY_DEV_BUNDLE_ID = com.yourname.jot.dev' > Config/Signing.local.xcconfig
open Scribe.xcodeproj
```

Select **Scribe Dev** scheme → Product → Run.

## Architecture

- **llama.cpp** runs in-process via the `CotabbyInference` Swift package
- Suggestions generate on a background actor; never block the UI thread
- Accessibility API watches focus + caret position across all apps
- Ghost text renders in a transparent overlay near the caret
- Tab acceptance replays keystrokes to insert text into any app

Key source paths:

| Path | What lives here |
|------|----------------|
| `Scribe/App/` | App lifecycle, coordinators |
| `Scribe/Services/Runtime/` | llama.cpp runtime, model loading |
| `Scribe/Services/Accessibility/` | AX focus tracking, caret geometry |
| `Scribe/UI/` | Settings, onboarding, ghost-text overlay |
| `Scribe/Support/` | Pure helpers, prompt post-processing |

## Debugging

Launch with `-cotabby-debug` argument (Xcode scheme → Arguments Passed On Launch) to enable file logging:

```bash
# Tail live suggestion events
jq 'select(.category == "suggestion")' ~/Library/Logs/Cotabby\ Dev/cotabby.jsonl

# See full LLM prompt + completion for a request
jq 'select(.request_id == "req_XXXXX")' ~/Library/Logs/Cotabby\ Dev/llm-io.jsonl
```

## License

AGPL-3.0. See [LICENSE](LICENSE).
