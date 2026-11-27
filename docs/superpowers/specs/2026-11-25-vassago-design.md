# Vassago — Clipboard History for macOS: Design Spec

**Date:** 2026-11-25 **Status:** Implemented 2026-11-26 **Author:** quyennv + Claude

## 1. Summary

Vassago is a personal menu bar tool for macOS that remembers what you copy. You copy several things in one place, then paste each of them somewhere else without going back for the next one. A hotkey opens the history as a list at the mouse pointer, and picking an item pastes it into the app you are in.

The case it is built for: a page lists order codes, and each one has to be opened in its own browser tab. Without a history that is copy, switch, paste, switch back, once per code. With Vassago it is all the copies first, then one hotkey and one digit per tab.

The idea comes from Ditto on Windows. The app is named after the third spirit of the Ars Goetia, "of the same nature as Agares", whose office is "to declare things past and to come, and to discover all things hid or lost".

Vassago is a separate app from Agares and changes nothing in it. It copies Agares's app shell (menu bar item, panel, update check, build and release scripts) and adds the clipboard work.

**Priorities:** never takes the cursor away from the app being pasted into, never records what a password manager marks as secret, small enough to read in one sitting.

## 2. Decisions & alternatives considered

| Decision | Chosen | Rejected alternatives |
| --- | --- | --- |
| Where it lives | **A new app in its own repository.** Nothing has to be shared with Agares at run time, and a slow clipboard read or a clipboard bug can never stall or crash Vietnamese typing. Agares stays a typing tool that never writes what you copy to disk. | Inside Agares, as a tab in its panel and a second hotkey on its key hook: about a third of the lines, one icon, but clipboard reads and disk writes would share a process with the key hook, where nothing may wait (Agares spec, 5.1). macOS's own clipboard history in Spotlight (Command+Space, then Command+4), which is switched on on this Mac with a 30-minute limit: no code, but no hotkey-then-digit pick and at most seven days of history. |
| Paste flow | **Pick from a list**, as in Ditto: hotkey, then a digit, or arrows and Enter. | A second hotkey that pastes the copied items one after another in the order copied: fastest for the order-code case, but a second feature with its own state. |
| What is kept | **Text with its formatting, images, and files.** | Plain text only: smallest, but no screenshots and no copied files. |
| Persistence | **Saved to disk**, so the history survives a quit or a restart. | Memory only: nothing copied ever reaches the disk, but the history is gone after a restart. |
| Finding an older item | **Scroll, or press `/` and type** (the search was added on 2026-11-27). Digits pick the nine newest until `/` starts a search. From then on they are typed like any other character, and Command with a digit picks. | Type to filter from the first key, as in Ditto: digits would then belong to the search, and hotkey-then-digit would be gone. A bare digit that always picks, with Option held to type one: one rule, but a chord for every digit of an order code. A text field in the list: it would take the keyboard focus from the app in front. |
| The pop-up list | **A native macOS menu** opened at the mouse pointer. macOS supplies the arrow keys, Enter, Esc, scrolling, screen edges, full-screen apps and several displays, and a menu does not take focus from the app in front. | A floating window in the panel's style, driven by a key hook: full control of the look, but all of the above written by hand. A window that takes focus, as Spotlight does: some apps lose their cursor or close a pop-over when focus leaves, so the paste can land in the wrong place. |
| Hotkey mechanism | **The system hotkey API** (`RegisterEventHotKey`). It needs no permission and no key hook. | An event tap, as Agares uses: needs Accessibility just to see the hotkey, and puts Vassago in the path of every keystroke. |
| Default hotkey | **Control+Command+V**, recordable in the panel: pinky, thumb and index finger of one hand. | Control+Option+V, the first default: an awkward stretch for one hand. Control+` (Ditto's default): VS Code's terminal toggle. Command+Shift+V: paste and match style in many apps. |
| Watching the clipboard | **Ask for the clipboard's change counter every 0.3 seconds** on a background queue, and read the contents only when it has moved. macOS has no notification for a clipboard change. | A slower poll, such as Agares's 2-second tick: two copies made inside one interval would record only the second. |
| Clearing the macOS clipboard | **Off by default. When set, the clipboard is emptied once it has held the same thing for 1, 5, 10 or 30 minutes, or 1 hour** (added 2026-11-27). The 0.3-second tick that already reads the change counter asks the rule, and the clip stays in the history. | A timer of its own: a second source of wake-ups for one comparison. Counting by uptime: the hours a Mac sleeps would not count, and a copy could wait on the clipboard overnight. |
| After a paste | **The list keeps its order, and the picked item stays on the clipboard.** Working down a run of items, each one stays at the number it had. | Moving the pasted item to the top, as Ditto does by default: every paste would renumber the rest. Putting the earlier clipboard back afterwards: needs a guessed delay for the target app to finish pasting. |
| Secrets | **Skip anything the copying app marks as concealed or transient** (the nspasteboard.org markers, which KeePassXC and 1Password set). | Recognising password managers by name: every one is a new case. |
| Signing | **The existing "Agares Dev" certificate.** It is already in the login keychain, and the permissions are tied to the signer, so they survive rebuilds. | A new "Vassago Dev" certificate: a second keychain item and a second pair of release secrets for no gain. Ad hoc signing: the Accessibility grant would be lost on every build. |
| Shared code | **Copied from Agares** and cut down, about 950 lines. | A Swift package shared by both apps: a third repository and a version to manage, for code that is small and rarely changes. |

## 3. What is recorded

### 3.1 Watching

A timer on a background queue reads `NSPasteboard.general.changeCount` every 0.3 seconds. When the number has not moved, nothing else happens but the check of section 3.6. When it has moved, Vassago reads the clipboard if the history is switched on and clipboard access is allowed (section 8), and otherwise only remembers the new number.

A copying app clears the clipboard first, which moves the counter, and writes its data afterwards without moving the counter again. Measured on 2026-11-26 over thirteen scripted copies, a reader that looked the moment the counter moved found the clipboard empty every time, and in one of them it was still empty 50 ms later. So while the clipboard is empty the change does not count as seen, and Vassago looks again on the next tick. The first build counted it as seen at once, and a copy whose data arrived after that look was never recorded.

What is already on the clipboard when Vassago starts is not recorded.

### 3.2 What is read

For every item on the clipboard, the data of these types, when the item has them:

| Type | Kept as |
| --- | --- |
| Plain text (`public.utf8-plain-text`) | As is |
| Rich text (`public.rtf`), HTML (`public.html`) | As is, and only alongside plain text |
| PNG (`public.png`) | As is |
| TIFF (`public.tiff`) | Converted to PNG. Dropped when the item also has a PNG. |
| File URL (`public.file-url`) | The reference only, never the file's contents |

An item that is a file keeps only its file URL and its plain text, which is the file's name. Other types are not read. Reading every type would make the copying app render formats nobody will paste, which for a large spreadsheet selection can take seconds.

### 3.3 What is skipped

A copy is not recorded when:

- the clipboard carries `org.nspasteboard.ConcealedType`, `org.nspasteboard.TransientType` or `org.nspasteboard.AutoGeneratedType`;
- it carries `com.quyennguyenvu.vassago.own`, the marker Vassago adds to what it writes itself (section 5.2);
- it carries `com.apple.is-remote-clipboard`, which means it arrived from another device through Universal Clipboard, and reading it would make macOS fetch from that device;
- nothing of section 3.2 is on it, or its only content is text that is empty or all whitespace;
- what would be kept of it, after section 3.2, adds up to more than 20 MB.

### 3.4 Kind and title

Each recorded copy is a clip with a kind and a one-line title for the list.

| Kind | When | Title |
| --- | --- | --- |
| Files | Any item has a file URL | The first file's name, then "and 2 more" when there are others |
| Text | Otherwise, any item has plain text | The first line that is not empty, with each run of whitespace turned into one space, at most 60 characters: a longer line shows its first 59 and "…" |
| Image | Otherwise | "Image 1200 × 800", in pixels |

Text decides before an image does, because Word and Excel put a picture of the selection on the clipboard beside its text. Such a clip is listed as text and still pastes with its picture.

An image clip and a files clip also get a thumbnail, a PNG made when the clip is recorded: the image scaled to at most 128 pixels on its longer side, or the Finder icon of the first file at 64 pixels. The list can then be drawn without loading any clip's data.

### 3.5 Duplicates and limits

Two clips are the same when the SHA-256 digest of their data is the same. Copying something already in the history removes the older clip and puts the new one at the top.

The history holds at most 100 clips and at most 200 MB of data. When either limit is passed, the oldest clips are dropped until both hold. Those are the defaults: both limits can be changed in the panel (section 7.1).

### 3.6 Clearing the macOS clipboard

Added 2026-11-27, and off by default. In the panel the user picks Never, 1, 5, 10 or 30 minutes, or 1 hour (section 7.1). Once the clipboard has held the same thing for that long, Vassago empties it with `clearContents()`. The clip stays in the history, so it can still be picked from the list.

- **On the same tick.** The 0.3-second watch of section 3.1 already reads the change counter, so the rule is asked there and adds no timer. Measured on 2026-11-27 against the running app: a tick costs about 0.11 ms of CPU, which is 0.04% of one core, and emptying the clipboard takes about 0.15 ms, or 1.5 ms with 20 MB on it.
- **From the last change.** The wait starts when the counter moves: a copy in any app, or a pick from Vassago's list. What is on the clipboard at launch counts from the launch. Switching the setting on does not start a new wait, so a clipboard already older than the time chosen is emptied on the next tick.
- **By the wall clock.** The hours the Mac sleeps count, so a copy does not outlast a night.
- **Once.** Emptying moves the counter. Vassago takes the new number as seen, so the empty clipboard is not looked at as a copy, and it is not emptied again until something is copied.
- **Whatever the other settings.** It runs with the history switched off and without clipboard access: emptying reads nothing.

The rule is a value type with no OS imports:

```swift
public struct Expiry {
    // True when the clipboard is to be emptied now. `after` is in the unit of `time`; nil never empties it.
    public mutating func check(count: Int, at time: Double, after: Double?) -> Bool
    // The clipboard was emptied, which moved its counter to `count`.
    public mutating func emptied(count: Int)
}
```

## 4. Storage

Everything is under `~/Library/Application Support/Vassago/`, a directory only the user's account can read (mode 0700). Nothing is encrypted.

```text
Vassago/
  index.json          the clips, newest first: id, kind, title, bytes, digest
  clips/<id>.plist    one clip's data: for each clipboard item, a dictionary of type to data
  clips/<id>.png      the thumbnail, for image and files clips
