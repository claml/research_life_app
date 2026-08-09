# Task 6 Manual Review Package

## Range

- Base: reviewed non-Git workspace after Task 5.
- Head: current Task 6 hardening + README.
- Inspect only the six modified/added files below, Task 6 report, and fidelity ledger.

## Files

| Path | Bytes | Lines | SHA-256 |
| --- | ---: | ---: | --- |
| `scripts/app.js` | 2902 | 89 | `0C4528FD134D8F840D3E8721F24753E10BD56F2A6628CB30C1C9451667B32506` |
| `scripts/render.js` | 25683 | 548 | `A400F3EEBE1AE2BC8C5C91D416F682489BDAA2A701DBF4348EB833988813942A` |
| `styles/views.css` | 30176 | 1703 | `517A68D7BB6A086986FAEA66879CE3B8FF6BCFC8F40782391B80F03C670C18F6` |
| `tests/shell.test.mjs` | 6006 | 162 | `B276B5F25D060F2ECF667D6B3729BA2203D3C6663135B388A46291A027C59F94` |
| `tests/state.test.mjs` | 12183 | 307 | `44E9C90894388B922BE28948E2046B9194CA17BE30291CEA8E7956A536FA2D3F` |
| `README.md` | 1724 | 36 | `E2C0DF91421A95476266BB8E989BDCC59948EE3D0BE1E19C36A570A2D58AB2F2` |

## Fresh automated evidence

- Full preview suite: 24 passed, 0 failed, exit 0.
- Recursive preview inventory: 19 files, all non-empty; 17 required file-map files present plus two reviewed additions (`weather-cloudscape.png`, `shell.test.mjs`); no screenshot/temp/debug/build/font artifacts under the preview directory.

## Final in-app Browser evidence

Viewport override: 1280×800 for native acceptance; 980×800 was already rechecked for Materials and shell with no visible overflow, then reset.

1. Today → Research → Notes → Weather → Escape: returned to heading `科研`; `笔记整理` region count 1 and Notes tab `aria-current="page"`; console clean.
2. Materials → select `交互线索观察稿.pdf` via labelled native button → Document View → Files: Document View heading persisted and Files row returned with `aria-selected="true"`.
3. Collapse sidebar → Life → Settings → expand: both destination headings correct and both expand/collapse controls became visible in the expected state.
4. Enable reduced transparency → Weather: toggle stayed `aria-pressed="true"` in Weather; console clean; composed screenshot shows opaque card and reveal.
5. Search submit: entering `导航` and pressing Enter kept the exact URL and `今天` heading; no navigation/reload.
6. Materials accessibility snapshot: each ARIA row contains a labelled native button such as `选择资料：交互线索观察稿.pdf`.

## Fidelity evidence

- Captured four current 1280×800 viewport PNGs in this plan's SDD directory, outside the product preview.
- Used `view_image` at original detail on all four accepted 1440×900 concepts and all four current screenshots in the same QA pass.
- Comparison points per screen: primary nav/copy, shell layout/proportions, typography hierarchy, cool palette/selective glass, container model/spacing, and interaction/responsive continuation.
- Above-the-fold copy diff: Chinese primary/secondary labels and principal actions match the approved inventory; no invented hero, badges, metric strip, cloud/account claims, or explanatory blocks. Intended demo-data/count/date differences are documented in `fidelity-ledger.md`.
- No material mismatch remains: Weather cloudscape and glass composition, Today open split, Research open sections/sole AI action, and Materials table/inspector anatomy all remain recognizable and faithful at the plan's acceptance viewport.

## Temporary evidence cleanup

The four QA PNGs are temporary evidence outside `docs/workbench_preview`; the controller will remove them after review.
