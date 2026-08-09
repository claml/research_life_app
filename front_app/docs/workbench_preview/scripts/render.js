import { PRIMARY_NAV, WORKSPACE_TABS } from './nav-config.js';

const icon = (name, className = 'icon') => `
  <svg class="${className}" aria-hidden="true" focusable="false">
    <use href="assets/icons.svg#icon-${name}"></use>
  </svg>`;

const escapeHtml = (value) => String(value ?? '')
  .replaceAll('&', '&amp;')
  .replaceAll('<', '&lt;')
  .replaceAll('>', '&gt;')
  .replaceAll('"', '&quot;')
  .replaceAll("'", '&#039;');

const workspaceLabel = (workspace) => (
  PRIMARY_NAV.find((item) => item.id === workspace)?.label ?? ''
);

function renderNavButton(item, state) {
  const active = item.id === state.workspace;
  const weatherAction = item.id === 'weather' ? ' data-action="enter-weather"' : '';
  return `
    <button class="nav-item${active ? ' is-active' : ''}" type="button"
      data-workspace="${item.id}" data-focus-key="nav-${item.id}" data-tooltip="${item.label}"${weatherAction}
      ${active ? 'aria-current="page"' : ''} aria-label="${item.label}">
      ${icon(item.icon)}
      <span class="nav-item__label">${item.label}</span>
    </button>`;
}

function renderSidebar(state) {
  const primaryItems = PRIMARY_NAV.filter((item) => item.id !== 'settings');
  const settings = PRIMARY_NAV.find((item) => item.id === 'settings');
  return `
    <aside class="sidebar${state.sidebarCollapsed ? ' is-collapsed' : ''}" aria-label="主导航">
      <div class="sidebar__brand-row">
        <a class="brand" href="./" aria-label="研LIFE 首页">
          <span class="brand__mark">${icon('brand')}</span>
          <span class="brand__text"><strong>研</strong>LIFE</span>
        </a>
        <button class="icon-button sidebar__toggle" type="button" data-action="toggle-sidebar" data-focus-key="sidebar-toggle"
          aria-label="${state.sidebarCollapsed ? '展开侧边栏' : '收起侧边栏'}" aria-pressed="${state.sidebarCollapsed}">
          ${icon('sidebar-toggle')}
        </button>
      </div>

      <form class="search-control" role="search">
        ${icon('search')}
        <label class="visually-hidden" for="preview-search">搜索</label>
        <input id="preview-search" type="search" placeholder="搜索" autocomplete="off" data-focus-key="sidebar-search">
      </form>

      <nav class="sidebar__nav" aria-label="工作区">
        ${primaryItems.map((item) => renderNavButton(item, state)).join('')}
      </nav>

      <div class="sidebar__footer">
        <button class="nav-item transparency-toggle" type="button" data-action="toggle-transparency" data-focus-key="sidebar-transparency"
          data-tooltip="降低透明度" aria-pressed="${state.reducedTransparency}" aria-label="降低透明度">
          ${icon('personalization')}
          <span class="nav-item__label">降低透明度</span>
          <span class="toggle-dot" aria-hidden="true"></span>
        </button>
        ${renderNavButton(settings, state)}
      </div>
    </aside>`;
}

function renderTabs(workspace, state) {
  const tabs = WORKSPACE_TABS[workspace] ?? [];
  if (tabs.length === 0) return '';
  const activeTab = state.workspaceTabs[workspace];
  return `
    <nav class="workspace-tabs" aria-label="${workspaceLabel(workspace)}视图">
      ${tabs.map((tab) => `
        <button class="workspace-tab${activeTab === tab.id ? ' is-active' : ''}" type="button"
          data-workspace="${workspace}" data-tab="${tab.id}" data-focus-key="tab-${workspace}-${tab.id}"
          ${activeTab === tab.id ? 'aria-current="page"' : ''}>${tab.label}</button>`).join('')}
    </nav>`;
}

function renderTodoRows(todos, detailed = false) {
  const priorityLabels = { high: '高', medium: '中', low: '低' };
  return todos.map((item) => `
    <li class="todo-row${item.complete ? ' is-complete' : ''}" data-priority="${escapeHtml(item.priority ?? 'medium')}">
      <span class="todo-checkbox" aria-hidden="true">${item.complete ? icon('todo', 'icon icon--small') : ''}</span>
      <span class="todo-row__label">${escapeHtml(item.label)}</span>
      ${detailed ? `<span class="priority-label">${escapeHtml(priorityLabels[item.priority] ?? '中')}优先级</span>` : ''}
      <time>${escapeHtml(item.time)}</time>
      ${icon('chevron', 'icon icon--small')}
    </li>`).join('');
}

