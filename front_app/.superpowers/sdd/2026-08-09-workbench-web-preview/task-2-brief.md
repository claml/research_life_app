### Task 2: Implement Navigation Configuration and Pure State

**Files:**
- Create: `docs/workbench_preview/scripts/nav-config.js`
- Create: `docs/workbench_preview/scripts/state.js`
- Create: `docs/workbench_preview/tests/state.test.mjs`

**Interfaces:**
- Consumes: state/action contracts defined in this plan.
- Produces: `PRIMARY_NAV`, `WORKSPACE_TABS`, `createInitialState()`, and `reducePreviewState()` for all later rendering and interaction tasks.

- [ ] **Step 1: Write the failing state tests**

Create `tests/state.test.mjs` with Node built-in tests covering:

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import { createInitialState, reducePreviewState } from '../scripts/state.js';

test('weather is manual and restores the previous workspace', () => {
  const initial = createInitialState();
  const inResearch = reducePreviewState(initial, {
    type: 'SELECT_WORKSPACE',
    workspace: 'research'
  });
  const inWeather = reducePreviewState(inResearch, { type: 'ENTER_WEATHER' });
  assert.equal(inWeather.workspace, 'weather');
  assert.equal(inWeather.previousWorkspace, 'research');
  const restored = reducePreviewState(inWeather, { type: 'EXIT_WEATHER' });
  assert.equal(restored.workspace, 'research');
  assert.equal(restored.previousWorkspace, null);
});

test('secondary tabs are remembered independently', () => {
  let state = createInitialState();
  state = reducePreviewState(state, {
    type: 'SELECT_TAB',
    workspace: 'research',
    tab: 'notes'
  });
  state = reducePreviewState(state, {
    type: 'SELECT_TAB',
    workspace: 'today',
    tab: 'calendar'
  });
  assert.equal(state.workspaceTabs.research, 'notes');
  assert.equal(state.workspaceTabs.today, 'calendar');
});

test('unknown workspaces and tabs leave state unchanged', () => {
  const state = createInitialState();
  assert.deepEqual(
    reducePreviewState(state, { type: 'SELECT_WORKSPACE', workspace: 'unknown' }),
    state
  );
  assert.deepEqual(
    reducePreviewState(state, {
      type: 'SELECT_TAB',
      workspace: 'research',
      tab: 'unknown'
    }),
    state
  );
});
```

- [ ] **Step 2: Run the tests and verify failure**

Run:

```powershell
node --test docs\workbench_preview\tests\state.test.mjs
```

Expected: FAIL because `scripts/state.js` does not exist.

- [ ] **Step 3: Implement immutable navigation configuration**

Define primary items with IDs `weather`, `today`, `research`, `materials`, `life`, and `settings`. Define the exact secondary tab IDs from the approved specification. Freeze exported arrays/objects so rendering cannot mutate configuration.

- [ ] **Step 4: Implement the pure reducer**

Implement every action contract listed in this plan. `ENTER_WEATHER` must copy the current non-weather workspace into `previousWorkspace`; `EXIT_WEATHER` must restore it or fall back to `today`; no timer action exists.

- [ ] **Step 5: Run state tests**

Run:

```powershell
node --test docs\workbench_preview\tests\state.test.mjs
```

Expected: all tests PASS.

- [ ] **Step 6: Record the checkpoint**

Run:

```powershell
Get-ChildItem docs\workbench_preview\scripts\nav-config.js,docs\workbench_preview\scripts\state.js,docs\workbench_preview\tests\state.test.mjs | Select-Object Name,Length
```

Expected: three non-empty files.

---

