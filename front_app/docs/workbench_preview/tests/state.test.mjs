import test from 'node:test';
import assert from 'node:assert/strict';
import { actionFromTarget } from '../scripts/app.js';
import { DEMO_DATA } from '../scripts/demo-data.js';
import { renderPreview } from '../scripts/render.js';
import { createInitialState, reducePreviewState } from '../scripts/state.js';

function fakeRoot() {
  return { innerHTML: '', dataset: {} };
}

function renderState(state) {
  const root = fakeRoot();
  renderPreview(root, state, DEMO_DATA);
  return root.innerHTML;
}

function fakeTarget(dataset) {
  const actionable = { dataset };
  return { closest: () => actionable };
}

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

test('sidebar toggle changes only collapsed state and toggles back', () => {
  const initial = createInitialState();
  const collapsed = reducePreviewState(initial, { type: 'TOGGLE_SIDEBAR' });
  const expanded = reducePreviewState(collapsed, { type: 'TOGGLE_SIDEBAR' });

  assert.equal(collapsed.sidebarCollapsed, true);
  assert.equal(expanded.sidebarCollapsed, false);
  assert.equal(initial.sidebarCollapsed, false);
  assert.notEqual(collapsed, initial);
});

test('weather chrome validates booleans and invalid weather origins fall back to today', () => {
  const initial = createInitialState();
  const hidden = reducePreviewState(initial, { type: 'SET_WEATHER_CHROME', visible: false });
  const invalid = reducePreviewState(hidden, { type: 'SET_WEATHER_CHROME', visible: 'false' });
  const entered = reducePreviewState({ ...initial, workspace: 'unknown' }, { type: 'ENTER_WEATHER' });
  const restored = reducePreviewState(entered, { type: 'EXIT_WEATHER' });

  assert.equal(hidden.weatherChromeVisible, false);
  assert.equal(invalid, hidden);
  assert.equal(entered.previousWorkspace, 'today');
  assert.equal(restored.workspace, 'today');
  assert.equal(restored.weatherChromeVisible, true);
});

test('reduced transparency accepts booleans and rejects non-boolean values', () => {
  const initial = createInitialState();
  const reduced = reducePreviewState(initial, {
    type: 'SET_REDUCED_TRANSPARENCY', enabled: true
  });

  assert.equal(reduced.reducedTransparency, true);
  assert.notEqual(reduced, initial);
  assert.equal(
    reducePreviewState(reduced, { type: 'SET_REDUCED_TRANSPARENCY', enabled: 1 }),
    reduced
  );
});

test('material selection accepts a valid id and ignores an empty id', () => {
  const initial = createInitialState();
  const selected = reducePreviewState(initial, {
    type: 'SELECT_MATERIAL',
    id: 'paper-hci'
  });

  assert.equal(selected.selectedMaterialId, 'paper-hci');
  assert.notEqual(selected, initial);
  assert.equal(
    reducePreviewState(selected, { type: 'SELECT_MATERIAL', id: '' }),
    selected
  );
});

test('research panel toggles one expanded section immutably', () => {
  const initial = createInitialState();
  const expanded = reducePreviewState(initial, {
    type: 'TOGGLE_RESEARCH_PANEL',
    id: 'recent-reading'
  });
  const collapsed = reducePreviewState(expanded, {
    type: 'TOGGLE_RESEARCH_PANEL',
    id: 'recent-reading'
  });

  assert.equal(initial.expandedResearchPanel, null);
  assert.equal(expanded.expandedResearchPanel, 'recent-reading');
  assert.equal(collapsed.expandedResearchPanel, null);
  assert.notEqual(expanded, initial);
  assert.notEqual(collapsed, expanded);
});

test('research disclosure maps its panel id to the existing reducer action', () => {
  assert.deepEqual(
    actionFromTarget(fakeTarget({ action: 'toggle-research-panel', panel: 'recent-reading' }), createInitialState()),
    { type: 'TOGGLE_RESEARCH_PANEL', id: 'recent-reading' }
  );
});