function renderTodayOverview(today) {
  const timeline = today?.timeline ?? [];
  const todos = today?.todos ?? [];
  return `
    <div class="today-preview" data-view="today-overview">
      <section class="preview-section timeline-preview" aria-labelledby="timeline-title">
        <h2 id="timeline-title">时间线</h2>
        <ol class="timeline-list">
          ${timeline.map((item) => `
            <li class="timeline-item">
              <time>${escapeHtml(item.time)}</time>
              <span class="timeline-item__dot" aria-hidden="true"></span>
              <span class="timeline-item__icon">${icon(item.icon)}</span>
              <span class="timeline-item__copy">
                <strong>${escapeHtml(item.label)}</strong>
                <small>${escapeHtml(item.meta)}</small>
              </span>
            </li>`).join('')}
        </ol>
      </section>
      <section class="preview-section todo-preview" aria-labelledby="todo-title">
        <h2 id="todo-title">待办</h2>
        <ul class="todo-list">
          ${renderTodoRows(todos)}
        </ul>
      </section>
    </div>`;
}

function renderTodayCalendar(today) {
  const month = today?.month ?? { label: '', weekdays: [], days: [], selectedDay: null };
  const agenda = today?.agenda ?? [];
  return `
    <div class="calendar-preview" data-view="today-calendar">
      <section class="month-strip" aria-labelledby="month-title">
        <div class="section-heading">
          <h2 id="month-title">${escapeHtml(month.label)}</h2>
          <span>本周</span>
        </div>
        <div class="month-strip__weekdays" aria-hidden="true">
          ${(month.weekdays ?? []).map((day) => `<span>${escapeHtml(day)}</span>`).join('')}
        </div>
        <ol class="month-strip__days" aria-label="八月日期">
          ${(month.days ?? []).map((day) => `
            <li${day === month.selectedDay ? ' class="is-selected" aria-current="date"' : ''}>
              <span>${escapeHtml(day)}</span>
            </li>`).join('')}
        </ol>
      </section>
      <section class="agenda-preview" aria-labelledby="agenda-title">
        <div class="section-heading">
          <h2 id="agenda-title">当日安排</h2>
          <span>${agenda.length} 项</span>
        </div>
        <ol class="agenda-list">
          ${agenda.map((item) => `
            <li><time>${escapeHtml(item.time)}</time><span>${escapeHtml(item.label)}</span></li>`).join('')}
        </ol>
      </section>
    </div>`;
}

function renderTodayTodos(today) {
  const todos = today?.todos ?? [];
  return `
    <section class="todos-preview" data-view="today-todos" aria-labelledby="all-todos-title">
      <div class="section-heading">
        <h2 id="all-todos-title">今日待办</h2>
        <span>${todos.filter((item) => item.complete).length}/${todos.length} 已完成</span>
      </div>
      <ul class="todo-list todo-list--detailed">${renderTodoRows(todos, true)}</ul>
    </section>`;
}

function renderTodayView(state, data) {
  const today = data?.today ?? data?.todayPreview ?? {};
  switch (state.workspaceTabs.today) {
    case 'calendar':
      return renderTodayCalendar(today);
    case 'todos':
      return renderTodayTodos(today);
    default:
      return renderTodayOverview(today);
  }
}

const RESEARCH_SECTIONS = Object.freeze([
  Object.freeze({ id: 'recent-reading', label: '最近阅读', dataKey: 'recentReadings', icon: 'literature' }),
  Object.freeze({ id: 'notes', label: '待整理笔记', dataKey: 'notes', icon: 'notes' }),
  Object.freeze({ id: 'weekly-plans', label: '本周计划', dataKey: 'weeklyPlans', icon: 'todo' }),
  Object.freeze({ id: 'weekly-analysis', label: '周分析', dataKey: 'weeklyAnalysis', icon: 'analysis' })
]);

function renderResearchRows(items, itemIcon) {
  return items.map((item) => `
    <li class="research-row">
      <span class="research-row__icon">${icon(itemIcon, 'icon icon--small')}</span>
      <strong>${escapeHtml(item.title)}</strong>
      <span>${escapeHtml(item.meta)}</span>
    </li>`).join('');
}

