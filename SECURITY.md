# Security Policy

Cubby handles whatever you copy, which often includes passwords, tokens and private messages. We take reports about it seriously.

## Supported versions

Cubby is maintained by a small team, so only the latest release receives security fixes.

| Version | Supported |
| --- | --- |
| 0.2.x (latest) | Yes |
| < 0.2 | No |

When a new minor version ships, the previous one stops receiving fixes. Please update before reporting, if you can.

## Reporting a vulnerability

**Please do not report security issues in public issues, discussions or pull requests.**

Use GitHub's private vulnerability reporting instead: go to the repository's **Security** tab and click **Report a vulnerability**, or open <https://github.com/no1coder/cubby/security/advisories/new> directly.

Please include:

- Cubby version and how you installed it (Homebrew, DMG or source build)
- macOS version and chip (Apple silicon or Intel)
- The output of **Settings › About › Copy Diagnostic Info**, if relevant (it never contains clipboard content)
- Steps to reproduce, and what an attacker could achieve
- A proof of concept, if you have one. Use made-up data, never real secrets.

## Scope

In scope:

- **Data exposure.** Clipboard history readable by other users or processes beyond what macOS already allows; data written outside the data folder or with weaker permissions than documented; clipboard content in logs, crash reports or diagnostic output; history leaving the Mac in any way.
- **Filtering failures.** Content marked concealed or transient, or content from an excluded app, being recorded anyway.
- **Mis-paste.** Content pasted into an app other than the one Cubby shows as the target, or pasted without a user action.
- **Permissions.** Cubby's Accessibility permission being usable by another process to control the Mac, or Cubby doing more with it than sending <kbd>⌘V</kbd>.
- **Signing and update chain.** Releases that are not signed by the expected Developer ID or not notarized, a way to make the update check point users to an unofficial download, tampering with release assets or the Homebrew cask, and weaknesses in the release workflows in `.github/workflows`.
- **Network access** other than the documented update check. See [PRIVACY.md](PRIVACY.md).

Out of scope:

- Attacks that require an already compromised user account, root access, or physical access to an unlocked Mac
- Other apps reading the system clipboard, which macOS allows by design
- Vulnerabilities in macOS itself (please report them to [Apple](https://security.apple.com))
- The secret filter not recognizing a particular token format. It is a best-effort heuristic; please open a regular issue or pull request with a fake sample.
- Missing hardening without a demonstrated impact

## What to expect

- **Acknowledgement** within 3 business days.
- **Initial assessment** within 7 days, including whether we consider it a vulnerability and how severe it is.
- **A fix** as soon as practical, aiming for 30 days for high-severity issues. We will keep you updated if it takes longer.
- **Disclosure** through a GitHub Security Advisory once a fixed release is available, coordinated with you. We will credit you unless you prefer otherwise.

## Verifying a release

Official releases are signed with a Developer ID (Team ID `69A75B6U2B`) and notarized by Apple. To check an installed copy:

```sh
spctl -a -vvv /Applications/Cubby.app                              # expect: source=Notarized Developer ID
codesign -dv /Applications/Cubby.app 2>&1 | grep TeamIdentifier    # expect: TeamIdentifier=69A75B6U2B
```

Each release also includes `SHA256SUMS.txt`. Compare it with `shasum -a 256 Cubby-x.y.z.dmg`.
