import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { PRIMARY_NAV, WORKSPACE_TABS } from '../scripts/nav-config.js';
import { DEMO_DATA as fullDemoData } from '../scripts/demo-data.js';
import { createInitialState, reducePreviewState } from '../scripts/state.js';
import { renderPreview } from '../scripts/render.js';
import {
  actionFromTarget,
  focusKeyFromRoot,
  restoreFocusByKey,
  startPreview
} from '../scripts/app.js';

const demoData = {
  weather: {
    time: '16:38',
    date: '8月9日 星期日',
    condition: '多云',
    temperature: '24°C',
    feelsLike: '体感 24°C',
    wind: '北风 2 级',
    humidity: '湿度 56%',
    todayItems: [
      { id: 'reading', label: '阅读文献', time: '18:00' },
      { id: 'notes', label: '整理记录', time: '20:00' },
      { id: 'walk', label: '晚间散步', time: '21:30' }
    ]
  }
};

function fakeRoot() {
  return { innerHTML: '', dataset: {} };
}

function renderState(state) {
  const root = fakeRoot();
  renderPreview(root, state, fullDemoData);
  return root.innerHTML;
}

function fakeTarget(dataset) {
  const actionable = { dataset };
  return { closest: () => actionable };
}

test('workspace render exposes semantic navigation and configured labels', () => {
  const root = fakeRoot();
  const state = createInitialState();

  renderPreview(root, state, demoData);

  assert.match(root.innerHTML, /<aside[^>]+aria-label="主导航"/);
  assert.match(root.innerHTML, /<header[^>]+class="workspace-header"/);
  for (const item of PRIMARY_NAV) {
    assert.match(root.innerHTML, new RegExp(`>${item.label}<`));
  }
  for (const tab of WORKSPACE_TABS.today) {
    assert.match(root.innerHTML, new RegExp(`>${tab.label}<`));
  }
  assert.match(root.innerHTML, /aria-current="page"[^>]*>\s*<svg[^>]*>[\s\S]*?今天</);
});