function renderResearchOverview(state, research) {
  return `
    <div class="research-overview" data-view="research-overview">
      ${RESEARCH_SECTIONS.map((section) => {
        const items = research?.[section.dataKey] ?? [];
        const expanded = state.expandedResearchPanel === section.id;
        return `
          <section class="research-panel" aria-labelledby="${section.id}-title">
            <div class="research-panel__heading">
              <h2 id="${section.id}-title">${section.label}</h2>
              <button class="research-disclosure" type="button" data-action="toggle-research-panel"
                data-panel="${section.id}" data-focus-key="research-disclosure-${section.id}" aria-expanded="${expanded}">
                <span>${expanded ? '收起' : '查看详情'}</span>${icon('chevron', 'icon icon--small')}
              </button>
            </div>
            <ul class="research-list">${renderResearchRows(items, section.icon)}</ul>
            ${expanded && items[0] ? `<p class="research-panel__detail">${escapeHtml(items[0].detail)}</p>` : ''}
          </section>`;
      }).join('')}
    </div>`;
}

function renderCompactResearchView(tab, research) {
  const viewConfig = {
    literature: { title: '文献队列', dataKey: 'recentReadings', icon: 'literature', aside: '按阅读状态排列' },
    notes: { title: '笔记整理', dataKey: 'notes', icon: 'notes', aside: '按更新时间排列' },
    'weekly-analysis': { title: '本周分析', dataKey: 'weeklyAnalysis', icon: 'analysis', aside: '阅读、实验与写作' },
    people: { title: '协作安排', dataKey: 'people', icon: 'people', aside: '按小组与时间排列' },
    statistics: { title: '科研统计', dataKey: 'statistics', icon: 'statistics', aside: '本周简报' }
  };
  const config = viewConfig[tab] ?? viewConfig.literature;
  const items = research?.[config.dataKey] ?? [];
  return `
    <section class="research-compact" data-view="research-${tab}" aria-labelledby="research-${tab}-title">
      <div class="section-heading">
        <h2 id="research-${tab}-title">${config.title}</h2>
        <span>${config.aside}</span>
      </div>
      <ul class="research-list research-list--compact">${renderResearchRows(items, config.icon)}</ul>
    </section>`;
}

function renderResearchView(state, data) {
  const research = data?.research ?? {};
  const tab = state.workspaceTabs.research;
  return tab === 'research-overview'
    ? renderResearchOverview(state, research)
    : renderCompactResearchView(tab, research);
}

function selectedMaterial(state, materials) {
  const files = materials?.files ?? [];
  return files.find((item) => item.id === state.selectedMaterialId) ?? files[0] ?? null;
}

function renderMaterialInspector(material) {
  if (!material) {
    return '<aside class="materials-inspector" aria-label="资料详情"><p>请选择资料</p></aside>';
  }
  return `
    <aside class="materials-inspector" aria-label="资料详情">
      <div class="materials-inspector__identity">
        <span class="material-type-icon material-type-icon--${escapeHtml(material.type.toLowerCase())}">
          ${icon(material.icon ?? 'document')}
        </span>
        <div><h2>${escapeHtml(material.title)}</h2><span>${escapeHtml(material.type)} · ${escapeHtml(material.size)}</span></div>
      </div>
      <div class="materials-inspector__actions" aria-label="资料操作">
        <button type="button">${icon('document', 'icon icon--small')}<span>打开</span></button>
        <button type="button">${icon('materials', 'icon icon--small')}<span>导出</span></button>
      </div>
      <dl class="materials-meta">
        <div><dt>位置</dt><dd>${escapeHtml(material.folder)}</dd></div>
        <div><dt>修改时间</dt><dd>${escapeHtml(material.modified)}</dd></div>
        <div><dt>类型</dt><dd>${escapeHtml(material.type)}</dd></div>
      </dl>
      <section class="materials-note" aria-labelledby="material-note-title">
        <h3 id="material-note-title">摘要</h3>
        <p>${escapeHtml(material.note)}</p>
      </section>
      <div class="materials-tags" aria-label="标签">
        ${(material.tags ?? []).map((tag) => `<span>${escapeHtml(tag)}</span>`).join('')}
      </div>
    </aside>`;
}