```

- The list is drawn from `index.json` and the thumbnails. A clip's data is loaded only when it is pasted or copied back.
- Adding a clip writes its data first and the index after, each atomically. Dropping a clip writes the index first and deletes its files after.
- At launch, an index entry whose data file is missing is dropped, and a file in `clips/` that no entry names is deleted. An index that cannot be read starts the history empty, and the files left behind are then deleted by the same rule.
- All reads and writes happen on the clipboard queue of section 3.1, never on the main thread.

The pure part of this is a value type with no OS imports:

```swift
public struct Clip: Codable, Equatable {
    public enum Kind: String, Codable { case text, image, files }
    public let id: String       // names the files in clips/
    public let kind: Kind
    public let title: String
    public let bytes: Int       // size of the data
    public let digest: String   // equal digests mean equal content
}

public struct History {
    public init(clips: [Clip] = [], maxCount: Int = 100, maxBytes: Int = 200_000_000)
    public private(set) var clips: [Clip]              // newest first
    public mutating func add(_ clip: Clip) -> [Clip]   // the clips this pushed out: a duplicate, or the oldest
    public mutating func limit(maxCount: Int, maxBytes: Int) -> [Clip]   // new limits: the clips now over them
    public mutating func remove(id: String) -> Clip?
    public mutating func removeAll() -> [Clip]
}

