# Fusion Tools by Dominik Bargiel

Scripts and fuses for Blackmagic Fusion and DaVinci Resolve, installable through [Reactor](https://www.steakunderwater.com/wesuckless/viewforum.php?f=32).

| Atom | What it does |
|---|---|
| Control Drop | Hold Ctrl while dropping folders on the Flow to create Loaders for every sequence and movie inside |
| Create Grid Collage | Builds a grid collage from selected Loaders |
| Expression Editor HUD | Edit all expressions on a node in one window (press E) |
| Propagate | Capture parameter changes on one node and apply them to other selected nodes |
| Viewer To Clipboard | Shift+Ctrl+C copies the viewer image; Ctrl+V in the Flow pastes an image as a Loader |
| vRayCameraExtractor | Builds a Fusion camera from the V-Ray camera matrix in EXR metadata |

## Install

In Reactor, click the gear button next to the repository list, paste this repository's URL, press **Check**, then **Add Repository**. Pick the tools you want; each one installs on its own.

## Releasing

Reactor follows this repository's releases. To ship a change:

1. Raise `Version` and `Date` in the atom's `.atom` file.
2. Run `lua Tools/validate-atoms.lua .` (or `fuscript -l lua Tools/validate-atoms.lua .`).
3. Create a GitHub release with a new tag, like `v1.1.0`.

Only atoms whose `Version` changed are offered as updates.