function renderMaterialsFiles(state, materials) {
  const files = materials?.files ?? [];
  const material = selectedMaterial(state, materials);
  return `
    <div class="materials-workbench" data-view="materials-files">
      <nav class="materials-folder-pane" aria-label="资料文件夹">
        <div class="materials-pane-heading"><h2>文件夹</h2><span>${files.length}</span></div>
        <ul class="materials-folder-tree" role="tree">
          ${(materials?.folders ?? []).map((folder) => `
            <li role="treeitem" aria-level="${Number(folder.depth ?? 0) + 1}"
              ${folder.active ? 'aria-current="true"' : ''}
              class="materials-folder${folder.active ? ' is-active' : ''}"
              style="--folder-depth: ${Number(folder.depth ?? 0)}">
              ${icon('materials', 'icon icon--small')}
              <span>${escapeHtml(folder.label)}</span><small>${escapeHtml(folder.count)}</small>
            </li>`).join('')}
        </ul>
      </nav>
      <section class="materials-list-pane" aria-labelledby="materials-list-title">
        <div class="materials-pane-heading">
          <div><h2 id="materials-list-title">全部资料</h2><span>${files.length} 项</span></div>
          <span>按修改时间</span>
        </div>
        <div class="materials-file-table" role="table" aria-label="资料列表">
          <div class="material-table-head" role="row">
            <span role="columnheader">名称</span><span role="columnheader">类型</span>
            <span role="columnheader">修改时间</span><span role="columnheader">大小</span>
          </div>
          <div class="material-table-body" role="rowgroup">
            ${files.map((item) => {
              const selected = material?.id === item.id;
              return `
                <div class="material-row${selected ? ' is-selected' : ''}" role="row"
                  data-material="${escapeHtml(item.id)}" aria-selected="${selected}">
                  <span class="material-row__name" role="cell">
                    <button class="material-row__select" type="button" data-action="select-material"
                      data-material="${escapeHtml(item.id)}" data-focus-key="material-${escapeHtml(item.id)}"
                      aria-label="选择资料：${escapeHtml(item.title)}"></button>
                    <span class="material-type-icon material-type-icon--${escapeHtml(item.type.toLowerCase())}">${icon(item.icon ?? 'document', 'icon icon--small')}</span>
                    <strong>${escapeHtml(item.title)}</strong>
                  </span>
                  <span role="cell">${escapeHtml(item.type)}</span>
                  <span role="cell">${escapeHtml(item.modified)}</span>
                  <span role="cell">${escapeHtml(item.size)}</span>
                </div>`;
            }).join('')}
          </div>
        </div>
      </section>
      ${renderMaterialInspector(material)}
    </div>`;
}

function renderMaterialsTool(state, materials, tab) {
  const material = selectedMaterial(state, materials);
  const isViewer = tab === 'document-viewer';
  const isPdf = material?.type === 'PDF';
  return `
    <section class="materials-tool" data-view="materials-${tab}" aria-labelledby="materials-tool-title">
      <div class="materials-tool__stage">
        <span class="materials-tool__icon">${icon(isViewer ? 'document' : 'pdf')}</span>
        <div>
          <span>${isViewer ? '文档查看' : 'PDF 工具'}</span>
          <h2 id="materials-tool-title">${escapeHtml(material?.title ?? '请选择资料')}</h2>
          <small>${escapeHtml(material?.type ?? '')} ${material ? `· ${escapeHtml(material.size)}` : ''}</small>
        </div>
      </div>
      <div class="materials-tool__rail">
        <h3>${isViewer ? '阅读位置' : isPdf ? '整理操作' : '当前资料'}</h3>
        ${isViewer ? `
          <div class="document-page-preview" aria-label="文档页面预览">
            <span></span><span></span><span></span><span></span>
          </div>
          <button type="button" class="quiet-action">打开查看</button>` : isPdf ? `
          <button type="button" class="tool-row"><span>合并页面</span><small>选择顺序</small></button>
          <button type="button" class="tool-row"><span>提取页面</span><small>保留原稿</small></button>
          <button type="button" class="quiet-action">另存为</button>` : `
          <div class="materials-tool__unsupported" data-state="requires-pdf">
            <strong>请选择 PDF 资料</strong>
            <span>当前资料为 ${escapeHtml(material?.type ?? '未知类型')}</span>
          </div>`}
      </div>
    </section>`;
}

