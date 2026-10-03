# Host integration contract

The host keeps `quick-actions` and `workspaces` registered internally and excludes both IDs from tabs, Command-number navigation, and applet settings. `NotchPresentation.hostTool` selects `.actions` or `.workspaces` while `selection` keeps the underlying applet. Tool content uses the existing applet's `makeView`, `contentHeight`, `handleArrow`, `hasPresentedOverlay`, and `dismissOverlay`.

`AppletContext.hostActions: [AppletAction]` supplies commands from the applet or workspace that opened Actions, followed by Settings. QuickActionsApplet should pass these to its embedded view and show them alongside saved actions and their management. It owns keyboard selection and Return for the combined list. The host does not present a second ActionList or popover. Commands are wrapped by the host to return to their source applet/tool before performing. These wrappers capture the presentation weakly because QuickActionsApplet retains them.

Persistent header buttons toggle Actions with Command-K and Workspaces with Command-Shift-W. Escape first releases a text editor's first responder without destroying view state. The next Escape dismisses a capture preview before any underlying applet overlay, then the active applet/tool overlay, then returns from a host tool, then closes the notch. Closing Actions returns to Workspaces or Settings when it was opened there. Actions opened from Settings includes General settings, Applet settings and Back to the underlying applet. Command-number and Control-Tab remain available while editing and return to applets. `context.restoreFocus()` clears the text responder and restores host focus; views may explicitly restore their own list focus after dismissal.

Service views keep unfinished editor data in applet-owned draft state when closing editors or changing applets. The host cannot preserve local view state after `dismissOverlay` or `deactivate` removes an editor. Keep editors within the content area below the header so tabs remain clickable.

`NotchPanelController(presentation:)` accepts an isolated presentation for keyboard verification; omitting it keeps normal app behavior.

## SwiftUI focus recovery

Setting NSHostingView as first responder releases native text editing but does not focus a SwiftUI view. `restoreFocus()` now advances `NotchPresentation.focusGeneration`, supplied through the `appletFocusGeneration` environment value. A visible focusable navigation view registers `.onAppletFocusRestore { focus = .deck }`, or sets its Boolean focus binding to true. Register on the currently visible focus owner so a hidden list cannot steal editor focus. This callback must select a non-text navigation target. The existing initial focus task still chooses the first field when opening an editor.

Home, Calendar and the shared AppletPages navigation deck use the modifier. Timer, Audio, Notes, Codex pickers and service views attach it to their visible navigation focus owners. A text-only editor that promises Return to resume editing needs a separate focusable navigation root; returning first responder to NSHostingView alone is insufficient.
