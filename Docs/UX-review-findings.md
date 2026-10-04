# UI regression checks

The UI review on 4 October 2026 identified failures in focus recovery, arrow routing, draft retention, shortcut collisions and stale Codex activity. This document retains the useful regression scenarios. It does not certify later changes or record a current test run.

Current ownership and keyboard contracts are described in [host integration](UX-integration.md) and [Actions and Workspaces](UX-services.md). Run checks through `Tests/run-checks.sh`; use `--list` to see the available cases.

## Keyboard and drafts

- Enter a Timer duration, leave with Escape, then press Return. Editing must resume with the same text. Opening the empty timer form must leave applet navigation available until Tab begins editing.
- Adjust `59:30` with Up, then start the timer. The adjusted text must remain valid input.
- Leave Notes, Files path entry, a saved-action editor and a Codex composer with Escape. Return or the advertised editing shortcut must reopen the retained draft.
- Open Actions from Notes and invoke New note. The source command must operate on Notes; saved-action creation uses Command-Shift-N.
- Edit a workspace with two resources. Up/Down must change selection and Space must change inclusion. Leave an unfinished resource edit, save the workspace, then reopen the resource. Its unfinished input must remain available.
- Open Actions from Workspaces or Settings, then leave it. The source view must return. Command-number and Control-Tab must remain usable from text editing.
- On Home, Escape leaves event details, then the calendar, then closes the notch. Capture previews and contextual help must have their own Escape step.

## Saving during quit

- Edit Notes while another store is still saving during quit. The newer text must also reach disk before termination succeeds.
- Fail an Actions or Workspaces write while another store is saving. The quit attempt must report the failure even if that operation has already left its pending queue. Its editor must remain available.
- Retry Notes after a failed write. Dirty text must remain intact. Failed saved-action and workspace operations require explicit retry and must never replay during a later quit attempt.

## Rendering and accessibility

- Verify groups of four applet tabs, the plain +N menu, navigation wrapping and tab hit targets beside the camera. Actions and Workspaces stay outside the applet tabs.
- Check Home's shared palette, moving glow, black camera band and concentric card edges on compact and notched displays.
- Check the closed notch with no status, one status and multiple statuses. Content remains compact with deliberate trailing padding.
- Timer creation, paused timers and completed timers stay unlit. Only the displayed running timer gets the orange glow.
- Inspect resource forms, Files previews and Codex pickers on the background layer. Floating composers and confirmations may use their own glass surface; the whole page should not be elevated.
- Repeat representative transitions with Reduce Motion and Reduce Transparency enabled. Closing the notch removes expanded content and stops visible-only work.

## Audio and Codex

- Check device-list keyboard selection and per-channel mute restoration. Muting and unmuting unequal channels must preserve their balance.
- History shows a title and latest-message preview. Return opens the exact thread; Command-N opens its composer and Escape preserves its draft.
- Live activity shows the latest message and current tools. Completed tools disappear. Disconnects and revision gaps must not leave cached tools looking live.
- After Escape releases the Codex search field, Command-F must focus it again. Open Actions from a composer for a disconnected thread; its Connect command must retain the intended recipient. Source commands must also work when their rows are outside the Actions viewport.
- A failed history preview can be retried with Command-R. Large activity streams show their supported compact fallback and a way to open the full thread in Codex.
- Leaving Codex dismisses its transient pickers and composer while preserving drafts and thread selection. Hidden activity must not keep rebuilding the visible projection.

The earlier review also covered transcript scrolling and local project thumbnails. Those implementations have been removed; current checks should exercise the compact activity projection and project membership instead.