function renderMaterialsView(state, data) {
  const materials = data?.materials ?? {};
  const tab = state.workspaceTabs.materials;
  return tab === 'files'
    ? renderMaterialsFiles(state, materials)
    : renderMaterialsTool(state, materials, tab);
}

function renderLifeView(state, data) {
  const life = data?.life ?? {};
  const tab = state.workspaceTabs.life;
  if (tab === 'companion') {
    return `
      <section class="life-preview life-companion" data-view="life-companion" aria-labelledby="companion-title">
        <div class="companion-scene" aria-hidden="true">
          <span class="companion-sun"></span><span class="companion-plant"></span>
          <span class="companion-character">${icon('companion')}</span>
        </div>
        <div class="life-preview__copy">
          <span>安静模式</span><h2 id="companion-title">${escapeHtml(life.companion?.name ?? '专注桌宠')}</h2>
          <p>${escapeHtml(life.companion?.state ?? '')} · ${escapeHtml(life.companion?.streak ?? '')}</p>
          <button type="button" class="quiet-action">开始专注</button>
        </div>
      </section>`;
  }
  if (tab === 'personalization') {
    return `
      <section class="life-preview life-personalization" data-view="life-personalization" aria-labelledby="theme-title">
        <div class="life-preview__copy"><span>个性化</span><h2 id="theme-title">界面主题</h2><p>选择柔和的工作台配色。</p></div>
        <div class="theme-options" role="list" aria-label="主题选项">
          ${(life.themes ?? []).map((theme) => `
            <button type="button" role="listitem" class="theme-option${theme.active ? ' is-active' : ''}">
              <span style="--theme-color: ${escapeHtml(theme.color)}"></span><strong>${escapeHtml(theme.name)}</strong>
            </button>`).join('')}
        </div>
      </section>`;
  }
  return `
    <section class="life-preview life-campus" data-view="life-campus" aria-labelledby="campus-title">
      <div class="life-preview__copy"><span>今天</span><h2 id="campus-title">校园日程</h2><p>三项轻量提醒。</p></div>
      <ol class="campus-list">
        ${(life.campus ?? []).map((item) => `
          <li><time>${escapeHtml(item.time)}</time><span>${icon('campus', 'icon icon--small')}</span>
            <div><strong>${escapeHtml(item.title)}</strong><small>${escapeHtml(item.detail)}</small></div></li>`).join('')}
      </ol>
    </section>`;
}

function renderSettingsView(state) {
  return `
    <div class="settings-preview" data-view="settings">
      <section class="settings-group" aria-labelledby="appearance-title">
        <div><span>${icon('personalization')}</span><h2 id="appearance-title">外观</h2></div>
        <div class="setting-row"><span><strong>界面色调</strong><small>云杉绿</small></span><button type="button" class="setting-choice">默认</button></div>
        <div class="setting-row"><span><strong>文字大小</strong><small>舒适</small></span><button type="button" class="setting-choice">标准</button></div>
      </section>
      <section class="settings-group" aria-labelledby="accessibility-title">
        <div><span>${icon('settings')}</span><h2 id="accessibility-title">辅助功能</h2></div>
        <div class="setting-row">
          <span><strong>降低透明度</strong><small>将玻璃表面切换为不透明背景</small></span>
          <button class="setting-toggle" type="button" data-action="toggle-transparency" data-focus-key="settings-transparency"
            aria-pressed="${state.reducedTransparency}" aria-label="降低透明度"><span aria-hidden="true"></span></button>
        </div>
        <div class="setting-row"><span><strong>减少动态效果</strong><small>跟随系统偏好</small></span><span class="setting-status">自动</span></div>
      </section>
    </div>`;
}

function renderQuietWorkspace(workspace) {
  const activeIcon = PRIMARY_NAV.find((item) => item.id === workspace)?.icon ?? 'document';
  return `
    <section class="quiet-workspace" aria-label="${workspaceLabel(workspace)}内容预览">
      <span class="quiet-workspace__mark">${icon(activeIcon)}</span>
      <span class="quiet-workspace__line"></span>
      <span class="quiet-workspace__line quiet-workspace__line--short"></span>
    </section>`;
}