public func title(forText text: String) -> String      // section 3.4

// The launch rule above: the clips whose data file is among `files`, and the names to delete.
public func reconcile(index: [Clip], files: Set<String>) -> (clips: [Clip], strays: [String])
```

Whatever `add`, `limit`, `remove` and `removeAll` return is what the store deletes from disk. `reconcile` is pure so that the rule that deletes files at launch has a unit test.

## 5. The list and pasting

### 5.1 The list

The hotkey opens a native menu at the mouse pointer, with every clip, newest first.

```text
┌──────────────────────────────────────┐
│ ⌕ Type / to search                   │
│ ──────────────────────────────────── │
│ ORD-10005                          1 │
│ ORD-10004                          2 │
│ ▣ Image 1200 × 800                 3 │
│ https://example.com/orders/10003   4 │
│ ▤ invoice.pdf and 2 more           5 │
│ …                                    │
└──────────────────────────────────────┘
```

- A row shows the title. An image clip and a files clip have their thumbnail in front (section 3.4).
- The title is cut with … to fit 240 points, about 39 characters, less the width of a thumbnail (added 2026-11-27). A menu is as wide as its widest row: with whole 60-character titles the list measured 562 points, close to a third of a 1920-point screen, and it is now about 300. The menu bar item's list is cut the same way. A search still looks in the whole title. Each cut title is kept by clip id until its clip leaves the history, so only the first opening after launch measures them. With every title 60 characters long, that opening took 19 ms for 100 clips and 89 ms for 500, and the later ones 6 ms and 30 ms, the same as with uncut titles (measured off screen, 2026-11-27).
- The nine newest rows have the digits 1 to 9 as key equivalents, with no modifier. Arrow keys and Enter, or a click, pick any row. Esc closes the list.
- While the list is open and Accessibility is granted, an event tap takes the digit keys and Return before the menu does, closes the menu without its animation, and picks the row. Picked through the menu itself, a row arrives only after the closing animation, about 350 ms later (measured on macOS 27.2.1, 2026-11-26). The tap is removed when the list closes. A click, and the menu bar item's list, still go through the menu.
- **Search** (added 2026-11-27). The first row reads "Type / to search". It is at the top because that is the one edge of a menu that stays put: with a long history the last row is off the screen, and it would move with every row a search hides. The row is not a text field, which would take the keyboard focus from the app in front. The event tap reads the keys instead and the row shows what was typed, as "Search: ord".
  - `/` starts a search. Until then every key does what it did before, so hotkey-then-digit is unchanged.
  - During a search every character is typed, digits and `/` too, and Delete takes one back. The list shows only the clips whose title contains the text, compared as in the panel (section 7.1), and the first nine shown carry ⌘1 to ⌘9.
  - Return and Enter pick the highlighted row. A menu's highlight cannot be set from code, so with no row highlighted they pick the top match. Command with a digit picks that row. The arrow keys and Esc stay with the menu.
  - When no clip matches, the row says so. The search ends when the list closes.
  - The row is left out when the tap is missing (no Accessibility), since nothing could be typed, and when the history is empty. The menu bar item's list has no search.
- With an empty history the list is one disabled row, "Nothing copied yet".
- Each missing permission adds a row above the clips, clipboard access first: "Clipboard access is off…", which opens the panel, and "Grant Accessibility to paste directly…", which opens the Settings pane.

### 5.2 Picking a clip

1. The clip's data is loaded from disk. If it cannot be read, the clip is dropped from the history, the system beep sounds, and nothing is pasted.
2. The data is written to the clipboard, every type it was recorded with, plus the marker `com.quyennguyenvu.vassago.own`. The watcher sees the marker and does not record the write, so the list keeps its order.
3. If Accessibility is granted, Vassago posts Command+V, a key press and a release, to the app in front. If it is not, nothing more happens: the clip is on the clipboard and the user presses Command+V.

The clip stays on the clipboard afterwards, so Command+V pastes it again.

A files clip is written back as the same file references. If a file has since been moved or deleted, what happens is up to the app pasted into; Finder pastes nothing.

### 5.3 Alongside Agares

Agares's key hook sees the Command+V that Vassago posts. It passes it through untouched: by default it leaves alone every key another app typed, and with that option off it still passes any key pressed with Command (Agares spec, 3.2). Digits typed into the open list are not letters, so Agares does not convert them.

## 6. The hotkey

A hotkey is a set of modifiers (Control, Option, Shift, Command) with one key. It is valid when Control, Option or Command is among the modifiers; Command+Tab is never a hotkey. The modifiers-alone shape that Agares has is left out, because the system hotkey API cannot register it.

- **Default:** Control+Command+V.
- **Registration:** `RegisterEventHotKey`, when the app starts and whenever the hotkey changes. If macOS refuses a new hotkey, the panel says the shortcut could not be registered and the previous one stays.
- **Recording:** Record… in the panel unregisters the current hotkey, so that pressing it again can be captured, and sends the panel window's key presses to the recorder. The next valid combination becomes the hotkey. Escape alone, or the panel losing focus, cancels and registers the previous hotkey again.
- **Storage:** `UserDefaults` keys `hotkeyModifiers` (bit set) and `hotkeyKeyCode`. A stored value that is not valid falls back to the default.

## 7. The panel and the menu bar

### 7.1 The panel

One fixed-size window, 420 points wide, in Agares's dark style with ember accents (control-panel spec, section 5).

```text
┌──────────────────────────────────────────┐
│                 Vassago                  │
│                                          │
│  ☑ Keep clipboard history [100] [200 MB] │
│                                          │
│  Clear the macOS clipboard       [Never] │
│                                          │
│  HOTKEY                                  │
│  (⌃ ⌘ V)                                 │
│  Press Control + Command + V to open the │
│  list.                                   │
│  [Record…]                               │
│                                          │
│  HISTORY  [Search          ] [Clear All] │
│  ┌────────────────────────────────────┐  │
│  │ ORD-10005                        × │  │
│  │ ORD-10004                        × │  │
│  │ ▣ Image 1200 × 800               × │  │
│  │ ▤ invoice.pdf and 2 more         × │  │
│  │ …                                  │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ☑ Launch at login  [Reset to Defaults…] │
│                                          │
│  ● Clipboard access allowed              │
│  ● Accessibility granted                 │
│  Vassago 0.1.0      [Check for Updates…] │
└──────────────────────────────────────────┘
```

- **Keep clipboard history:** on by default, saved as `keepsHistory`. While it is off nothing new is recorded. The clips already kept stay, and can still be pasted.
- **The two limits** (added 2026-11-27): two small pop-ups in the same row, so the panel is no taller. One sets the most clips kept (25, 50, 100, 200 or 500), the other the most data (50, 100, 200 or 500 MB, or 1 GB). They are saved as `maxClips` and `maxMegabytes`, and a saved value that is not one of the choices counts as the default. A new limit applies at once. When clips have to be deleted to fit it, an alert says how many and asks first, since they cannot be brought back; Cancel leaves the limit as it was.
- **Clear the macOS clipboard** (added 2026-11-27): a row of its own under the switch, with a small pop-up: Never, or after 1, 5, 10 or 30 minutes, or 1 hour. It is saved as `clearMinutes`, where 0 is Never, and applies at once. Section 3.6 has the rule.
- **Hotkey:** the current hotkey as keycaps, spelled out in words underneath, and Record… (section 6).
- **History:** every clip, newest first, in a list five rows high that scrolls. With eight rows the panel measured 819 points tall, too tall for a 900-point screen with the Dock showing; with six it was 751. The sixth row went on 2026-11-27 to make room for the clear setting's row, and the panel now comes to about 762: worked out from the rows as measured, not seen. The rows look as they do in the pop-up list. Clicking a row writes the clip back to the clipboard and highlights the row for a moment; it does not paste, because the panel is the app in front. The × on a row deletes that clip. Clear All deletes every clip after an alert asks to confirm, since it cannot be undone.
- **Search** (added 2026-11-27): a text field in the heading's row, so the panel is no taller. While it holds text, the list shows only the clips whose title contains it, compared as Finder compares names: case and accents do not count, and đ counts as d. Only the title is searched, not the rest of a clip's text, which is on disk and not loaded for the list (section 4). With no clip left the list says "No clip matches". The field is disabled while a hotkey is being recorded, so that a key the recorder ignores is not typed into it. Clear All still deletes every clip, not only the ones shown.
- **Launch at login:** `SMAppService.mainApp`, as in Agares.
- **Reset to Defaults…** (added 2026-11-27), in the Launch at login row. It puts back the hotkey (Control+Command+V), the limits (100 clips, 200 MB), the history switch (on), the clearing (Never) and Launch at login (off). An alert lists these and asks first. The alert also says how many of the oldest clips the default limits delete, or that none is. Permissions are not touched. If macOS refuses the standard hotkey, the current one stays, as after a refused recording.
- **Footer:** one line for each permission, with the buttons of section 8 while it is missing; the version and Check for Updates, as in Agares.

Each row is labelled for VoiceOver with its title and kind, and each × with "Delete" and the title.

The panel opens at launch only while Accessibility is missing, or the history is switched on and clipboard access is not allowed.

### 7.2 The menu bar item

The item shows the SF Symbol `doc.on.clipboard`, followed by a dot when a newer release is known. While the history is switched on but clipboard access is not allowed, it shows `⚠` instead.

Its menu, top to bottom:

- "Clipboard access is off…" and "Grant Accessibility to paste directly…" (each only while that permission is missing)
- Version 0.2.0 Available… (only when a newer release is known)
- The nine newest clips, as in the pop-up list. Picking one pastes it into the app in front.
- Open Vassago…
- Clear History… (with the same confirmation as Clear All)
- Check for Updates…
- Quit Vassago

The Dock icon, the main menu and the quitting rules are Agares's (control-panel spec, section 6): a Dock icon only while the panel is open, and only the menu bar item's Quit quits, apart from logout, restart and shutdown. The main menu has an Edit menu with Cut, Copy, Paste and Select All, which is what gives the panel's search field ⌘X, ⌘C, ⌘V and ⌘A.

### 7.3 Updates

The update check is Agares's (control-panel spec, section 7), against the repository `quyennguyenvu/vassago`: quiet once a day, and on demand with an alert. Nothing is downloaded or installed. Its key is `nextUpdateCheck`.

## 8. Permissions and failure handling

Vassago needs two permissions, for two different things.

| Permission | Needed for | Without it |
| --- | --- | --- |
| Clipboard access: Paste from Other Apps set to Always Allow | Recording | Nothing is recorded. Clips already kept can still be pasted. |
| Accessibility | Posting Command+V | Picking a clip only puts it on the clipboard. |

**Clipboard access.** From macOS 15.4, macOS asks the user before an app reads the clipboard on its own. `NSPasteboard.general.accessBehavior` gives the setting. On earlier versions there is no such setting and access counts as allowed.

| Setting | Behaviour |
| --- | --- |
| Always Allow | The watcher reads every change. |
| Default (the app has never asked) | At launch with the history switched on, or when the history is switched on, Vassago makes one read. macOS then shows its prompt and starts listing Vassago in System Settings. After that the setting is Ask. |
| Ask | The watcher never reads, because every read could raise a prompt. The panel shows Allow Clipboard Access…, which opens the Settings pane where the user picks Always Allow. |
| Always Deny | The same as Ask. |

The setting is read again on the 2-second tick that also watches Accessibility, so recording starts without a relaunch once it is allowed.

Observed on macOS 27.2.1 (section 11): a new build that has never asked already reports Always Allow, no prompt appears, and the Paste from Other Apps pane does not list Vassago. So on this macOS recording needs no permission step. The Default, Ask and Always Deny rows follow the SDK's documentation and could not be exercised.

**Accessibility.** As in Agares: macOS is asked to show its prompt once at launch, the panel shows Grant Accessibility… and Reset Permission while it is missing, and the 2-second tick notices when it is granted or withdrawn.

| Condition | Behaviour |
| --- | --- |
| A clip's data cannot be written to disk | The clip is not added. Nothing else changes. |
| A clip's data cannot be read when picked | The clip is dropped from the history and the system beep sounds (5.2). |
| The index cannot be read at launch | The history starts empty (section 4). |
| Two copies less than 0.3 seconds apart | Only the second is recorded. |
| The clipboard is cleared and left empty | Nothing is recorded. Vassago looks again on each tick until something is on it (3.1). |
| The hotkey cannot be registered | The panel says so, and the previous hotkey stays (section 6). |
| The front app pastes with something other than Command+V | The clip is on the clipboard, and the user pastes by hand. |

## 9. Code layout

```text
vassago/
  Package.swift
  Sources/VassagoEngine/     pure logic, no OS imports: History, Expiry, Hotkey, ListKeys, Version
  Sources/Vassago/           Clipboard, Store, GlobalHotkey, HistoryMenu, AppModel, StatusMenu, Panel, UpdateCheck, main
  Tests/VassagoEngineTests/
  Resources/                 Info.plist, icon.svg
  scripts/test.sh            runs the tests
  scripts/bundle.sh          release build → build/Vassago.app → codesign; install or dmg
  scripts/release.sh         test, bump the version, tag, push
  .github/                   release workflow and the header of the release notes
