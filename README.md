# Prescient

A native macOS GUI for searching file contents and file names in a folder —
essentially a graphical `grep`, with Emacs integration for opening results at
the matched line.

## Features

- Recursive folder search with include filters and folder/file exclusions
- Multiple search terms (a line matches if it contains any of them)
- Match case, whole word, and regular expression options, with matches highlighted
- Recent searches per workspace
- Export results as text or CSV
- File-name search mode
- Opens results in Emacs at the matched line
- Stop button and live searched-file counting

## Install (Homebrew)

```bash
brew install --cask --no-quarantine HalloweenJack2606/tap/prescient
```

`--no-quarantine` is required while the app is unsigned. Requires macOS 26 (Tahoe)+.

## Build from source

```bash
xcodebuild -project prescient.xcodeproj -scheme prescient -configuration Release build
```

## Release

`scripts/release.sh [version]` builds the app and packages `dist/Prescient-<version>.dmg`,
printing the `sha256` to update in the Homebrew cask.
