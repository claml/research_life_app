import { DEMO_DATA } from './demo-data.js';
import { renderPreview } from './render.js';
import { createInitialState, reducePreviewState } from './state.js';

const ACTIONS = Object.freeze({
  'enter-weather': () => ({ type: 'ENTER_WEATHER' }),
  'exit-weather': () => ({ type: 'EXIT_WEATHER' }),
  'toggle-sidebar': () => ({ type: 'TOGGLE_SIDEBAR' }),
  'show-weather-chrome': () => ({ type: 'SET_WEATHER_CHROME', visible: true }),
  'toggle-research-panel': (_state, element) => ({
    type: 'TOGGLE_RESEARCH_PANEL',
    id: element.dataset.panel
  }),
  'select-material': (_state, element) => ({
    type: 'SELECT_MATERIAL',
    id: element.dataset.material
  }),
  'toggle-transparency': (state) => ({
    type: 'SET_REDUCED_TRANSPARENCY',
    enabled: !state.reducedTransparency
  })
});

export function actionFromTarget(target, state) {
  const element = target?.closest?.('[data-action], [data-workspace], [data-tab]');
  if (!element) return null;
  const { action, workspace, tab } = element.dataset;

  if (action && ACTIONS[action]) return ACTIONS[action](state, element);
  if (tab && workspace) return { type: 'SELECT_TAB', workspace, tab };
  if (workspace === 'weather') return { type: 'ENTER_WEATHER' };
  if (workspace) return { type: 'SELECT_WORKSPACE', workspace };
  return null;
}

export function focusKeyFromRoot(root) {
  const activeElement = root?.ownerDocument?.activeElement;
  if (!activeElement) return null;
  if (typeof root.contains === 'function' && !root.contains(activeElement)) return null;
  return activeElement.closest?.('[data-focus-key]')?.dataset?.focusKey ?? null;
}

export function restoreFocusByKey(root, focusKey) {
  if (!focusKey || typeof root?.querySelector !== 'function') return false;
  const element = root.querySelector(`[data-focus-key="${focusKey}"]`);
  if (!element || element.disabled || element.getAttribute?.('tabindex') === '-1') return false;
  element.focus?.({ preventScroll: true });
  return true;
}

export function startPreview(root) {
  if (!root) throw new TypeError('startPreview requires a root element');

  let state = createInitialState();
  let weatherOriginFocusKey = null;
  const render = (focusKey = null) => {
    renderPreview(root, state, DEMO_DATA);
    restoreFocusByKey(root, focusKey);
  };
  const dispatch = (action) => {
    if (!action) return;
    const activeFocusKey = focusKeyFromRoot(root);
    const nextState = reducePreviewState(state, action);
    if (nextState === state) return;
    let nextFocusKey = activeFocusKey;
    if (action.type === 'ENTER_WEATHER') {
      weatherOriginFocusKey = activeFocusKey === 'nav-weather' ? activeFocusKey : 'nav-weather';
      nextFocusKey = 'weather-return';
    } else if (action.type === 'EXIT_WEATHER') {
      nextFocusKey = weatherOriginFocusKey ?? 'nav-weather';
      weatherOriginFocusKey = null;
    }
    state = nextState;
    render(nextFocusKey);
  };

  root.addEventListener('click', (event) => {
    dispatch(actionFromTarget(event.target, state));
  });

  root.addEventListener('submit', (event) => {
    if (event.target?.closest?.('.search-control')) event.preventDefault();
  });

  root.addEventListener('pointerout', (event) => {
    const weatherView = event.target?.closest?.('.weather-view');
    if (state.workspace !== 'weather' || !weatherView) return;
    if (!weatherView.contains(event.relatedTarget)) {
      dispatch({ type: 'SET_WEATHER_CHROME', visible: false });
    }
  });

  root.addEventListener('pointerover', (event) => {
    if (state.workspace !== 'weather') return;
    if (event.target?.closest?.('[data-weather-reveal]')) {
      dispatch({ type: 'SET_WEATHER_CHROME', visible: true });
    }
  });

  root.addEventListener('focusin', (event) => {
    if (state.workspace !== 'weather' || state.weatherChromeVisible) return;
    if (event.target?.closest?.('[data-focus-key="weather-reveal"]')) {
      dispatch({ type: 'SET_WEATHER_CHROME', visible: true });
    }
  });

  (root.ownerDocument ?? document).addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && state.workspace === 'weather') {
      event.preventDefault();
      dispatch({ type: 'EXIT_WEATHER' });
    }
  });

  render();
  return Object.freeze({
    dispatch,
    getState: () => state
  });
}

if (typeof document !== 'undefined') {
  const root = document.querySelector('#app');
  if (root) startPreview(root);
}