```

One process, a menu bar app (`LSUIElement`), with no telemetry. Bundle id `com.quyennguyenvu.vassago`, minimum macOS 13, Swift with no dependencies, built with SwiftPM and Command Line Tools as Agares is.

| File | From | What it holds |
| --- | --- | --- |
| `Sources/VassagoEngine/History.swift` | New | `Clip`, `History`, `title(forText:)`, `reconcile(index:files:)` (section 4) |
| `Sources/VassagoEngine/Expiry.swift` | New | When the macOS clipboard is emptied (section 3.6) |
| `Sources/VassagoEngine/Hotkey.swift` | Agares, cut down | `Modifiers`, `Hotkey` with a key always present, `HotkeyRecorder`, the key labels. No matcher, no modifiers-alone shape, no presets. |
| `Sources/VassagoEngine/ListKeys.swift` | New | What a key pressed in the open list does: pick a row, start a search, type into it, or stay with the menu (section 5.1) |
| `Sources/VassagoEngine/Version.swift` | Agares, unchanged | Three-number versions and their ordering |
| `Sources/Vassago/Clipboard.swift` | New | The 0.3-second watch, the read with its skip rules, the write-back, emptying the clipboard, Command+V |
| `Sources/Vassago/Store.swift` | New | The index, data and thumbnail files, and the digest |
| `Sources/Vassago/GlobalHotkey.swift` | New | Registers the hotkey with macOS and calls back when it is pressed |
| `Sources/Vassago/HistoryMenu.swift` | New | Builds the rows for the pop-up list and the menu bar item |
| `Sources/Vassago/AppModel.swift` | Agares's shape | Settings, the permission tick, the update schedule, and the history's actions |
| `Sources/Vassago/StatusMenu.swift` | Agares, adapted | The menu bar item, the Dock and quit rules |
| `Sources/Vassago/Panel.swift` | Agares's window, palette, keycaps and footer | The body of section 7.1 |
| `Sources/Vassago/UpdateCheck.swift` | Agares, repository name changed | The GitHub request and its alert |
| `main.swift`, `Info.plist`, `scripts/`, `.github/` | Agares, renamed | |

Not copied: the Telex engine, `KeyTap`, `Typist`, `scripts/make-cert.sh` (the certificate already exists; Agares's script makes it on another Mac) and `scripts/sync-plans.py`.

- **Signing:** `codesign --sign "Agares Dev" --identifier com.quyennguyenvu.vassago`.
- **Icon:** Agares's ember ring around three stacked bars, a list, in place of the letter â.
- **Releases:** the same workflow as Agares (Agares spec, 7.1). The repository `quyennguyenvu/vassago` needs the secrets `SIGNING_P12_BASE64` and `SIGNING_P12_PASSWORD` before the first release.

## 10. Testing

**Unit tests**, with Swift Testing, run by `bash scripts/test.sh`:

- `History`: a new clip goes to the top; a clip with a known digest replaces the older one and returns it; passing 100 clips returns the oldest; passing 200 MB returns the oldest clips until the total fits; `remove` and `removeAll` return what the store must delete; new limits return the oldest clips over them, keep the newest whatever its size, and hold for the clips added after.
- `title(forText:)`: leading blank lines, runs of whitespace, a line of exactly 60 characters, a longer line.
- `shortened(_:toFit:)`: a title that fits is left alone, a wider one keeps its longest beginning that fits, and when nothing fits only the … is left.
- `reconcile(index:files:)`: a clip whose data file is missing is dropped, and files no kept clip names are listed for deletion.
- `Hotkey` validity, keycaps and name, the recorder, and `Version`: Agares's tests, less the cases for the parts left out.
- `Expiry`: the clipboard is emptied once it has held the same thing long enough; a new copy starts the wait again; nothing is emptied while the setting is Never, and switching it on counts from the copy; an emptied clipboard is left alone until the next copy.
- `ListKeys`: a bare digit picks until a search starts and is typed after; Command with a digit picks only during a search; `/` starts a search and is text inside one; Delete, Return and Enter; arrows, Esc, Tab and other modifiers stay with the menu.

**By hand**, since the rest needs the real clipboard, the permissions and other apps:

| Where | Check |
| --- | --- |
| A browser | Copy five order codes from one page. In five new tabs, the hotkey then 5, 4, 3, 2, 1 pastes them in the order copied, and the address bar keeps its cursor each time. |
| VS Code, Terminal | The hotkey and a pick put the text at the cursor |
| TextEdit | Bold text copied from a rich text document pastes bold |
| A screenshot to the clipboard | It appears with a thumbnail and pastes into Preview's New from Clipboard |
| Finder | Two copied files show as "a.pdf and 1 more", and paste into another folder |
| KeePassXC | Copying a password adds nothing to the history |
| The same text copied twice | One row, at the top |
| A slow writer | A script that clears the clipboard and writes half a second later is still recorded (3.1) |
| Quit and reopen | The history is still there, thumbnails included |
| Each clipboard access setting | Section 8's behaviour, and recording starts within two seconds of Always Allow |
| Accessibility withdrawn | A pick only copies |
| A full-screen app, a second display | The list opens there, at the pointer |
| Agares running with Vietnamese on | Digits pick, and the paste arrives unconverted |
| The panel's search | Typing `ord` leaves only the rows with it in their title, `don hang` finds `Đơn hàng`, and ⌘V pastes into the field |
| The list's search | The hotkey then a digit pastes as before. The hotkey, `/`, then `ord-10` narrows the rows while the menu stays open, and the typed text is readable in the first row. Return pastes the top match, ⌘2 the second, and Delete widens the list again. The address bar keeps its cursor throughout. |
| The clear setting | With After 1 minute, a copied word is gone from ⌘V a minute later and is still in the list. A second copy inside the minute starts the wait again. With Never nothing is cleared. |
| Reset to Defaults | With another hotkey recorded, 25 clips, After 5 minutes and Launch at login on, Reset puts all four back after its alert, and names the clips it deletes when there are more than 100. Cancel changes nothing. |
| The list's search with Agares on | Letters typed after `/` reach the search, with Vietnamese switched on and off |

## 11. To settle before building

Two behaviours of macOS that the design rests on were tried on 2026-11-26, on macOS 27.2.1, before anything was built on them. A small test bench in the menu bar item's menu did the reading and the pasting.

**Reading the clipboard in the background.** It works, and on this macOS it needs no permission.

| # | Result |
| --- | --- |
| A1 | At first launch, before Vassago had read anything, the setting was already `always allow`. |
| A2 | A read made with no user action raised no prompt. |
| A3, A6 | Not reported from the test bench. Confirmed with the real watcher instead: copies made from the shell were recorded within 0.6 seconds, with no prompt. |
| A4 | The link `x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard` opens the pane, which is called Paste from Other Apps. It was empty, under the note "Applications that have requested access to pasteboard contents from other applications at any time will appear here." |
| A5 | Not possible: Vassago is not listed in the pane, so there is nothing to set. |
| A7 | Recording went on working after two more builds, signed with the same certificate, were installed. |

The SDK header says the default is to ask. Why this build is allowed without asking is not known.

**A menu opened by an app that is not in front.** It works as designed.

| # | Result |
| --- | --- |
| B1 | Control+Option+V opened the menu at the mouse pointer, with the digits shown as key equivalents. |
| B2 to B4 | In a browser's address bar, a digit pasted its row, the arrow keys and Return pasted theirs, and Esc left the cursor in the address bar. No delay was needed before Command+V. |
| B5 | The same in a VS Code editor and in Terminal. |
| B6 | The same over a full-screen window. |

## 12. Out of scope

- Searching a clip's text beyond its title, and a search in the menu bar item's list
- A paste-next hotkey that works through the clips in the order copied
- Paste as plain text
- Pinned or favourite clips, and editing a clip
- Sync between Macs
- Encrypting the stored clips
- Excluding particular apps from recording
- Opening the list at the text cursor instead of the mouse pointer
- Hotkeys made of modifiers alone
- A light theme
- Downloading or installing updates

## 13. Risks

1. **Three of the four clipboard access settings have never run.** macOS 27.2.1 gives a new build Always Allow from the start (section 11), so the code for Default, Ask and Always Deny follows the SDK header and is untried. If a later macOS starts asking, that code is what keeps a prompt from appearing on every copy.
2. **Stored clips are not encrypted.** A password copied from an app that does not mark it as concealed is saved to disk as it is, until it is deleted, cleared, or pushed out by newer clips. Anything running under the user's account can read the directory, as it can read the clipboard itself.
3. **A copy can be missed** when another follows within 0.3 seconds, or when the copying app's data comes to more than 20 MB.
4. **Files are references.** A files clip pastes nothing useful once its files have moved.
5. **Reading can be slow.** An app that prepares its data only when asked does that work when Vassago reads it. This happens on the background queue, so only recording waits.
6. **Images lose their original format.** A TIFF is kept as a PNG, and formats other than PNG and TIFF are not kept at all.
7. **Spotlight's clipboard history is on on this Mac** and keeps recording independently. The two do not interfere.
8. **The update check and releases find nothing** until `quyennguyenvu/vassago` is public, has the signing secrets, and has a release tagged `v<version>`.
9. **Some checks of section 10 were not made by hand.** Checked on 2026-11-26 against the installed app: a pick that pastes in a browser, the panel's controls, five order codes into five tabs, bold text, a screenshot, two Finder files, a KeePassXC password, and picking with Agares on. Not tried: an Office copy, the limit of 100 against the running app (the rule is unit-tested), withdrawing Accessibility, a second display, Universal Clipboard, and anything that needs Vassago listed under Paste from Other Apps. VS Code, Terminal and a full-screen window were tried with the test bench of section 11, not with the finished app.
10. **The two searches have not been tried in the running app.** The panel's field and the list's search (both added 2026-11-27) were built, and the key rules and the comparison are tested, but nobody has yet watched them work. Open for the list: that rows hide and renumber while the menu is open, that the typed text in the first row is not dimmed, and what reaches the search when Agares is converting.
11. **The clear setting, Reset to Defaults and the panel's new rows have not been tried in the running app** (all added 2026-11-27). The rule for when the clipboard is emptied is unit-tested, and copies of the two new rows were rendered and measured. Nobody has yet watched the clipboard being emptied, pressed Reset, or seen the whole panel at its new height. Untried too: emptying under a clipboard access setting other than Always Allow.
