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
