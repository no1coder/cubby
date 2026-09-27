## Summary

<!-- What does this change, and why? Link the related issue, for example "Closes #123". -->

## How to test

<!-- Steps a reviewer can follow to verify the change. -->

## Screenshots

<!-- For UI changes: before and after, in light and dark mode, and in English and Chinese if you changed text. Use demo data only. Delete this section if it doesn't apply. -->

## Checklist

- [ ] `make test` passes
- [ ] `make lint` passes
- [ ] New or changed logic in `CubbyCore` is covered by tests
- [ ] UI changes include screenshots in light and dark mode
- [ ] New user-visible strings are in `Resources/Localizable.xcstrings` with Simplified Chinese translations
- [ ] User-visible changes are listed under `## [Unreleased]` in `CHANGELOG.md`
- [ ] No new dependencies or network access (or agreed in an issue first)
- [ ] The PR title follows [Conventional Commits](https://www.conventionalcommits.org/) (`feat: …`, `fix: …`)