test('weather render keeps a return control and no more than three today items', () => {
  const root = fakeRoot();
  const weatherState = reducePreviewState(createInitialState(), { type: 'ENTER_WEATHER' });

  renderPreview(root, weatherState, demoData);

  assert.match(root.innerHTML, /class="weather-view/);
  assert.match(root.innerHTML, /data-action="exit-weather"/);
  assert.match(root.innerHTML, />返回</);
  assert.match(root.innerHTML, />16:38</);
  assert.match(root.innerHTML, /<time class="weather-clock" datetime="16:38">16:38<\/time>/);
  assert.match(root.innerHTML, />24°C</);
  assert.equal((root.innerHTML.match(/class="weather-agenda__item"/g) ?? []).length, 3);
});

test('weather datetime follows the supplied demo time', () => {
  const root = fakeRoot();
  const weatherState = reducePreviewState(createInitialState(), { type: 'ENTER_WEATHER' });
  const changedTimeData = {
    weather: { ...demoData.weather, time: '07:05' }
  };

  renderPreview(root, weatherState, changedTimeData);

  assert.match(root.innerHTML, /<time class="weather-clock" datetime="07:05">07:05<\/time>/);
});

test('hidden weather chrome leaves only the reveal control tabbable', () => {
  const root = fakeRoot();
  let state = reducePreviewState(createInitialState(), { type: 'ENTER_WEATHER' });
  state = reducePreviewState(state, { type: 'SET_WEATHER_CHROME', visible: false });

  renderPreview(root, state, demoData);

  assert.match(root.innerHTML, /class="weather-reveal"[^>]*data-focus-key="weather-reveal"/);
  assert.doesNotMatch(root.innerHTML, /class="weather-reveal"[^>]*tabindex="-1"/);
  assert.match(root.innerHTML, /class="weather-return[^>]*data-focus-key="weather-return"[^>]*tabindex="-1"/);
  assert.match(root.innerHTML, /class="weather-transparency[^>]*data-focus-key="weather-transparency"[^>]*tabindex="-1"/);
});

test('state-changing controls render stable focus keys', () => {
  const today = renderState(createInitialState());
  const research = renderState(reducePreviewState(createInitialState(), {
    type: 'SELECT_WORKSPACE', workspace: 'research'
  }));
  const materials = renderState(reducePreviewState(createInitialState(), {
    type: 'SELECT_WORKSPACE', workspace: 'materials'
  }));

  for (const key of ['nav-weather', 'nav-today', 'sidebar-toggle', 'sidebar-transparency', 'tab-today-today-overview']) {
    assert.match(today, new RegExp(`data-focus-key="${key}"`));
  }
  assert.match(research, /data-focus-key="research-disclosure-recent-reading"/);
  assert.match(materials, /data-focus-key="material-paper-gnss"/);
});

test('focus helpers capture and restore only eligible keyed controls', () => {
  let focused = false;
  const active = { closest: () => ({ dataset: { focusKey: 'sidebar-toggle' } }) };
  const eligible = {
    disabled: false,
    getAttribute: () => null,
    focus() { focused = true; }
  };
  const root = {
    ownerDocument: { activeElement: active },
    contains: (element) => element === active,
    querySelector: () => eligible
  };

  assert.equal(focusKeyFromRoot(root), 'sidebar-toggle');
  assert.equal(restoreFocusByKey(root, 'sidebar-toggle'), true);
  assert.equal(focused, true);
  assert.equal(restoreFocusByKey({
    querySelector: () => ({ disabled: false, getAttribute: () => '-1', focus() {} })
  }, 'weather-return'), false);
});

test('rerenders retain control focus and restore weather exit to its nav entry', () => {
  const listeners = new Map();
  const focused = [];
  const documentListeners = new Map();
  const previewDocument = {
    activeElement: null,
    addEventListener(type, listener) { documentListeners.set(type, listener); }
  };
  const root = {
    innerHTML: '',
    dataset: {},
    ownerDocument: previewDocument,
    contains: () => true,
    addEventListener(type, listener) { listeners.set(type, listener); },
    querySelector(selector) {
      const key = selector.match(/data-focus-key="([^"]+)"/)?.[1];
      if (!key || !this.innerHTML.includes(`data-focus-key="${key}"`)) return null;
      return { disabled: false, getAttribute: () => null, focus: () => focused.push(key) };
    }
  };
  const previousDocument = globalThis.document;
  globalThis.document = previewDocument;

  try {
    const preview = startPreview(root);
    previewDocument.activeElement = { closest: () => ({ dataset: { focusKey: 'sidebar-toggle' } }) };
    preview.dispatch({ type: 'TOGGLE_SIDEBAR' });
    assert.equal(focused.at(-1), 'sidebar-toggle');

    previewDocument.activeElement = { closest: () => ({ dataset: { focusKey: 'nav-weather' } }) };
    preview.dispatch({ type: 'ENTER_WEATHER' });
    assert.equal(focused.at(-1), 'weather-return');

    preview.dispatch({ type: 'SET_WEATHER_CHROME', visible: false });
    previewDocument.activeElement = { closest: () => ({ dataset: { focusKey: 'weather-reveal' } }) };
    listeners.get('focusin')({
      target: { closest: () => ({ dataset: { focusKey: 'weather-reveal' } }) }
    });
    assert.equal(preview.getState().weatherChromeVisible, true);
    assert.equal(focused.at(-1), 'weather-reveal');

    previewDocument.activeElement = { closest: () => ({ dataset: { focusKey: 'weather-return' } }) };
    preview.dispatch({ type: 'EXIT_WEATHER' });
    assert.equal(focused.at(-1), 'nav-weather');
  } finally {
    if (previousDocument === undefined) delete globalThis.document;
    else globalThis.document = previousDocument;
  }
});

test('inert search submission is prevented without changing preview state', () => {
  const listeners = new Map();
  const root = {
    innerHTML: '',
    dataset: {},
    addEventListener(type, listener) { listeners.set(type, listener); }
  };
  const documentListeners = new Map();
  const previousDocument = globalThis.document;
  globalThis.document = {
    addEventListener(type, listener) { documentListeners.set(type, listener); }
  };

  try {
    const preview = startPreview(root);
    let prevented = false;
    listeners.get('submit')({
      target: { closest: (selector) => selector === '.search-control' ? {} : null },
      preventDefault() { prevented = true; }
    });

    assert.equal(prevented, true);
    assert.deepEqual(preview.getState(), createInitialState());
  } finally {
    if (previousDocument === undefined) delete globalThis.document;
    else globalThis.document = previousDocument;
  }
});

test('delegated controls map to reducer action contracts', () => {
  const state = createInitialState();

  assert.deepEqual(
    actionFromTarget(fakeTarget({ workspace: 'research' }), state),
    { type: 'SELECT_WORKSPACE', workspace: 'research' }
  );
  assert.deepEqual(
    actionFromTarget(fakeTarget({ workspace: 'research', tab: 'notes' }), state),
    { type: 'SELECT_TAB', workspace: 'research', tab: 'notes' }
  );
  assert.deepEqual(
    actionFromTarget(fakeTarget({ action: 'toggle-transparency' }), state),
    { type: 'SET_REDUCED_TRANSPARENCY', enabled: true }
  );
  assert.deepEqual(
    actionFromTarget(fakeTarget({ workspace: 'weather' }), state),
    { type: 'ENTER_WEATHER' }
  );
});

test('reduced-transparency fallbacks make search and weather reveal opaque', () => {
  const tokens = readFileSync(new URL('../styles/tokens.css', import.meta.url), 'utf8');
  const components = readFileSync(new URL('../styles/components.css', import.meta.url), 'utf8');
  const revealFallback = [...components.matchAll(
    /\.preview-root\[data-reduced-transparency="true"\]\s+\.weather-reveal\s*\{([^}]*)\}/g
  )]
    .map((match) => match[1])
    .find((block) => /background:\s*var\(--surface-opaque-reveal\);/.test(block)) ?? '';

  assert.match(tokens, /--surface-opaque-search:\s*#[0-9a-f]{6};/i);
  assert.match(tokens, /--surface-opaque-reveal:\s*#[0-9a-f]{6};/i);
  assert.match(
    components,
    /\[data-reduced-transparency="true"\]\s+\.weather-reveal[\s\S]*?\{[\s\S]*?backdrop-filter:\s*none;/
  );
  assert.match(components, /\.search-control\s*\{\s*background:\s*var\(--surface-opaque-search\);/);
  assert.match(components, /\.weather-reveal\s*\{\s*background:\s*var\(--surface-opaque-reveal\);/);
  assert.match(revealFallback, /opacity:\s*1;/);
});

test('collapsed desktop shell reclaims the sidebar grid track', () => {
  const root = fakeRoot();
  const collapsedState = reducePreviewState(createInitialState(), { type: 'TOGGLE_SIDEBAR' });
  const shellCss = readFileSync(new URL('../styles/shell.css', import.meta.url), 'utf8');

  renderPreview(root, collapsedState, demoData);

  assert.match(root.innerHTML, /class="app-shell is-sidebar-collapsed"/);
  assert.match(
    shellCss,
    /\.app-shell\.is-sidebar-collapsed\s*\{\s*grid-template-columns:\s*80px\s+minmax\(0,\s*1fr\);/
  );
});

test('collapsed and compact navigation expose tooltips without hiding the brand mark', () => {
  const root = fakeRoot();
  const shellCss = readFileSync(new URL('../styles/shell.css', import.meta.url), 'utf8');
  const components = readFileSync(new URL('../styles/components.css', import.meta.url), 'utf8');

  renderPreview(root, createInitialState(), demoData);

  assert.match(root.innerHTML, /data-focus-key="nav-weather"[^>]*data-tooltip="天气"/);
  assert.match(components, /\.sidebar\.is-collapsed\s+\.nav-item:(?:hover|focus-visible)::after/);
  assert.match(shellCss, /@media\s*\(max-width:\s*1040px\)[\s\S]*?\.sidebar\s+\.nav-item:(?:hover|focus-visible)::after/);
  assert.match(shellCss, /@media\s*\(max-width:\s*1040px\)[\s\S]*?\.sidebar\s+\.brand__mark\s*\{[\s\S]*?display:\s*inline-flex;/);
});

test('the search field keeps a visible focus-within treatment', () => {
  const components = readFileSync(new URL('../styles/components.css', import.meta.url), 'utf8');

  assert.match(components, /\.search-control:focus-within\s*\{[\s\S]*?outline:\s*3px\s+solid/);
});
