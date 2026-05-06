# 本地每周分析部署手册

适用项目：`D:\桌面\研究生活\应用`

目标：把“每周分析”从当前的本地规则分析，升级为“本地大模型优先，规则分析兜底”。

推荐方案：
- 本地模型运行器：`Ollama`
- 默认模型：`qwen3:4b`
- 兜底模型：当前已有规则分析 `[analysis_service.dart](D:\桌面\研究生活\应用\lib\services\analysis\analysis_service.dart)`

---

## 1. 先决条件

你的机器当前适合做这个版本：
- CPU：`i5-1240P`
- 内存：`16 GB`
- 显卡：`Intel Iris Xe`
- 结论：适合 `qwen3:4b`，不建议把视觉模型作为主流程

建议：
- `Ollama` 可以装在 `C:` 盘
- 模型目录尽量放到 `D:` 盘

---

## 2. 安装 Ollama

1. 打开官方文档：`https://docs.ollama.com/windows`
2. 安装 `Ollama for Windows`
3. 安装完成后，新开一个 PowerShell，执行：

```powershell
ollama --version
```

如果能输出版本号，说明安装成功。

---

## 3. 把模型目录切到 D 盘

先在 `D:` 盘准备目录：

```powershell
New-Item -ItemType Directory -Force D:\OllamaModels
```

然后设置用户级环境变量：

```powershell
[Environment]::SetEnvironmentVariable('OLLAMA_MODELS', 'D:\OllamaModels', 'User')
```

设置后：
- 关闭 Ollama
- 重新打开 Ollama
- 再开一个新的 PowerShell

验证环境变量：

```powershell
[Environment]::GetEnvironmentVariable('OLLAMA_MODELS', 'User')
```

应输出：

```text
D:\OllamaModels
```

---

## 4. 拉取模型

第一阶段只拉一个模型：

```powershell
ollama pull qwen3:4b
```

拉取完成后检查：

```powershell
ollama list
```

应该能看到 `qwen3:4b`。

如果后面觉得效果不够稳，再升级：

```powershell
ollama pull qwen2.5:7b
```

但第一版不要一开始就上 `7b`。

---

## 5. 先在本机验证接口

先确认 Ollama 本地服务可用。它默认监听：

```text
http://localhost:11434
```

在 PowerShell 里执行：

```powershell
$body = @{
  model = "qwen3:4b"
  stream = $false
  format = "json"
  messages = @(
    @{
      role = "user"
      content = "把这句话转成 JSON：这周我完成了论文整理，下周一要和导师开会。"
    }
  )
  options = @{
    temperature = 0
  }
} | ConvertTo-Json -Depth 8

Invoke-RestMethod `
  -Method Post `
  -Uri "http://localhost:11434/api/chat" `
  -ContentType "application/json" `
  -Body $body
```

如果返回 JSON，说明本地模型接口正常。

---

## 6. 给 Flutter 项目补 HTTP 依赖

当前 [pubspec.yaml](D:\桌面\研究生活\应用\pubspec.yaml) 里还没有 HTTP 客户端依赖。

在项目根目录执行：

```powershell
flutter pub add http
```

然后执行：

```powershell
flutter pub get
```

---

## 7. 新增本地 LLM 分析服务

在 `lib/services/analysis/` 下新增两个文件：

1. `local_llm_analysis_service.dart`
2. `local_llm_analysis_models.dart`

推荐职责：

### `local_llm_analysis_models.dart`

定义只给本地模型用的 DTO：
- `LocalLlmTaskDto`
- `LocalLlmPersonDto`
- `LocalLlmAnalysisDto`

建议字段：
- `summary`
- `warnings`
- `tasks`
- `persons`

`tasks` 每项包含：
- `content`
- `category`
- `type`
- `confidence`
- `relatedPersonNames`
- `timeHint`

`persons` 每项包含：
- `name`
- `role`
- `aliases`
- `relatedTaskIndexes`

### `local_llm_analysis_service.dart`

职责：
- 发 HTTP 请求到 `http://localhost:11434/api/chat`
- 构造 prompt
- 解析模型返回 JSON
- 校验字段是否合法
- 转成 `AnalysisDraft`

---

## 8. Prompt 只做一件事：输出结构化 JSON

不要让模型输出自然语言报告。只让它输出 JSON。

建议 system prompt：

```text
你是一个研究生生活周分析助手。你的任务是从中文周记中提取：
1. tasks：本周已完成事项或未来计划
2. persons：涉及的人物
3. summary：简短总结
4. warnings：信息不足时的提醒

输出必须是合法 JSON，不要输出 Markdown，不要输出解释，不要输出代码块。

category 只能是：
study, work, life, health, social, other

type 只能是：
record, plan

role 只能是：
teacher, classmate, friend, partner, family, other

timeHint 只能是：
明天, 后天, 下周, 周一, 周二, 周三, 周四, 周五, 周六, 周日, 周末

如果某项无法确定，就使用最保守的值，不要编造不存在的信息。
```

建议 user prompt：

```text
请分析下面这段周记，并严格输出 JSON：

{{rawText}}
```

---

## 9. 返回 JSON 结构

建议先用这一版结构：

```json
{
  "summary": "本周共识别出 3 条事项，涉及 2 位人物。",
  "warnings": [],
  "tasks": [
    {
      "content": "完成论文资料整理",
      "category": "work",
      "type": "record",
      "confidence": 0.92,
      "relatedPersonNames": [],
      "timeHint": null
    },
    {
      "content": "下周一和导师开会确认论文框架",
      "category": "work",
      "type": "plan",
      "confidence": 0.9,
      "relatedPersonNames": ["导师"],
      "timeHint": "周一"
    }
  ],
  "persons": [
    {
      "name": "导师",
      "role": "teacher",
      "aliases": [],
      "relatedTaskIndexes": [1]
    }
  ]
}
```

