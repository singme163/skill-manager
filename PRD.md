# PRD：Skill Manager for macOS

## 1. 背景与目标（Context）

Claude Code 与 Codex 都支持基于目录的 Agent Skill（`<skills-dir>/<skill-name>/SKILL.md`），但目前只能靠终端 / Finder 手工管理：看不清本机装了哪些 skill、两个工具之间无法方便地复用、安装社区 skill 需要手动 clone/拷贝。

本产品是一个 **macOS 原生（SwiftUI）App**，统一管理本机 Claude Code 与 Codex 的 skill，提供**查（浏览/搜索）、增（4 种方式）、删、编辑**能力。界面简约、符合 macOS 原生审美，个人开发者自用为主。

**成功标准**：打开 App 3 秒内看清两个工具各装了什么 skill；安装/删除/双端同步一个 skill 都在 3 次点击内完成。

## 2. 事实基础（已在本机验证）

| 项 | Claude Code | Codex |
|---|---|---|
| skill 根目录 | `~/.claude/skills/` | `~/.codex/skills/` |
| 结构 | 每个 skill 一个文件夹，含 `SKILL.md`（必须）+ 可选资源（`references/`、`assets/`、`agents/`、脚本等） | 同左，格式完全一致 |
| 元数据 | `SKILL.md` 顶部 YAML frontmatter：`name`、`description`（必填），可能有其他键 | 同左 |

两端格式一致 ⇒ 跨工具复制 = 目录级拷贝，无需转换。

**范围外**（v1 不做）：插件市场自带的 skill（`~/.claude/plugins/`，只读且由插件系统管理）、项目级 `.claude/skills/`、skill 的启用/禁用状态管理、多机同步。

## 3. 用户与场景

单一用户画像：同时使用 Claude Code 和 Codex 的开发者（即本人）。

核心场景：
1. **盘点**：打开 App，一眼看到两个工具各有哪些 skill、各自的 description。
2. **查找**：按名称/描述关键词搜索，定位某个 skill。
3. **安装**：从 GitHub 链接 / 本地文件夹 / zip 安装一个社区 skill 到指定工具。
4. **同步**：把 Claude Code 里好用的 skill 一键复制到 Codex（或反向）。
5. **新建**：快速创建一个符合规范的空白 skill 骨架，开始编写。
6. **维护**：预览/编辑 SKILL.md，删除不再用的 skill。

## 4. 功能需求

### F1 查 — 浏览与搜索（P0）
- **三栏布局**（`NavigationSplitView`）：
  - 侧边栏：来源筛选 —「全部 / Claude Code / Codex」，各项带 skill 数量徽标。
  - 中栏：skill 列表。每行显示：名称、description 摘要（1–2 行）、来源徽标（当仅在一端安装时）、目录大小、修改时间。支持按名称/修改时间排序。
  - 详情栏：见 F2。
- **搜索**：顶部搜索框，对 `name` + `description` + 文件夹名做即时模糊过滤。
- **同名合并视图**：同名 skill 在两端都存在时，列表合并为一行，用双徽标标识「已双端安装」；详情页可分别查看/操作两端副本。
- **加载方式**：启动时扫描两个目录，解析各 `SKILL.md` 的 frontmatter（容错：缺 frontmatter / 解析失败的 skill 仍显示，标记「元数据缺失」）。目录变更用 FSEvents / `DispatchSource` 监听自动刷新，另提供手动刷新按钮。

### F2 详情与编辑（P0）
- 详情页上半部：元信息卡片（name、description、来源、路径、大小、修改时间、文件清单树）。
- 下半部：**SKILL.md 预览（渲染 Markdown）↔ 编辑模式切换**。内置简单编辑器：等宽字体纯文本编辑 + 保存（⌘S），保存前对 frontmatter 做 YAML 合法性校验，非法时警告但允许强制保存。
- 快捷操作：在 Finder 中显示、用默认编辑器打开、复制路径。

### F3 增 — 四种方式（P0/P1）
所有安装动作都先选择目标：**Claude Code / Codex / 两者**。

