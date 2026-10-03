# About the project

smool is a native macOS utility built around design and user experience. The goal is simple access to apps and services through the notch, navigable entirely with the keyboard. The app should be fast, use minimal resources, and only appear when the user needs or wants it.

This project is a work in progress. Features and integrations have not been decided yet.

## Code style

- Write simple, idiomatic Swift with clear names and intentional whitespace.
- Start from first principles and established UX practices. Keep the user in control.
- Solve concrete needs. Avoid unnecessary abstractions and ceremonial complexity.
- Verify changes and commit regularly in small, cohesive commits. Include only work related to the task and keep build artifacts out of Git.

## UI/UX principles

- Design for the notch. Use Music, Spotify and Home as references for hierarchy, spacing, gradients and interaction. Integrations need a compact smool interface rather than a miniature copy of another app.
- Keyboard first. Every workflow must be usable without a mouse. Show useful shortcuts in the view, not only on hover. Keep secondary commands in the shared Actions panel, available with Command-K, instead of adding competing buttons and menus.
- Escape must always provide a way out of editing and overlays so applet navigation becomes available again. Preserve drafts when leaving a text field. Keep Command-number applet shortcuts available.
- Show applet tabs in pages of four. Moving beyond a group reveals the next group from the left; navigation wraps to Home. A plain +N overflow control opens the full applet menu. Do not add a separate caret or make overflow a glass circle.
- Actions and Workspaces are persistent host tools on the right, not applet tabs. Actions contains individual commands; Workspaces groups resources to open together. Avoid duplicate navigation and competing ellipsis menus.
- Place ordinary content and quiet shortcut hints directly on the background. Use native Liquid Glass for floating controls and applet tabs. Preserve Home's established colors, animated gradients and glass treatment when adding features.
- Keep the closed notch content-sized and minimal. Use recognizable icons or icon-sized text with deliberate padding, including the trailing edge.
- Use inline transitions and floating overlays within smool for editors and detail views. Avoid separate macOS dialogs for app workflows. Keep the floating composer's rounded edges concentric with the outer shape.
- Prefer inferred, forgiving input. Normalize ordinary website addresses automatically. Do not require users to supply redundant names, schemes or technical details when they can be derived.
- Timers use a centered, bold duration and a borderless, initially focused input with a small unit label. Provide visible presets and keyboard adjustment, Return to start, music-style playback controls and an orange glow. Do not ask for timer names.
- Audio device selection and volume belong inside smool. Make device navigation and volume adjustment discoverable from the keyboard; use controls shaped for this form factor.
- Keep text, empty states and shortcut hints comfortably inside the rounded edges. Remove visual clutter before adding decoration.
- All interface copy is English. Respect Reduce Motion and avoid background animation or observation work when the notch is closed.
- Verify keyboard escape paths, tab hit targets, Home colors and animation, closed-state spacing and representative workflows after UI changes. A successful build alone does not establish that the experience is correct.