test('today tabs render overview, calendar agenda, and priority-aware todos', () => {
  const initial = createInitialState();
  const overview = renderState(initial);
  const calendar = renderState(reducePreviewState(initial, {
    type: 'SELECT_TAB', workspace: 'today', tab: 'calendar'
  }));
  const todos = renderState(reducePreviewState(initial, {
    type: 'SELECT_TAB', workspace: 'today', tab: 'todos'
  }));

  assert.match(overview, /data-view="today-overview"/);
  assert.equal((overview.match(/class="timeline-item"/g) ?? []).length, 3);
  assert.equal((overview.match(/<li class="todo-row(?: is-complete)?"/g) ?? []).length, 4);
  assert.match(calendar, /data-view="today-calendar"/);
  assert.match(calendar, /aria-label="八月日期"/);
  assert.match(calendar, />当日安排</);
  assert.match(todos, /data-view="today-todos"/);
  assert.match(todos, /data-priority="high"/);
  assert.match(todos, /is-complete/);
});

test('research overview has open sections, one AI action, and expandable detail', () => {
  let state = reducePreviewState(createInitialState(), {
    type: 'SELECT_WORKSPACE', workspace: 'research'
  });
  const overview = renderState(state);
  state = reducePreviewState(state, {
    type: 'TOGGLE_RESEARCH_PANEL', id: 'recent-reading'
  });
  const expanded = renderState(state);

  assert.match(overview, /data-view="research-overview"/);
  for (const label of ['最近阅读', '待整理笔记', '本周计划', '周分析']) {
    assert.match(overview, new RegExp(`>${label}<`));
  }
  assert.equal((overview.match(/>AI 助手</g) ?? []).length, 1);
  assert.doesNotMatch(overview, /research-panel__detail/);
  assert.match(expanded, /data-panel="recent-reading"[^>]*aria-expanded="true"/);
  assert.match(expanded, /class="research-panel__detail"/);
});

test('every secondary research tab renders a compact structural preview without extra AI', () => {
  const initial = reducePreviewState(createInitialState(), {
    type: 'SELECT_WORKSPACE', workspace: 'research'
  });

  for (const tab of ['literature', 'notes', 'weekly-analysis', 'people', 'statistics']) {
    const html = renderState(reducePreviewState(initial, {
      type: 'SELECT_TAB', workspace: 'research', tab
    }));
    assert.match(html, new RegExp(`data-view="research-${tab}"`));
    assert.doesNotMatch(html, /即将|敬请期待|coming soon/i);
    assert.equal((html.match(/>AI 助手</g) ?? []).length, 0);
  }
});

