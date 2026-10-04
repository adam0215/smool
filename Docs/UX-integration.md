# Host integration

The host owns navigation, focus and feature handoffs. Applets own their services, drafts and visible work. This boundary keeps keyboard behavior consistent while allowing each applet to handle its own content.

## Destinations and applet lifetime

`NotchPresentation.Destination` represents the displayed host destination: applet, Workspaces, Settings, Actions with its source, or a captured-selection preview. `selection` retains the underlying applet ID. `hostTool`, `showsActions`, `showsSettings` and `capturedSelection` derive from the destination.

Actions and Workspaces remain registered internally, but do not appear in applet tabs, Command-number navigation or applet settings. Their content uses the same `Applet` contract as other features. The header opens Actions with Command-K and Workspaces with Command-Shift-W. Closing Actions restores the applet, Workspaces or Settings from which it opened.

`deactivate()` handles leaving an applet, and `dismissOverlay()` removes transient UI while retaining drafts. `handleBack()` consumes one applet-specific Escape step and reports whether it handled the event. The default implementation dismisses an overlay. Home also uses it to leave event details and then the calendar.

## Commands and capture

`connectAppletCommands()` installs `AppletCommandContext` when `NotchPresentation` creates its applets. Notes asks its `composeInCodex` provider whether composing is available; Actions reads the `hostActions` provider for current commands. Providers read current host state, including enabled applets, without waiting for `makeView` to run.

`AppletAction` combines a stable ID, title, symbol, operation and optional `AppletShortcut`. A shortcut contains its key and modifiers and derives the visible label and actual keyboard binding. Its palette binding omits plain Return and Command-arrows, which already belong to selection and navigation. The host wraps contextual operations to restore their source destination before executing them. These wrappers capture the host weakly.

`AppletContext` carries view-facing layout, focus restoration and navigation. Cross-feature handoffs live in `AppletIntegration.swift`. `CapturedSelection` owns a capture preview and its note-save state. Selected text and notes enter Codex through `prepareCodexDraft`, which opens the recipient picker without choosing a recipient or submitting a message. Saving captured text as a note waits for `NotesStore.flush()` before leaving the preview. A failed write keeps the capture and reuses its note ID on retry.

## Escape and focus

`NotchPanelController.goBackOrClose()` handles Escape in this order:

1. Release a native text editor, preserving its draft.
2. Dismiss contextual help or a save-error notice.
3. Dismiss a capture preview or Settings.
4. Let the displayed applet consume one `handleBack()` step.
5. Leave the host tool and restore its source.
6. Close the notch.

Command-number and Control-Tab navigation remain available while editing. Ordinary text-editing arrows stay with the editor; applets may explicitly handle editing arrows where their input requires it.

Setting `NSHostingView` as first responder releases native text editing but does not focus a SwiftUI navigation view. `restoreFocus()` also advances `focusGeneration`, supplied through the `appletFocusGeneration` environment value. The visible navigation owner responds through `onAppletFocusRestore`, selecting a non-text focus target. Hidden lists must not steal focus from an editor. A view that offers Return to resume editing needs that separate navigation target.

Editors stay below the host header so applet tabs remain clickable. Drafts live in applet-owned state because transient SwiftUI views can disappear during navigation.

Codex Search uses a task keyed by `searchFocusRequest`. Each Command-F request clears focus, yields until the search field is mounted, then focuses it if the request is still current. This also restores focus after Escape released the editor while the search view remained visible. Opening Actions from a composer preserves the selected recipient and connection context; explicitly leaving the composer has its own draft-preserving back step.

## Saving and termination

`NotesStore.requestSave()` starts asynchronous disk work and returns without waiting. `flush()` awaits the current text and returns success or failure; failed writes retain dirty text for retry. Leaving a Notes editor requests a save, while capture handoffs and termination await `flush()`.

`NotchPresentation.finishPendingChanges()` drains Notes, Files, Actions and Workspaces together, then checks for edits or operations added while another store was saving. It repeats until no work remains and deactivates applets only after every pass succeeds. On failure the editor remains available and the host reports which feature needs attention. Notes can retry its dirty text directly. Actions and Workspaces require returning to the editor or confirmation and explicitly repeating the failed operation.

Actions and Workspaces report pending-operation outcomes and expose `failedWriteGeneration`. The host captures both generations at the start of a quit attempt and compares them after each pass. A failure that finishes and leaves the pending queue while another store is still saving therefore still aborts that attempt. A later pass cannot hide it. The stores do not retain failed mutations for replay, and a failure completed before a later explicit Quit command does not block that new attempt. The app delegate uses macOS's deferred termination reply to keep the interface responsive while stores finish.

## Home and verification

`HomePalette` supplies the established clock, Spotify and Codex colors. `HomeCard` chooses the card arrangement, color and glow position. `BottomGlow` animates resolved color and position while clipping light below the camera band. Home keeps its glass cards; ordinary applet content remains on the background layer. Expanded content is removed when the notch closes, and Reduce Motion disables the corresponding animations.

Run `Tests/run-checks.sh AppletCommand HostEscape HomeCalendar HomeLighting HostRendering NotchHomeRendering` for focused coverage. `NotchPanelController(presentation:)` accepts an isolated presentation so keyboard checks can exercise the actual host. Rendered images and live keyboard checks cover different parts of the experience; both matter after UI changes.
