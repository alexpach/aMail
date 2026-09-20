# Third-party source

## Spectrum UI

Copyright: Spectrum UI contributors. Licensed under Apache License 2.0, reproduced in `licenses/Spectrum-UI.txt`.

Source repository: https://github.com/arihantcodes/spectrum-ui

Copied or adapted from the public main branch on 2026-09-19:

- `src/components/spectrum/button.tsx`: https://github.com/arihantcodes/spectrum-ui/blob/main/components/ui/button.tsx. Import path adapted for aMail.
- `src/components/spectrum/task-checkbox.tsx`: https://github.com/arihantcodes/spectrum-ui/blob/main/components/spectrumui/task-checkbox.tsx. Retains the controlled checkbox, spring press feedback, animated check stroke and reduced-motion handling. Removes the task label presentation, descriptions, confetti, strikethrough and uncontrolled mode; uses the compact aMail row styles.

Other dependencies retain their respective package licenses in the npm distribution and are pinned by `package-lock.json`.
