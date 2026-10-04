# Actions and Workspaces

Actions combines commands for the current view with saved launches. Workspaces groups resources to open together. Both are persistent host tools and keep their editors inside smool.

## Contextual commands

`QuickActionsApplet.entries` reads `commandContext.hostActions()` and adds saved actions and management commands. `AppletCommandContext` is installed at host composition, so command availability does not depend on rendering the Actions view. The host restores the source destination before running a contextual command.

`AppletShortcut` supplies each command's label and binding. Saved-action management uses Command-Shift-N, Command-Shift-E and Command-Shift-Delete to avoid collisions with source commands. Plain Return runs the highlighted row; Command-arrows remain host navigation. Up/Down changes the highlighted entry through `handleArrow`. Keyboard bindings mount in the list background independently of the lazy rows, so commands still work when their rows are offscreen. Contextual entry IDs have a `context:` prefix to keep them separate from saved actions and management commands.

## Draft ownership

Actions retains a new-action draft and one draft per saved action. Workspaces retains a new-workspace draft, drafts for existing workspaces, and resource drafts within each workspace. Leaving an editor dismisses a presentation level without deleting the draft. Opening Actions from Workspaces preserves the workspace editor and its command context.

A resource edit updates its workspace draft. Command-Return on the workspace editor saves the workspace. Unfinished resource drafts survive leaving and reopening that workspace. The host releases native text editing on the first Escape; subsequent Escape presses go through `handleBack()` and `dismissOverlay()`. See [host integration](UX-integration.md) for focus restoration.

## Persistence

`QuickActionStore.save`, `delete` and `move`, and `WorkspaceStore.save` and `delete`, are asynchronous operations returning `Bool`. They serialize mutations, write atomically and publish the updated collection only after a successful write. A failed operation leaves the committed collection unchanged. Editors and deletion confirmations retain their state so the user can retry explicitly.

`finishPendingChanges()` waits for current operations and reports their outcomes. It does not retry a failed save, deletion or move, or make an old failure block future quit attempts. The stores expose `hasPendingChanges` and a monotonically increasing `failedWriteGeneration`. The host repeats its drain while work remains and compares failure generations across the entire quit attempt. This catches failures even after their operation has left the pending queue. Applets remain active until draining succeeds, so failures leave the editor available.

## Keyboard interaction

Workspaces opens as a vertical list. Return opens the included resources together, Command-E edits, and Command-N creates or resumes a new workspace. Inside the workspace editor, arrows select resources, Space includes or excludes them, Return edits a resource, Command-N adds one, and Command-Return saves.

Resource entry accepts an installed app name, local path, website or Codex thread ID/link. Names are optional and inferred. Bare websites normalize to HTTPS. App and folder entry stays inside the notch.

The resource editor shows Command-J to switch between shortcut and inferred input, Option-Up/Down to choose an Apple Shortcut, Command-R to reload shortcuts, and Command-Return to save. Return in the text field also saves. These commands do not require macOS Full Keyboard Access to make ordinary buttons reachable with Tab.

The visible Actions list, workspace list, resource list and resource editor subscribe to `onAppletFocusRestore`. Restoring an editor focuses its non-text root. Return or Tab then reenters the destination field, or the optional name field in shortcut mode.

## Layout and checks

Workspace content height follows the current list or editor and caps at 320 points. Actions keeps a stable list height so reading contextual commands does not create a resize dependency. Text, lists and forms sit on the background; Save controls and transient confirmations receive their own elevation.

Run `Tests/run-checks.sh ActionFlows ActionApplets AppletCommand SavedActions` for command composition, draft lifetime, resource inference, persistence and rendering checks. Verify Escape-to-Return and nested workspace editing through the actual host after changing focus behavior.