1. **导入本地文件夹 / zip（P0）**：文件选择器或拖拽到窗口。zip 自动解压；自动识别 skill 根（含 `SKILL.md` 的目录，支持 zip 内嵌套一层）。整目录拷贝到目标 skills 目录。
2. **新建空白模板（P0）**：表单填 name（校验：小写字母数字连字符、不与现有重名）+ description，生成 `SKILL.md` 骨架（frontmatter + 标题 + 占位章节），创建后直接进入编辑模式。
3. **跨工具复制（P0）**：详情页 / 列表右键菜单「复制到 Codex / 复制到 Claude Code」，整目录拷贝。目标已存在同名时弹确认（覆盖 / 取消）。
4. **从 GitHub URL 安装（P1）**：粘贴仓库 URL 或仓库内子目录 URL（如 `https://github.com/org/repo/tree/main/skills/foo`）。实现：GitHub codeload 下载 zipball → 解压到临时目录 → 定位含 `SKILL.md` 的目录（多个时列出让用户勾选）→ 拷贝安装。仅支持公开仓库；网络错误 / 找不到 SKILL.md 时给出明确提示。

- 冲突策略统一：目标已有同名 skill ⇒ 确认对话框（覆盖 / 取消），覆盖前将旧版本移入废纸篓。

### F4 删（P0）
- 列表右键 / 详情页按钮 / ⌫ 快捷键删除，需确认对话框（显示 skill 名与目标路径）。
- **删除 = 移入系统废纸篓**（`NSWorkspace.recycle`），可恢复，不做永久删除。
- 双端安装的 skill：删除时让用户选择删哪一端或两端。

## 5. 界面设计原则

- 原生 SwiftUI 三栏结构，遵循 macOS HIG；系统强调色、SF Symbols 图标、自动适配浅色/深色模式。
- 无多余装饰：主界面只有 侧边栏 + 列表 + 详情 + 工具栏（添加「+」下拉菜单、搜索框、刷新）。
- 空状态友好：无 skill 时显示引导插画文案 +「新建 / 导入」入口；支持全窗口拖拽导入。
- 危险操作（删除、覆盖）永远有确认；操作结果用非阻塞 toast/横幅反馈。

## 6. 技术方案要点

- **技术栈**：Swift 5.9+ / SwiftUI，目标 macOS 14+；Xcode 工程，无第三方依赖优先（Markdown 渲染可用 `AttributedString(markdown:)` 起步，v1.1 视效果换 swift-markdown-ui；YAML frontmatter 用自写轻量解析器——只需取顶部 `---` 块内的 `name:`/`description:` 键，无需完整 YAML 库）。
- **沙盒**：**关闭 App Sandbox**（个人直发使用，需自由读写 `~/.claude` / `~/.codex` 两个隐藏目录；若未来上架 App Store 再改造为 security-scoped bookmarks）。
- **架构**：`SkillStore`（ObservableObject）持有扫描结果；`SkillScanner`（目录扫描 + frontmatter 解析）；`SkillInstaller`（导入/新建/复制/GitHub 安装，统一走"临时目录准备 → 原子移动"流程）；`Tool` 枚举（claudeCode / codex）抽象路径，便于未来扩展第三方工具。
- 目录路径可在设置中自定义覆盖（默认取上表路径），应对非标准安装。

## 7. 里程碑

- **M1（MVP）**：F1 浏览/搜索 + F2 只读预览 + F4 删除 + F3.1 本地导入 —— 可用的"增删查"。
- **M2**：F3.2 新建模板 + F3.3 跨工具复制 + F2 内置编辑器。
- **M3**：F3.4 GitHub 安装 + 目录监听自动刷新 + 打磨（空状态、拖拽、快捷键）。

## 8. 风险与对策

| 风险 | 对策 |
|---|---|
| SKILL.md frontmatter 格式不规范（缺失/非法 YAML） | 容错展示 + 标记，不因单个坏文件影响整体列表 |
| GitHub 下载受网络/私有仓库限制 | 仅支持公开仓库，失败给明确错误；提供"手动下载后用本地导入"兜底 |
| 误删 | 只移废纸篓，永不硬删 |
| 未来 Codex/Claude Code 改变 skill 目录约定 | 路径可配置 + `Tool` 抽象层隔离 |

## 9. 验证方式

1. `xcodebuild build` 编译通过后启动 App，确认列表正确显示本机现有 skill（Claude Code 端 1 个：`gpt-image-2-style-library`；Codex 端 3 个：`guizang-ppt-skill`、`rescue-bad-photo`、`storage-analyzer`）。
2. 在临时目录造一个测试 skill → 导入 → 列表出现 → 跨工具复制 → 两端目录确认 → 删除 → 确认进入废纸篓。
3. 编辑某测试 skill 的 SKILL.md 保存，`cat` 确认写入且 frontmatter 完好。
4. 破坏性用例：导入无 SKILL.md 的文件夹（应报错拒绝）、同名覆盖（应弹确认）、frontmatter 缺失的 skill（应容错显示）。
