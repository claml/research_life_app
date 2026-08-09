# SDD ledger — plan: docs/superpowers/plans/2026-08-09-workbench-web-preview.md

Execution workspace fallback: current workspace, because the project has no Git repository metadata and cannot create a worktree.
Baseline: Flutter 180 tests passed; backend 13 tests passed; Dart analysis reported 1 warning and 5 info items.
Task 1: in progress
Task 1: review found Important — normalize sidebar width, shell gap, main-panel start, and outer offsets across today/research/materials.
Task 1: minor (deferred) — weather left-edge reveal affordance is taller/more prominent than ideal.
Task 1: minor (deferred) — materials inspector uses `下载` beside explicitly local-file status; consider `导出`/`另存为`.
Task 1: fix round 1/5 started.
Task 1: fix round 1/5 (1 addressed, 0 open; no commits — non-Git workspace)
Task 1: complete (review clean; non-Git workspace)
Task 2: minor (deferred) — add focused coverage for sidebar, weather fallback/chrome validation, material selection, research panel, and reduced-transparency actions in later tasks.
Task 2: complete (review clean; non-Git workspace; 3/3 tests passed)
Task 3: review found 3 Important — weather background fidelity, incomplete opaque reduced-transparency fallback, and unreclaimed desktop sidebar grid track.
Task 3: minor (deferred) — derive weather `<time datetime>` from demo data.
Task 3: minor (deferred) — prevent inert search form submission/reload.
Task 3: minor (deferred) — add focused regression coverage for collapsed track and complete transparency fallback.
Task 3: fix round 1/5 started.
Task 3: fix round 1/5 (2 addressed, 1 open — Weather reveal retains opacity 0.52 under reduced transparency; no commits — non-Git workspace)
Task 3: fix round 2/5 started.
Task 3: fix round 2/5 (1 addressed, 0 open; no commits — non-Git workspace)
Task 3: complete (review clean; non-Git workspace; 8/8 tests passed; Browser 1280×800 and 980×800 checked)
Task 4: plan note — prescribed reducer toggle regression was already GREEN because Task 2 was required to implement every action contract; new render/action behavior had independent RED→GREEN evidence.
Task 4: complete (review clean; non-Git workspace; 13/13 tests passed; Browser 1280×800 checked)
Task 5: review found Important — PDF tools must not expose merge/extract actions for non-PDF selections.
Task 5: minor (deferred) — native material row buttons override their control semantics with `role="row"`.
Task 5: fix round 1/5 started.
Task 5: fix round 1/5 (1 addressed, 0 open; no commits — non-Git workspace)
Task 5: complete (review clean; non-Git workspace; 19/19 tests passed; Browser 1280×800 and 980×800 checked)
Task 6: RED captured (24 tests: 21 pass, 3 expected failures for weather datetime, inert search submit, and material row semantics).
Task 6: GREEN and final QA hardening complete (24/24 full preview tests; 17/17 state tests; 19-file inventory; required=17, missing=0, empty=0, forbidden artifacts=0; live Browser pass left to controller).
Task 6: review found 2 Important — hidden Weather actions stayed tabbable and full rerenders lost focus; runtime keyboard coverage was deferred.
Task 6: fix round 1/5 started; RED captured (shell suite exit 1 at missing focus-helper export before production changes).
Task 6: fix round 1/5 GREEN (11/11 focused shell tests; 28/28 full preview tests; stable focus keys/restoration and hidden Weather tab order addressed).
Task 6: Browser regression passed — Research and sidebar controls retain focus after rerender; entering Weather focuses Return; Escape restores focus to nav-weather and the prior Research workspace; pointer exit makes hidden Return/transparency tabindex=-1 while reveal remains tabbable; focusing reveal restores chrome and keeps reveal focus.
Task 6: fix round 1/5 complete (scoped re-review PASS; no Critical/Important findings).
Final review: 1 Important (collapsed/compact nav lacked hover/focus tooltips) and 2 Minor (Search focus ring, compact brand mark) found; final fix wave started.
Final fix wave RED: focused shell suite 11/13, with the two new contract tests failing before implementation.
Final fix wave GREEN: focused shell suite 13/13; Browser 1280 confirms visible focus tooltip and Search focus ring, Browser 980 confirms brand mark visible and no page overflow.
Final fix scoped re-review: ACCEPTED; all prior findings resolved, no new Critical/Important issues, fresh full suite 30/30.
