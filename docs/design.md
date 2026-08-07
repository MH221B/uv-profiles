# Design

The repository contains a dot-sourced runtime and a separate installer. The runtime defines a local `uv` function, intercepting only `activate` and `profiles`; all other arguments invoke the resolved `uv.exe` directly. Activation snapshots PATH, environment variables, prompt, and any existing `deactivate` function so switching and deactivation are session-local and reversible.

Profile names are validated before literal filesystem lookup. Generated `Activate.ps1` files are validity markers and are never executed. No execution policy, machine-wide setting, or unrelated profile content is changed.
