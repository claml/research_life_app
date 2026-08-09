export const DEMO_DATA = Object.freeze({
  weather: Object.freeze({
    time: '16:38',
    date: '8月9日 星期日',
    year: '2026年',
    condition: '多云',
    temperature: '24°C',
    feelsLike: '体感 24°C',
    wind: '北风 2 级',
    humidity: '湿度 56%',
    todayItems: Object.freeze([
      Object.freeze({ id: 'reading', label: '阅读文献：强化学习综述', time: '18:00' }),
      Object.freeze({ id: 'notes', label: '实验记录整理与分析', time: '20:00' }),
      Object.freeze({ id: 'walk', label: '晚间散步', time: '21:30' })
    ])
  }),
  today: Object.freeze({
    timeline: Object.freeze([
      Object.freeze({ time: '09:00', label: '阅读导航行为综述', meta: '标注核心方法', icon: 'literature' }),
      Object.freeze({ time: '11:30', label: '整理实验记录', meta: '核对三组结果', icon: 'todo' }),
      Object.freeze({ time: '14:00', label: '运行对照实验', meta: '检查参数设置', icon: 'research' })
    ]),
    todos: Object.freeze([
      Object.freeze({ time: '09:30', label: '补充文献批注', priority: 'high', complete: true }),
      Object.freeze({ time: '11:00', label: '整理结果图表', priority: 'high', complete: false }),
      Object.freeze({ time: '14:30', label: '撰写方法摘要', priority: 'medium', complete: false }),
      Object.freeze({ time: '17:00', label: '更新下周计划', priority: 'low', complete: false })
    ]),
    month: Object.freeze({
      label: '2026年8月',
      weekdays: Object.freeze(['一', '二', '三', '四', '五', '六', '日']),
      days: Object.freeze([3, 4, 5, 6, 7, 8, 9]),
      selectedDay: 9
    }),
    agenda: Object.freeze([
      Object.freeze({ time: '09:00', label: '阅读与批注' }),
      Object.freeze({ time: '14:00', label: '对照实验' }),
      Object.freeze({ time: '17:00', label: '计划复盘' })
    ])
  }),
  research: Object.freeze({
    recentReadings: Object.freeze([
      Object.freeze({ title: '室内导航线索综述', meta: '今天 · 已批注', detail: '聚焦空间线索与行为反馈。' }),
      Object.freeze({ title: '路径选择实验方法', meta: '昨天 · 阅读中', detail: '整理实验变量与对照条件。' }),
      Object.freeze({ title: '动态环境建模笔记', meta: '周五 · 待读', detail: '记录可复用的数据表达方式。' })
    ]),
    notes: Object.freeze([
      Object.freeze({ title: '阅读笔记：导航线索', meta: '今天 10:20', detail: '补全术语定义与引用关系。' }),
      Object.freeze({ title: '实验记录：路径对照', meta: '昨天 18:10', detail: '复核两组条件的差异。' }),
      Object.freeze({ title: '讨论摘要：方法取舍', meta: '周五 15:40', detail: '保留三条待验证判断。' })
    ]),
    weeklyPlans: Object.freeze([
      Object.freeze({ title: '完成结果图表整理', meta: '周一 · 高优先级', detail: '统一图例与标注格式。' }),
      Object.freeze({ title: '补充两篇方法文献', meta: '周三 · 进行中', detail: '覆盖路径选择与动态建模。' }),
      Object.freeze({ title: '形成方法章节提纲', meta: '周五 · 待开始', detail: '按问题、方法、验证组织。' })
    ]),
    weeklyAnalysis: Object.freeze([
      Object.freeze({ title: '阅读推进稳定', meta: '3 篇', detail: '批注质量较上周更集中。' }),
      Object.freeze({ title: '实验整理需收口', meta: '2 项待办', detail: '优先完成图表与变量说明。' }),
      Object.freeze({ title: '下周聚焦写作', meta: '方法章节', detail: '先完成结构，再补充论证。' })
    ]),
    people: Object.freeze([
      Object.freeze({ title: '方法讨论组', meta: '周二 · 讨论实验设计' }),
      Object.freeze({ title: '实验协作组', meta: '周四 · 核对结果' }),
      Object.freeze({ title: '资料互助组', meta: '周五 · 交换文献' })
    ]),
    statistics: Object.freeze([
      Object.freeze({ title: '本周阅读', meta: '3 篇 · 2 篇已批注' }),
      Object.freeze({ title: '笔记整理', meta: '3 条 · 1 条待复核' }),
      Object.freeze({ title: '计划进度', meta: '1 项完成 · 2 项进行中' })
    ])
  }),
  materials: Object.freeze({
    folders: Object.freeze([
      Object.freeze({ id: 'all', label: '全部资料', count: 6, depth: 0, active: true }),
      Object.freeze({ id: 'navigation', label: '导航研究', count: 3, depth: 0 }),
      Object.freeze({ id: 'reading', label: '阅读材料', count: 2, depth: 1 }),
      Object.freeze({ id: 'fieldwork', label: '观察记录', count: 1, depth: 1 }),
      Object.freeze({ id: 'experiments', label: '实验记录', count: 2, depth: 0 }),
      Object.freeze({ id: 'figures', label: '图表与草图', count: 1, depth: 0 })
    ]),
    files: Object.freeze([
      Object.freeze({ id: 'paper-gnss', title: '空间导向方法综述.pdf', type: 'PDF', modified: '今天 09:30', size: '2.4 MB', folder: '导航研究 / 阅读材料', icon: 'pdf', note: '整理空间导向研究的概念与常用方法。', tags: Object.freeze(['综述', '导向']) }),
      Object.freeze({ id: 'paper-hci', title: '交互线索观察稿.pdf', type: 'PDF', modified: '昨天 16:20', size: '1.8 MB', folder: '导航研究 / 观察记录', icon: 'pdf', note: '记录公共空间中的交互线索与观察要点。', tags: Object.freeze(['观察', '交互']) }),
      Object.freeze({ id: 'protocol-route', title: '路径选择实验方案.docx', type: 'DOCX', modified: '昨天 11:40', size: '684 KB', folder: '实验记录', icon: 'document', note: '用于比较不同导向提示下的路径选择。', tags: Object.freeze(['实验', '方案']) }),
      Object.freeze({ id: 'sheet-wayfinding', title: '导向标识记录表.xlsx', type: 'XLSX', modified: '周五 18:10', size: '326 KB', folder: '实验记录', icon: 'document', note: '汇总观察点位与标识类型的虚构记录。', tags: Object.freeze(['记录', '标识']) }),
      Object.freeze({ id: 'notes-layout', title: '空间布局阅读笔记.md', type: 'MD', modified: '周四 14:25', size: '48 KB', folder: '导航研究 / 阅读材料', icon: 'document', note: '摘录布局认知相关的术语与问题。', tags: Object.freeze(['笔记', '布局']) }),
      Object.freeze({ id: 'figure-cues', title: '场景线索草图集.png', type: 'PNG', modified: '周三 10:05', size: '3.1 MB', folder: '图表与草图', icon: 'document', note: '用于讨论的场景线索示意草图。', tags: Object.freeze(['草图', '线索']) })
    ])
  }),
  life: Object.freeze({
    campus: Object.freeze([
      Object.freeze({ time: '10:00', title: '校园日程', detail: '图书馆 · 阅读时段' }),
      Object.freeze({ time: '15:30', title: '场地预约', detail: '讨论室 · 45 分钟' }),
      Object.freeze({ time: '18:20', title: '校车提醒', detail: '东门站 · 提前 10 分钟' })
    ]),
    companion: Object.freeze({ name: '专注桌宠', state: '安静陪伴', streak: '25 分钟' }),
    themes: Object.freeze([
      Object.freeze({ name: '云杉绿', color: '#0f6657', active: true }),
      Object.freeze({ name: '雾蓝', color: '#6e8f98' }),
      Object.freeze({ name: '石墨', color: '#3f4b52' })
    ])
  })
});
