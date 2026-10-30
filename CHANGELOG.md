# Changelog

## [1.2.0] - 2026-10-30

### Added
- **Regex and whole-word search**: `Aa` (match case), `ab` (whole word) and `.*`
  (regular expression) toggles in the Text field. Invalid patterns and grep
  errors are shown in the summary line instead of returning no results.
- **Match highlighting** in the results Text column.
- **Recent searches**: a clock menu in the Text field recalls the last 20
  searches (terms and options) of the active workspace.
- **Export results**: copy all results, or save them as text (`path:line:text`)
  or CSV. ⌘C copies the selected rows.

### Changed
- The Case Sensitive checkbox moved into the Text field as the `Aa` toggle.

### Fixed
- README described multiple search terms as AND matching; they match any term.

## [1.1.0] - 2026-10-26

### Added
- **Workspaces**: save named sets of search settings (folder, file filters,
  exclusions, and the Subfolders / Case Sensitive / File Names toggles) and
  switch between them from the toolbar. Create, rename, and delete workspaces;
  changes auto-save to the active one. Existing settings migrate to a
  "Default" workspace on first launch.

### Fixed
- "Open in Emacs" no longer resolves files against a stale folder bookmark
  after the folder was typed in manually.

### Changed
- Reorganized the codebase into `App`, `Models`, `Search`, `Workspaces`,
  `Emacs`, and `Views` folders; search state and workspace persistence moved
  out of the main view.

## [1.0.0] - 2026-08-05

### Added
- First release: GUI file & text search for macOS with Emacs integration.
- Recursive search with include filters and folder/file exclusions.
- Multiple search terms, case-sensitive toggle, and file-name search mode.
- Results context menu: open in Emacs / Finder / Terminal, copy path or
  match, search this file only, copy grep command, exclude file or folder.

### Fixed
- Folder field now honors typed paths instead of reverting to the last
  browsed folder.
- Clicking anywhere in a text field places the caret; the search field is
  focused on launch.

[1.2.0]: https://github.com/HalloweenJack2606/prescient/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/HalloweenJack2606/prescient/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/HalloweenJack2606/prescient/releases/tag/v1.0.0