function renderWorkspace(state, data) {
  const title = workspaceLabel(state.workspace);
  const showQuickCapture = state.workspace === 'today';
  const showResearchAi = state.workspace === 'research'
    && state.workspaceTabs.research === 'research-overview';
  const content = state.workspace === 'today'
    ? renderTodayView(state, data)
    : state.workspace === 'research'
      ? renderResearchView(state, data)
      : state.workspace === 'materials'
        ? renderMaterialsView(state, data)
        : state.workspace === 'life'
          ? renderLifeView(state, data)
          : state.workspace === 'settings'
            ? renderSettingsView(state)
            : renderQuietWorkspace(state.workspace);
  return `
    <div class="workspace-panel">
      <header class="workspace-header">
        <div class="workspace-header__topline">
          <h1>${title}</h1>
          ${showQuickCapture ? `
            <button class="quick-action" type="button" aria-label="快速记录">
              ${icon('quick-capture')}<span>快速记录</span>
            </button>` : ''}
          ${showResearchAi ? `
            <button class="research-ai-action" type="button" aria-label="AI 助手">
              ${icon('ai')}<span>AI 助手</span>
            </button>` : ''}
        </div>
        ${renderTabs(state.workspace, state)}
      </header>
      <div class="workspace-content">
        ${content}
      </div>
    </div>`;
}

function renderWeatherAgenda(items) {
  return items.slice(0, 3).map((item) => `
    <li class="weather-agenda__item">
      <span class="weather-agenda__check" aria-hidden="true"></span>
      <span>${escapeHtml(item.label)}</span>
      <time>${escapeHtml(item.time)}</time>
    </li>`).join('');
}

function renderWeather(state, data) {
  const weather = data?.weather ?? {};
  const chromeClass = state.weatherChromeVisible ? '' : ' is-chrome-hidden';
  const hiddenControlTabIndex = state.weatherChromeVisible ? '' : ' tabindex="-1"';
  return `
    <section class="weather-view${chromeClass}" aria-label="天气待机">
      <div class="weather-atmosphere" aria-hidden="true"></div>
      <button class="weather-reveal" type="button" data-weather-reveal data-action="show-weather-chrome" data-focus-key="weather-reveal"
        aria-label="显示天气控制">${icon('chevron')}</button>

      <article class="weather-card glass-surface">
        <div class="weather-card__brand"><strong>研</strong>LIFE</div>
        <time class="weather-clock" datetime="${escapeHtml(weather.time)}">${escapeHtml(weather.time)}</time>
        <div class="weather-date">
          <strong>${escapeHtml(weather.date)}</strong>
          <span>${escapeHtml(weather.year)}</span>
        </div>
        <div class="weather-summary">
          <span class="weather-symbol" aria-hidden="true">
            <span class="weather-symbol__sun"></span>
            <span class="weather-symbol__cloud"></span>
          </span>
          <span class="weather-summary__temp">${escapeHtml(weather.temperature)}</span>
          <strong>${escapeHtml(weather.condition)}</strong>
        </div>
        <div class="weather-details" aria-label="天气详情">
          <span>${escapeHtml(weather.feelsLike)}</span>
          <span>${escapeHtml(weather.wind)}</span>
          <span>${escapeHtml(weather.humidity)}</span>
        </div>
        <div class="weather-agenda">
          <div class="weather-agenda__heading">
            <h2>今日待办</h2>
            <span>${Math.min(weather.todayItems?.length ?? 0, 3)}项</span>
          </div>
          <ul>${renderWeatherAgenda(weather.todayItems ?? [])}</ul>
        </div>
      </article>

      <button class="weather-return floating-control" type="button" data-action="exit-weather" data-focus-key="weather-return"${hiddenControlTabIndex}>
        ${icon('back')}<span>返回</span>
      </button>
      <button class="weather-transparency floating-control" type="button" data-action="toggle-transparency" data-focus-key="weather-transparency"${hiddenControlTabIndex}
        aria-pressed="${state.reducedTransparency}" aria-label="降低透明度">
        ${icon('personalization')}
      </button>
    </section>`;
}

export function renderPreview(root, state, data) {
  if (!root || typeof root !== 'object') {
    throw new TypeError('renderPreview requires a root element');
  }
  root.dataset.reducedTransparency = String(Boolean(state.reducedTransparency));
  root.className = state.workspace === 'weather' ? 'preview-root is-weather' : 'preview-root';
  root.innerHTML = state.workspace === 'weather'
    ? renderWeather(state, data)
    : `<div class="app-shell${state.sidebarCollapsed ? ' is-sidebar-collapsed' : ''}">${renderSidebar(state)}${renderWorkspace(state, data)}</div>`;
}
