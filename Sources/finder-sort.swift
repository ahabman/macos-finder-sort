// finder-sort: sort the frontmost Finder window or Open/Save panel.
//
//   finder-sort modified   Date Modified, newest first
//   finder-sort name       Name, A to Z
//
// Works through the Accessibility API, so the process that launches it
// (BetterTouchTool) needs the Accessibility permission. Column titles are
// matched in English.

import AppKit
import ApplicationServices

enum Mode {
    case modified, name

    var columnTitle: String { self == .modified ? "Date Modified" : "Name" }
    var sortDirection: String {
        self == .modified ? kAXDescendingSortDirectionValue : kAXAscendingSortDirectionValue
    }
}

func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func string(_ element: AXUIElement, _ name: String) -> String? { attr(element, name) as? String }

func children(_ element: AXUIElement) -> [AXUIElement] {
    (attr(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func role(_ element: AXUIElement) -> String { string(element, kAXRoleAttribute) ?? "" }

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("finder-sort: \(message)\n".utf8))
    exit(1)
}

/// Breadth-first search for list-view tables. Rows and cells are not descended
/// into, so large folders stay fast.
func findLists(in root: AXUIElement) -> [AXUIElement] {
    var queue = [root], found: [AXUIElement] = [], visited = 0
    while !queue.isEmpty && visited < 2000 {
        let element = queue.removeFirst()
        visited += 1
        switch role(element) {
        case kAXOutlineRole, kAXTableRole:
            found.append(element)
        case kAXRowRole, kAXCellRole, kAXMenuBarRole, kAXMenuRole:
            continue
        default:
            queue.append(contentsOf: children(element))
        }
    }
    return found
}

/// The header button titled `title`, plus the element that reports its sort
/// direction. Finder exposes the header through each column's AXHeader and the
/// direction on the column; Open/Save panels expose the buttons in a
/// "ListViewHeader" group with the direction on the button itself.
func column(titled title: String, in list: AXUIElement) -> (button: AXUIElement, sortState: AXUIElement)? {
    func matches(_ button: AXUIElement) -> Bool {
        string(button, kAXTitleAttribute) == title || string(button, kAXDescriptionAttribute) == title
    }
    for column in (attr(list, kAXColumnsAttribute) as? [AXUIElement]) ?? [] {
        if let header = attr(column, kAXHeaderAttribute), matches(header as! AXUIElement) {
            return (header as! AXUIElement, column)
        }
    }
    for group in children(list) where role(group) == kAXGroupRole {
        if let button = children(group).first(where: matches) { return (button, button) }
    }
    return nil
}

/// Press the header until it reports the wanted direction.
func sortList(_ list: AXUIElement, _ mode: Mode) -> Bool {
    guard let (button, sortState) = column(titled: mode.columnTitle, in: list) else { return false }
    for _ in 0..<3 {
        if string(sortState, kAXSortDirectionAttribute) == mode.sortDirection { return true }
        AXUIElementPerformAction(button, kAXPressAction as CFString)
        usleep(150_000)
    }
    return string(sortState, kAXSortDirectionAttribute) == mode.sortDirection
}

/// Finder icon, column and gallery views: View > Sort By > <title>.
func pressFinderSortMenu(_ app: AXUIElement, _ mode: Mode) -> Bool {
    func item(_ parent: AXUIElement, _ title: String) -> AXUIElement? {
        let menu = role(parent) == kAXMenuRole ? parent : children(parent).first { role($0) == kAXMenuRole }
        return menu.flatMap { children($0).first { string($0, kAXTitleAttribute) == title } }
    }
    guard let bar = attr(app, kAXMenuBarAttribute) else { return false }
    let barItems = children(bar as! AXUIElement)
    guard let view = barItems.first(where: { string($0, kAXTitleAttribute) == "View" }),
          let sortBy = item(view, "Sort By"),
          let target = item(sortBy, mode.columnTitle)
    else { return false }
    return AXUIElementPerformAction(target, kAXPressAction as CFString) == .success
}

/// Open/Save panels: a sheet on the focused window, or the focused window itself.
func panelRoot(_ window: AXUIElement) -> AXUIElement {
    children(window).first { role($0) == kAXSheetRole } ?? window
}

func isPanel(_ element: AXUIElement) -> Bool {
    role(element) == kAXSheetRole || string(element, kAXSubroleAttribute) == kAXDialogSubrole
        || string(element, kAXIdentifierAttribute)?.contains("open-panel") == true
        || string(element, kAXIdentifierAttribute)?.contains("save-panel") == true
}

/// Switch an Open/Save panel to list view (Command-2), the only view with columns.
/// Posted to the HID event tap because the panel can run in a separate process,
/// where events posted to the host app's pid do not arrive.
func switchPanelToListView() {
    let source = CGEventSource(stateID: .hidSystemState)
    for keyDown in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: 0x13, keyDown: keyDown)  // "2"
        event?.flags = .maskCommand
        event?.post(tap: .cghidEventTap)
    }
}

// MARK: - main

let arguments = CommandLine.arguments.dropFirst()
let mode: Mode
switch arguments.first {
case "modified": mode = .modified
case "name": mode = .name
case "debug": mode = .name  // prints sort state, changes nothing
default: fail("usage: finder-sort modified|name|debug")
}

guard AXIsProcessTrusted() else { fail("Accessibility permission missing for the launching app") }
guard let front = NSWorkspace.shared.frontmostApplication else { fail("no frontmost app") }

let app = AXUIElementCreateApplication(front.processIdentifier)
guard let focused = attr(app, kAXFocusedWindowAttribute) else { fail("no focused window") }
let window = focused as! AXUIElement
let root = panelRoot(window)
let inPanel = !CFEqual(root, window) || isPanel(window)
let isFinder = front.bundleIdentifier == "com.apple.finder"

if arguments.first == "debug" {
    print("app=\(front.bundleIdentifier ?? "?") inPanel=\(inPanel)")
    for list in findLists(in: root) {
        for title in ["Name", "Date Modified"] {
            if let (_, sortState) = column(titled: title, in: list) {
                print("\(title): \(string(sortState, kAXSortDirectionAttribute) ?? "-")")
            }
        }
    }
    exit(0)
}

if !isFinder && !inPanel { fail("front window is neither Finder nor an Open/Save panel") }

if let list = findLists(in: root).first(where: { column(titled: mode.columnTitle, in: $0) != nil }) {
    exit(sortList(list, mode) ? 0 : 1)
}

if isFinder && !inPanel {
    exit(pressFinderSortMenu(app, mode) ? 0 : 1)
}

if !arguments.contains("--after-switch") {
    // The panel applies Command-2 only after the launching BetterTouchTool action
    // returns, so hand the sort to a detached process and return now.
    switchPanelToListView()
    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = [arguments.first!, "--after-switch"]
    child.standardInput = FileHandle.nullDevice
    child.standardOutput = FileHandle.nullDevice
    child.standardError = FileHandle.nullDevice
    do { try child.run() } catch { fail("cannot start \(child.executableURL!.path): \(error)") }
    exit(0)
}
for _ in 0..<20 {
    let current = attr(app, kAXFocusedWindowAttribute).map { $0 as! AXUIElement } ?? window
    if let list = findLists(in: panelRoot(current)).first(where: { column(titled: mode.columnTitle, in: $0) != nil }) {
        exit(sortList(list, mode) ? 0 : 1)
    }
    usleep(150_000)
}
fail("no \"\(mode.columnTitle)\" column found")