test('material rows map selection and render a folder, table, and inspector workflow', () => {
  const initial = reducePreviewState(createInitialState(), {
    type: 'SELECT_WORKSPACE', workspace: 'materials'
  });
  const selected = reducePreviewState(initial, {
    type: 'SELECT_MATERIAL', id: 'paper-hci'
  });
  const initialHtml = renderState(initial);
  const selectedHtml = renderState(selected);

  assert.deepEqual(
    actionFromTarget(fakeTarget({ action: 'select-material', material: 'paper-hci' }), initial),
    { type: 'SELECT_MATERIAL', id: 'paper-hci' }
  );
  assert.match(initialHtml, /data-view="materials-files"/);
  assert.match(initialHtml, /class="materials-folder-pane"[^>]*aria-label="资料文件夹"/);
  assert.match(initialHtml, /class="materials-file-table"[^>]*role="table"/);
  assert.match(initialHtml, /class="materials-inspector"[^>]*aria-label="资料详情"/);
  assert.equal((initialHtml.match(/class="material-row(?: is-selected)?"/g) ?? []).length, 6);
  assert.match(initialHtml, /class="material-row is-selected"[^>]*role="row"[^>]*aria-selected="true"/);
  assert.match(initialHtml, /<button class="material-row__select"[^>]*data-material="paper-gnss"[^>]*aria-label="[^"]+"/);
  assert.doesNotMatch(initialHtml, /<button class="material-row[^>]*role="row"/);
  assert.match(selectedHtml, /class="material-row is-selected"[^>]*data-material="paper-hci"[^>]*aria-selected="true"/);
  assert.match(selectedHtml, /class="materials-inspector"[\s\S]*>交互线索观察稿\.pdf</);
  assert.match(selectedHtml, />导出</);
  assert.doesNotMatch(selectedHtml, /下载|云端|同步|账户/);
});

test('materials secondary tabs preserve the selected item in distinct tool previews', () => {
  let state = reducePreviewState(createInitialState(), {
    type: 'SELECT_WORKSPACE', workspace: 'materials'
  });
  state = reducePreviewState(state, { type: 'SELECT_MATERIAL', id: 'paper-hci' });

  const viewer = renderState(reducePreviewState(state, {
    type: 'SELECT_TAB', workspace: 'materials', tab: 'document-viewer'
  }));
  const tools = renderState(reducePreviewState(state, {
    type: 'SELECT_TAB', workspace: 'materials', tab: 'pdf-tools'
  }));

  assert.match(viewer, /data-view="materials-document-viewer"/);
  assert.match(viewer, />交互线索观察稿\.pdf</);
  assert.match(tools, /data-view="materials-pdf-tools"/);
  assert.match(tools, />交互线索观察稿\.pdf</);
  assert.match(tools, />另存为</);
  assert.doesNotMatch(`${viewer}${tools}`, /下载|云端|同步|账户/);
});

test('PDF tools with a non-PDF selection hide page actions and request a PDF', () => {
  let state = reducePreviewState(createInitialState(), {
    type: 'SELECT_WORKSPACE', workspace: 'materials'
  });
  state = reducePreviewState(state, {
    type: 'SELECT_MATERIAL', id: 'protocol-route'
  });
  state = reducePreviewState(state, {
    type: 'SELECT_TAB', workspace: 'materials', tab: 'pdf-tools'
  });
  const html = renderState(state);

  assert.match(html, /data-view="materials-pdf-tools"/);
  assert.match(html, />路径选择实验方案\.docx</);
  assert.doesNotMatch(html, />合并页面<|>提取页面<|>另存为</);
  assert.match(html, /data-state="requires-pdf"/);
  assert.match(html, />请选择 PDF 资料</);
});

test('life tabs render concise campus, companion, and personalization previews', () => {
  const life = reducePreviewState(createInitialState(), {
    type: 'SELECT_WORKSPACE', workspace: 'life'
  });
  const expectations = [
    ['campus', 'life-campus', '校园日程'],
    ['companion', 'life-companion', '专注桌宠'],
    ['personalization', 'life-personalization', '界面主题']
  ];

  for (const [tab, view, label] of expectations) {
    const html = renderState(reducePreviewState(life, {
      type: 'SELECT_TAB', workspace: 'life', tab
    }));
    assert.match(html, new RegExp(`data-view="${view}"`));
    assert.match(html, new RegExp(`>${label}<`));
    assert.doesNotMatch(html, /即将|敬请期待|coming soon/i);
  }
});

test('settings exposes short appearance and accessibility controls including transparency', () => {
  const settings = reducePreviewState(createInitialState(), {
    type: 'SELECT_WORKSPACE', workspace: 'settings'
  });
  const html = renderState(settings);
  const reducedHtml = renderState(reducePreviewState(settings, {
    type: 'SET_REDUCED_TRANSPARENCY', enabled: true
  }));

  assert.match(html, /data-view="settings"/);
  assert.match(html, />外观</);
  assert.match(html, />辅助功能</);
  assert.match(html, /data-action="toggle-transparency"[^>]*aria-pressed="false"/);
  assert.match(reducedHtml, /data-action="toggle-transparency"[^>]*aria-pressed="true"/);
  assert.doesNotMatch(html, /账户|同步|云端/);
});
