# macos-finder-sort

Keyboard shortcuts that sort the front Finder window or Open/Save panel.

| Shortcut | Sort |
| --- | --- |
| ⌃⌥⌘M | Date Modified, newest first |
| ⌃⌥⌘N | Name, A to Z |

## Install

```bash
./install.sh
```

The script compiles `Sources/finder-sort.swift` to `bin/finder-sort` and adds two global BetterTouchTool keyboard shortcut triggers. Each trigger runs `do shell script "bin/finder-sort modified|name"` as an inline AppleScript action, so BetterTouchTool's Accessibility permission covers `finder-sort`. Running the script again adds duplicate triggers.

## How it sorts

`finder-sort` uses the Accessibility API on the frontmost app's focused window:

- Finder list view: presses the column header until the column's `AXSortDirection` matches (descending for Date Modified, ascending for Name).
- Finder icon, column and gallery views: presses View > Sort By > Date Modified or Name.
- Open/Save panel in list view: presses the header button in the panel's `ListViewHeader` group until its `AXSortDirection` matches.
- Open/Save panel in another view: sends ⌘2 to switch the panel to list view, then a detached `finder-sort` process sorts it. The panel applies ⌘2 only after the BetterTouchTool action returns.

In any other window the command exits 1 and changes nothing. Column titles are matched in English.

`bin/finder-sort debug` prints the front window's Name and Date Modified sort state without changing it.
