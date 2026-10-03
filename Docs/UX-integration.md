# Host integration contract

The host keeps `quick-actions` and `workspaces` registered internally and excludes both IDs from tabs, Command-number navigation, and applet settings. `NotchPresentation.hostTool` selects `.actions` or `.workspaces` while `selection` keeps the underlying applet. Tool content uses the existing applet's `makeView`, `contentHeight`, `handleArrow`, `hasPresentedOverlay`, and `dismissOverlay`.

`AppletContext.hostActions: [AppletAction]` supplies commands from the applet or workspace that opened Actions, followed by Settings. QuickActionsApplet should pass these to its embedded view and show them alongside saved actions and their management. It owns keyboard selection and Return for the combined list. The host does not present a second ActionList or popover. Commands are wrapped by the host to return to their source applet/tool before performing. These wrappers capture the presentation weakly because QuickActionsApplet retains them.

Persistent header buttons toggle Actions with Command-K and Workspaces with Command-Shift-W. Escape first releases a text editor's first responder without destroying view state. The next Escape dismisses a capture preview before any underlying applet overlay, then the active applet/tool overlay, then returns from a host tool, then closes the notch. Closing Actions returns to Workspaces or Settings when it was opened there. Actions opened from Settings includes General settings, Applet settings and Back to the underlying applet. Command-number and Control-Tab remain available while editing and return to applets. `context.restoreFocus()` clears the text responder and restores host focus; views may explicitly restore their own list focus after dismissal.

Service views keep unfinished editor data in applet-owned draft state when closing editors or changing applets. The host cannot preserve local view state after `dismissOverlay` or `deactivate` removes an editor. Keep editors within the content area below the header so tabs remain clickable.

`NotchPanelController(presentation:)` accepts an isolated presentation for keyboard verification; omitting it keeps normal app behavior.
