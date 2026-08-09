# Task 1 fix round 1 review package

Scope: verify only the open Important finding from the first review — workspace shell geometry drift across `today.png`, `research.png`, and `materials.png` — plus new breakage introduced by the fix.

The workspace has no Git metadata. The changed binary assets are identified below.

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `docs/workbench_preview/assets/concepts/today.png` | 973,274 | `6C5110E2EF4235E7C5382D4D940D0A6406991A1AD425EB2A40257495CC8686D6` |
| `docs/workbench_preview/assets/concepts/research.png` | 1,076,949 | `0696E68E81459658476A64CBEB4408A3ED4856A9CDB97A50BCB7BF981B8D7FB5` |
| `docs/workbench_preview/assets/concepts/materials.png` | 1,239,911 | `4DCF9BC9D1B3BCF61E59B608E9EC30FAB00B53EC87C0487C6718606A4D90722E` |

All three identify as PNG 1440×900. `today.png` is unchanged and is the geometry source. Research and Materials were regenerated inside Today's pixel-locked shell.

Implementer anchor check reported identical pixels for Research/Materials versus Today across the defined shell probes at sidebar x=21/244, gap x=245–267, main start x=268, main right x=1415, and outer y=24/875, with 0 mismatches for both corrected assets.

Reviewer must inspect all three images with `view_image` at original detail, verify that the Important geometry finding is ADDRESSED or NOT ADDRESSED, and check only for new breakage in the corrected Research/Materials content. The two pre-existing Minor findings are outside this fix round.
