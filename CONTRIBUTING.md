# Contributing to Cubby

Thanks for your interest in Cubby. Bug reports, translations, documentation fixes and code are all welcome.

- **Found a bug?** Open an issue with the bug report template and paste the output of **Settings › About › Copy Diagnostic Info**. It never contains clipboard content.
- **Have an idea?** Check the [roadmap](docs/ROADMAP.md) first, then open a feature request or start a [discussion](https://github.com/no1coder/cubby/discussions).
- **Found a security issue?** Do not open a public issue. Follow [SECURITY.md](SECURITY.md).

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Development setup

- **Xcode 26 or later** (Swift 6.2 and the macOS 26 SDK; the panel uses `NSGlassEffectView`), on a macOS version that Xcode 26 supports.
- Cubby itself runs on **macOS 14 or later**. Guard newer APIs with `#available` and keep the macOS 14 code path working.
- No third-party dependencies and no Xcode project: Cubby is a Swift package. Open `Package.swift` in Xcode if you prefer an IDE.

```sh
git clone https://github.com/no1coder/cubby.git
cd cubby
make test
```

### Make targets

| Command | What it does |
| --- | --- |
| `make build` | Debug build (`swift build`) |
| `make test` | Run the unit tests (Swift Testing) |
| `make lint` | Check formatting with `swift format` (configured in `.swift-format`) |
| `make check-cjk` | Fail if a Swift string literal still contains Chinese text (user-facing strings belong in the String Catalog) |
| `make strings` | Extract localizable strings from the sources into `Resources/Localizable.xcstrings`, then list new, stale and untranslated keys |
| `make check-strings` | Fail if the String Catalog is out of sync with the sources or any zh-Hans translation is missing (runs in CI) |
| `make coverage` | Run the tests with coverage and enforce the CubbyCore line-coverage threshold |
| `make format` | Reformat `Sources` and `Tests` in place |
| `make app` | Build a Universal release app at `build/Cubby.app` |
| `make run` | Build the app and launch it |
| `make install` | Build, copy to `/Applications` and launch |
| `make clean` | Remove `.build`, `build` and `dist` |

### Project layout

```
Sources/
  CubbyCore/        Pure logic, no UI, fully unit-tested
    Models/           ClipItem, content classification, HEX colors, hashing, secret detection
    History/          ClipHistory (immutable value type), filtering, ClipStore (state, undo, persistence)
    Storage/          JSON history storage, blob store, coalesced saving, private file permissions
    Clipboard/        NSPasteboard reading and writing, including rich text
    Settings/         User settings and the hot key model
    Panel/            Panel placement and keyboard command mapping
  Cubby/            The app: AppKit and SwiftUI
    App/              Entry point, AppDelegate, menu bar, main menu, data paths
    Services/         Clipboard monitor, global hot key, paste, permissions, image cache, HUD, drag and drop
    Panel/            Floating panel, preview panel, view model
    Views/            SwiftUI views for the panel and design tokens
    Settings/         Settings window and shortcut recorder
    Onboarding/       First-launch guide
    UserGuide/        User guide window: renders docs/USER-GUIDE*.md, bundled by scripts/build-app.sh
Tests/CubbyCoreTests/ Swift Testing unit tests
Resources/          Info.plist, app icon, string catalog
scripts/            Build, release and check scripts
docs/               Design spec, roadmap, QA checklist, README assets
```

Put logic in `CubbyCore` whenever it can be expressed without AppKit windows or views. It is the part we can test thoroughly.

## Running a development build

### Keep your real history out of it

Set `CUBBY_DATA_DIR` to store history and images in a separate folder instead of `~/Library/Application Support/Cubby`:

```sh
swift build
CUBBY_DATA_DIR=/tmp/cubby-dev .build/debug/Cubby -hasCompletedOnboarding YES --show-panel
```

`-hasCompletedOnboarding YES` overrides that preference for this launch only, so the first-launch guide is skipped.

`.build/debug/Cubby` is a bare executable, not an app bundle, so macOS usually attributes permission prompts to the terminal that launched it. To test permissions or direct pasting, use `make run` or `make install`.

### Screenshot scenarios

Debug builds accept `--scenario <name>` to open the UI in a known state. In this mode Cubby skips onboarding and does not register the global shortcut, so it will not clash with an installed copy.

| Scenario | Shows |
| --- | --- |
| `panel` | The panel |
| `preview` | The panel with the side preview open |
| `help` | The panel with the shortcut help overlay |
| `search:<text>` | The panel with `<text>` typed into the search field |
| `category:<name>` | The panel filtered to `all`, `text`, `link`, `image`, `file`, `color` or `favorite` |
| `settings:<pane>` | The settings window on `general`, `history`, `privacy`, `translation` (macOS 26) or `about` |
| `onboarding` | The first-launch guide |
| `guide` | The user guide window (the English or Simplified Chinese guide, following the app language) |
| `guide:<text>` | The user guide with `<text>` in its search field |
| `screenshot:permission` | The Screen Recording permission guide |
| `screenshot:pin` | Two pinned screenshots made from a generated image (the first one is key) |
| `screenshot:<state>` | The screenshot overlay in a preset state on a generated desktop with three overlapping fake windows. It needs no Screen Recording permission and never captures your real screen. States: `hovering`, `selecting`, `adjusting`, `annotating`, `annotating:<tool>`, `text`, `tiny`, `edge`, `fullscreen`, `hover-cycle`, `window-mode` |
| `screenshot:live` | A real capture of all screens (needs Screen Recording). The capture time is written to the unified log (`log show --predicate 'subsystem == "io.github.no1coder.Cubby"'`) |
| `screenshot:translate` | The screenshot overlay translating the generated desktop with a stub engine (macOS 26; nothing is sent anywhere) |
| `translation:download` | The system translation language download window (macOS 26). Close it; don't confirm a download you don't want |
| `screenshot:window-probe` | Captures Cubby's own demo pin with and without the window shadow and logs the size and corner transparency; with `CUBBY_DATA_DIR` set, both images are written there (needs Screen Recording) |

Add `--light` to force the light appearance:

```sh
CUBBY_DATA_DIR=/tmp/cubby-demo .build/debug/Cubby --scenario search:swift --light
```

Translation walkthroughs can add `--fake-translation-key <preset id>` (an obviously fake key held in memory only, to see the masked display), `--fake-keychain-failure` (every key read or write fails, as if Keychain access was denied) and `--translation-probes` (refreshes the model list and tests the connection when the pane opens; only loopback addresses are allowed). None of them touch your Keychain or a real service.

### Test tools

| Command | What it does |
| --- | --- |
| `make e2e` (`--e2e <names\|all>`) | Screenshot end-to-end scripts driven by synthetic input on a generated desktop, with a private pasteboard |
| `make e2e-panel` (`--panel-e2e <names\|all>`) | Panel and clipboard-translation end-to-end scripts with demo items, a private pasteboard and a stub translation service |
| `--translate-qa <corpus.json> <outdir>` | Runs the real recognition and layout pipeline on synthetic screenshots from `Tests/TranslationQA/corpus.json` and writes before/after images and an `index.html` |
| `--clip-translation-selftest` | Exercises the clipboard translation service with stub engines in a temporary data directory |

The end-to-end suites need an unlocked screen, and take over the screen while they run: don't use the mouse or keyboard until they finish.

The full list lives in `AppDelegate.applyDebugScenario`, `PanelController.applyDebugScenario` and `ScreenshotCoordinator.startDebugScenario`. Only use demo data for screenshots: file cards show full paths, including your user name.

## Local signing and permissions

macOS ties the Accessibility permission to the app's code signature. `make app`, `make run` and `make install` sign with, in order:

1. `SIGN_IDENTITY`, if set (`-` means ad-hoc);
2. the first **Apple Development** certificate in your keychain;
3. an ad-hoc signature.

An ad-hoc signature changes on every build. After a rebuild, System Settings still shows Cubby as allowed under Accessibility, but the permission no longer applies and Cubby only copies instead of pasting.

**Recommended:** create a self-signed code signing certificate once.

1. Open Keychain Access › Certificate Assistant › Create a Certificate…
2. Name it `Cubby Local`, set Certificate Type to **Code Signing**, and create it.
3. Build with it:

   ```sh
   SIGN_IDENTITY="Cubby Local" make install
   ```

The permission is then tied to your certificate rather than to a single build, and survives rebuilds.

**Otherwise**, after each rebuild, reset the permission and grant it again:

```sh
tccutil reset Accessibility io.github.no1coder.Cubby
```

The same thing happens when you switch between your own build and an official release (signed with the maintainer's Developer ID): remove Cubby from the Accessibility list with **−**, or run the command above, then grant access again.

## Code style

- **Keep it simple.** Solve the problem at hand; avoid speculative abstractions and options.
- **Immutable value types.** Prefer `struct` and `enum` with `let` properties. Return an updated copy instead of mutating shared state; `ClipHistory` is the model to follow.
- **Swift 6 strict concurrency.** UI code runs on `@MainActor`. Don't silence the compiler with `@unchecked Sendable` or `nonisolated(unsafe)` without a comment explaining why it is safe.
- **Small files and functions.** Keep files under 400 lines and functions short. Split by feature rather than piling onto an existing file.
- **Follow [docs/DESIGN.md](docs/DESIGN.md).** Take sizes, radii and font sizes from `DesignTokens.swift` instead of hard-coding numbers. Don't open sheets or popovers from the panel, because they take key focus and close it.
- **No new dependencies.** The app has zero third-party dependencies. Open an issue before proposing one.
- **No new network access.** The update checker is the only code allowed to touch the network. Anything else needs discussion and an update to [PRIVACY.md](PRIVACY.md).
- **Never log clipboard content.** Use `Logger` with the subsystem `io.github.no1coder.Cubby`, and mark any interpolated user content `privacy: .private`.
- **Comments.** Code comments in this repository are written in Simplified Chinese. English comments are welcome in new files; when editing an existing file, match the language already used there. Identifiers, commit messages and user-facing source strings are English.
- **Formatting.** Run `make format`; `make lint` must pass.

## Tests

- Tests use Swift Testing and live in `Tests/CubbyCoreTests`. New logic in `CubbyCore` needs tests, and CI enforces a coverage threshold for `CubbyCore`.
- Tests must never touch real data or preferences. Use the helpers in `Tests/CubbyCoreTests/Support` (`IsolatedDefaults`, `InMemoryHistoryStorage`, fixtures).
- Build fake tokens with `FakeSecrets` instead of committing literals that look like real credentials.
- The app layer has no UI tests. For UI changes, walk through the relevant parts of [docs/QA-CHECKLIST.md](docs/QA-CHECKLIST.md) in both light and dark mode.

## Localization

English is the development language. Cubby ships in English and Simplified Chinese.

- Every new user-visible string goes into the String Catalog `Resources/Localizable.xcstrings` with a Simplified Chinese translation.
- SwiftUI `Text("…")` literals are localized automatically. In AppKit code and `CubbyCore`, use `String(localized: "…", comment: "…")`, and write a comment that tells translators where the string appears.
- Don't hard-code Chinese or other non-English text in `Sources`; CI fails on CJK string literals.
- Don't build sentences by concatenation. Use whole-sentence format strings such as `"Paste to %@"`, and catalog plural variations for counts (`"%lld items"`).
- After adding strings, run `make strings` to extract them into the catalog, then fill in the Simplified Chinese translations. Xcode's String Catalog editor works well for this.
- Check the layout with long strings and missing translations:

  ```sh
  open build/Cubby.app --args -AppleLanguages '(en)' -NSDoubleLocalizedStrings YES
  open build/Cubby.app --args -AppleLanguages '(zh-Hans)' -NSShowNonLocalizedStrings YES
  ```

Want to add a language? Open an issue first so we can agree on how it will be maintained.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/) in English:

```
<type>: <description>

<optional body>
```

Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`. Write the description in the imperative mood and keep the first line under 72 characters. For example:

```
fix: keep the selection when the preview panel closes
feat: add a Quick Look preview for PDF files
```

## Pull requests

1. For a new feature or a large change, open an issue first so we can agree on the approach. Small fixes can go straight to a pull request.
2. Fork the repository and create a branch from `main`.
3. Keep each pull request focused on one change.
4. Run `make test` and `make lint` before pushing.
5. For UI changes, attach screenshots in light and dark mode, and in both languages if you changed text.
6. For user-visible changes, add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md).
7. Fill in the pull request template, use a Conventional Commits style title, and make sure CI is green.

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
