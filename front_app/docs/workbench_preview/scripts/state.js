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
