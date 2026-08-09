# Task 2 Review Package

## Range

- Base: non-Git workspace; all three task files were absent before Task 2.
- Head: current working tree after Task 2.
- Scope: exactly the three newly created files below.

## Inventory

| File | Bytes |
| --- | ---: |
| `docs/workbench_preview/scripts/nav-config.js` | 1530 |
| `docs/workbench_preview/scripts/state.js` | 2683 |
| `docs/workbench_preview/tests/state.test.mjs` | 1548 |

## Added file: `scripts/nav-config.js`

```js
const freezeItems = (items) => Object.freeze(
  items.map((item) => Object.freeze({ ...item }))
);

export const PRIMARY_NAV = freezeItems([
  { id: 'weather', label: '天气', icon: 'weather' },
  { id: 'today', label: '今天', icon: 'today' },
  { id: 'research', label: '科研', icon: 'research' },
  { id: 'materials', label: '资料', icon: 'materials' },
  { id: 'life', label: '生活', icon: 'life' },
  { id: 'settings', label: '设置', icon: 'settings' }
]);

export const WORKSPACE_TABS = Object.freeze({
  today: freezeItems([
    { id: 'today-overview', label: '今天' },
    { id: 'calendar', label: '日历' },
    { id: 'todos', label: '待办' }
  ]),
  research: freezeItems([
    { id: 'research-overview', label: '概览' },
    { id: 'literature', label: '文献' },
    { id: 'notes', label: '笔记' },
    { id: 'weekly-analysis', label: '周分析' },
    { id: 'people', label: '人员' },
    { id: 'statistics', label: '统计' }
  ]),
  materials: freezeItems([
    { id: 'files', label: '文件' },
    { id: 'document-viewer', label: '文档查看' },
    { id: 'pdf-tools', label: 'PDF 工具' }
  ]),
  life: freezeItems([
    { id: 'campus', label: '校园' },
    { id: 'companion', label: '桌宠' },
    { id: 'personalization', label: '个性化' }
  ])
});

export function isWorkspaceId(value) {
  return typeof value === 'string' && PRIMARY_NAV.some((item) => item.id === value);
}

export function defaultTabFor(workspaceId) {
  return WORKSPACE_TABS[workspaceId]?.[0]?.id ?? null;
}
```

## Added file: `scripts/state.js`

```js
import { WORKSPACE_TABS, defaultTabFor, isWorkspaceId } from './nav-config.js';

const hasTab = (workspace, tab) => (
  WORKSPACE_TABS[workspace]?.some((item) => item.id === tab) ?? false
);

const isNonWeatherWorkspace = (workspace) => isWorkspaceId(workspace) && workspace !== 'weather';

export function createInitialState() {
  return {
    workspace: 'today',
    workspaceTabs: {
      today: defaultTabFor('today'),
      research: defaultTabFor('research'),
      materials: defaultTabFor('materials'),
      life: defaultTabFor('life')
    },
    sidebarCollapsed: false,
    weatherChromeVisible: true,
    previousWorkspace: null,
    selectedMaterialId: 'paper-gnss',
    expandedResearchPanel: null,
    reducedTransparency: false
  };
}

export function reducePreviewState(state, action) {
  switch (action?.type) {
    case 'SELECT_WORKSPACE': {
      if (!isNonWeatherWorkspace(action.workspace)) return state;
      return { ...state, workspace: action.workspace, previousWorkspace: null };
    }
    case 'SELECT_TAB': {
      if (!hasTab(action.workspace, action.tab)) return state;
      return {
        ...state,
        workspaceTabs: { ...state.workspaceTabs, [action.workspace]: action.tab }
      };
    }
    case 'TOGGLE_SIDEBAR':
      return { ...state, sidebarCollapsed: !state.sidebarCollapsed };
    case 'ENTER_WEATHER':
      if (state.workspace === 'weather') return state;
      return {
        ...state,
        workspace: 'weather',
        previousWorkspace: isNonWeatherWorkspace(state.workspace)
          ? state.workspace
          : 'today'
      };
    case 'SET_WEATHER_CHROME':
      if (typeof action.visible !== 'boolean') return state;
      return { ...state, weatherChromeVisible: action.visible };
    case 'EXIT_WEATHER':
      if (state.workspace !== 'weather') return state;
      return {
        ...state,
        workspace: isNonWeatherWorkspace(state.previousWorkspace)
          ? state.previousWorkspace
          : 'today',
        previousWorkspace: null,
        weatherChromeVisible: true
      };
    case 'SELECT_MATERIAL':
      if (typeof action.id !== 'string' || action.id.length === 0) return state;
      return { ...state, selectedMaterialId: action.id };
    case 'TOGGLE_RESEARCH_PANEL':
      if (typeof action.id !== 'string' || action.id.length === 0) return state;
      return {
        ...state,
        expandedResearchPanel: state.expandedResearchPanel === action.id ? null : action.id
      };
    case 'SET_REDUCED_TRANSPARENCY':
      if (typeof action.enabled !== 'boolean') return state;
      return { ...state, reducedTransparency: action.enabled };
    default:
      return state;
  }
}
```

## Added file: `tests/state.test.mjs`

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

## Fresh controller verification

`node --test docs\\workbench_preview\\tests\\state.test.mjs` exited 0 with 3 passed, 0 failed. Inventory matched the byte counts above.