---

## 10. 在项目里怎么接

### 第一步：保留现有规则分析器不动

现有规则分析在：

- [analysis_service.dart](D:\桌面\研究生活\应用\lib\services\analysis\analysis_service.dart)

它继续作为 fallback。

### 第二步：修改 controller 的分析入口

当前入口在：

- [research_life_controller.dart](D:\桌面\研究生活\应用\lib\state\research_life_controller.dart)

当前 `analyzeCurrentInput()` 是同步规则分析。你要把它改成：

```dart
Future<String?> analyzeCurrentInput() async
```

新的执行顺序：

1. 读取输入文本
2. 先调用本地 `LocalLlmAnalysisService.analyze(...)`
3. 如果成功：
   - 写入 `_currentDraft`
   - 再调用 `_reviewService.buildPreview(...)`
4. 如果失败、超时或 JSON 不合法：
   - 回退到 `_analysisService.analyze(...)`

建议超时：
- 首次生成：`45s`
- 正常生成：`20s`

### 第三步：分析页可以基本不改

当前分析页在：

- [analysis_page.dart](D:\桌面\研究生活\应用\lib\features\analysis\analysis_page.dart)

它现在的 `_runAction(...)` 已经接受 `FutureOr<String?> Function()`，所以只要把 `controller.analyzeCurrentInput` 改成 async，大部分调用点可以继续复用。

但 `fillSampleAndAnalyze()` 也需要同步改成 async：

```dart
Future<String?> fillSampleAndAnalyze() async
```

---

## 11. 映射规则

本地模型返回 DTO 后，转成现有模型：

- `LocalLlmTaskDto -> ExtractedTaskDraft`
- `LocalLlmPersonDto -> ExtractedPersonDraft`
- 最后组装成 `AnalysisDraft`

字段映射要点：

- `id`：本地生成，例如 `task_0`, `task_1`
- `confidence`：夹在 `0.0 ~ 1.0`
- `category/type/role`：不在枚举内就回退到 `other`
- `timeHint`：不在允许集合内就置空

---

## 12. 一定要做的校验

不要直接相信模型输出。

在 Dart 端做这些校验：

1. 根对象必须是 JSON object
2. `tasks` 必须是数组
3. `persons` 必须是数组
4. `content` 不能为空
5. `confidence` 必须在 `0` 到 `1`
6. `relatedTaskIndexes` 不能越界
7. 枚举值不合法时自动降级，不要让整个流程崩掉

只要校验失败：
- 记录错误
- 回退规则分析器

---

## 13. 推荐的错误处理策略

本地 LLM 分析失败时，区分 3 类：

### 1. Ollama 没启动

提示：

```text
未连接到本地模型服务，已自动回退到规则分析。请确认 Ollama 正在运行。
```

### 2. 模型没拉取

提示：

```text
未找到本地模型 qwen3:4b，已自动回退到规则分析。请先执行 ollama pull qwen3:4b。
```

### 3. JSON 非法

提示：

```text
本地模型返回格式无效，已自动回退到规则分析。
```

---

## 14. 第一轮联调顺序

按这个顺序做，不要跳：

1. 装好 `Ollama`
2. 拉取 `qwen3:4b`
3. PowerShell 手动调通 `/api/chat`
4. Flutter 加 `http`
5. 写 `LocalLlmAnalysisService`
6. 先在一个临时按钮或测试方法里调用
7. 确认能得到合法 `AnalysisDraft`
8. 再接回 `ResearchLifeController.analyzeCurrentInput()`
9. 最后做 fallback

---

## 15. 验收标准

到这一步算接通：

1. 输入一段周记，能看到事项和人物
2. 同一段输入重复分析，结果基本稳定
3. 本地模型关闭后，仍能自动回退到规则分析
4. 点击“确认结果”后，主页、人物、历史照常同步

---

## 16. 第一版不要做的事

先别做这些：

- 多模型切换 UI
- 温度、上下文长度等高级设置页
- 图片识别
- 云端 API fallback
- 把所有分析过程持久化进数据库

先把“本地大模型周分析 + 规则兜底”打通。

---

## 17. 推荐的第一版文件改动清单

新增：
- `D:\桌面\研究生活\应用\lib\services\analysis\local_llm_analysis_models.dart`
- `D:\桌面\研究生活\应用\lib\services\analysis\local_llm_analysis_service.dart`

修改：
- [pubspec.yaml](D:\桌面\研究生活\应用\pubspec.yaml)
- [research_life_app.dart](D:\桌面\研究生活\应用\lib\app\research_life_app.dart)
- [research_life_controller.dart](D:\桌面\研究生活\应用\lib\state\research_life_controller.dart)
- [analysis_page.dart](D:\桌面\研究生活\应用\lib\features\analysis\analysis_page.dart)

---

## 18. 你现在最应该执行的命令

```powershell
ollama --version
```

```powershell
New-Item -ItemType Directory -Force D:\OllamaModels
```

```powershell
[Environment]::SetEnvironmentVariable('OLLAMA_MODELS', 'D:\OllamaModels', 'User')
```

```powershell
ollama pull qwen3:4b
```

```powershell
ollama list
```

```powershell
flutter pub add http
```

执行完这些，再开始写代码。
