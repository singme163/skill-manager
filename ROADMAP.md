# Skill Manager 产品化迭代计划（v1.1 → v2.0）

## Context

v1.0 已完成并可用：SwiftUI 原生三栏 App，管理 Claude Code / Codex 两端 skill 的增删查 + 编辑 + 用法指引，18 个单元测试全过，有图标和打包脚本（`Scripts/make-app.sh`）。但它目前只是"能用的个人工具"：未开源、无签名公证（别人下载会被 Gatekeeper 拦截）、无自动更新、工具列表写死两个、不支持项目级 skills。

产品化方向（已确认）：**开源 + 直发分发**（签名公证 + 自动更新）、**支持范围全面扩展**（项目级 skills、更多 AI 工具可配置、插件 skill 只读展示）、**不商业化**，以口碑和影响力为迭代导向。

节奏建议：每个版本 1–2 周可交付，先发布再扩展——让公众号文章发出时就有可下载的 Release。

---

## v1.1 发布就绪（最高优先级，公众号发文前完成）

目标：任何读者点开链接，3 分钟内装上能跑的 App。

| 事项 | 说明 |
|---|---|
| 开源仓库 | `git init`，MIT LICENSE，README 补英文简介与截图，`.gitignore`（.build/dist/Tools/build） |
| 签名 + 公证 | 需要 Apple Developer 账号（$99/年，需用户开通）；`make-app.sh` 扩展：Developer ID 签名 → `notarytool` 公证 → 装订；无账号时降级为 ad-hoc 签名并在 README 写明「右键打开」绕过 Gatekeeper |
| dmg 打包 | `Scripts/make-dmg.sh`：`hdiutil` 生成带 Applications 快捷方式的 dmg |
| 自动更新 | 集成 Sparkle 2（首个第三方依赖，SPM 引入）；appcast.xml 托管 GitHub Pages；菜单加「检查更新」 |
| CI | GitHub Actions：push 跑 build + `Scripts/test.sh` 等效流程；打 tag 自动构建 Release 产物 |
| 首启体验 | 首次启动检测两个 skills 目录：不存在时给引导页（解释 skill 是什么 + 指向设置）；「关于」窗口、帮助菜单链接仓库 |
| 本地化 | String Catalog 抽离硬编码中文，提供 en/zh——开源面向国际受众 |

关键文件：`Scripts/make-app.sh`（扩展）、新增 `Scripts/make-dmg.sh`、`.github/workflows/`、`Package.swift`（Sparkle 依赖）、各 View 的文案抽离。

## v1.2 工具可配置化 + 插件只读展示

目标：从"Claude Code + Codex 专用"变成"任何遵循 SKILL.md 目录约定的工具都能管"。

- **核心重构**：`Tool` 枚举 → 数据驱动的 `ToolConfig`（id、名称、图标、目录、是否只读），内置预设 Claude Code / Codex / Gemini CLI / OpenCode，支持用户在设置中添加自定义工具（名称 + 目录）
  - 波及：`Tool.swift`（重写）、`SkillCopy.tool` 类型、`SkillStore` 扫描循环、侧边栏动态生成、`ToolTargetPicker`、`ToolBadge` 颜色分配
  - 现有 `SkillScanner.scan(directory:tool:)` 已按目录参数化，重构成本可控
- **插件 skill 只读展示**：扫描 `~/.claude/plugins/` 下插件自带的 skill，以只读来源展示（灰色徽标「插件」，禁用删除/编辑/覆盖），盘点视图完整化
- 同名合并逻辑从"两端"泛化为"N 端"（`Skill.merge` 已是通用实现，主要是 UI 徽标排布）

## v1.3 项目级 skills

目标：覆盖 `.claude/skills` 项目级目录这一真实使用场景。

- 项目登记：设置中添加项目目录（或把项目文件夹拖进窗口识别），持久化到 UserDefaults/JSON
- 侧边栏新增「项目」分组，每个项目一个节点；项目级 skill 支持与全局互相复制（"提升为全局 / 下沉到项目"）
- `DirectoryWatcher` 按登记目录动态增减
- 可选加分项：扫描 `~/.codex/projects` 或最近打开项目自动发现

## v1.4 发现与安装升级

目标：从"管理已有的"到"帮你找到好的"——口碑传播的核心功能。

- **发现页**：内置精选索引（awesome-claude-skills 类仓库的解析缓存），浏览 + 搜索 + 一键安装；索引数据托管在本仓库（JSON），社区可 PR 收录
- **来源追踪与更新检测**：安装时在 skill 目录写入 `.skillmanager.json`（来源 URL、commit/日期）；列表标记"上游有更新"，一键升级（复用覆盖安装流程）
- GitHub 安装增强：支持 token 访问私有仓库（钥匙串存储）
- 批量操作：列表多选 → 批量删除 / 复制到另一工具 / 导出 zip

## v1.5 编辑与质量工具

目标：不只是管理 skill，还帮你写出好 skill。

- **Skill Lint**：规则集（frontmatter 必填项、name 与目录一致、description 长度与触发词质量、引用的相对路径文件是否存在），详情页显示检查结果
- 编辑器升级：Markdown + YAML 语法高亮（可评估 CodeEditor 类轻量库或自绘 NSTextView 高亮），frontmatter 表单化编辑（name/description 用表单，正文用编辑器）
- 编辑历史：保存前自动快照到 App Support，提供"恢复到之前版本"
- 模板库：内置多种模板（工具型 / 参考文档型 / 带脚本型）

## v2.0 生态与分享

- **分享**：skill 一键导出 zip + 自动生成分享说明；注册 `skillmanager://install?url=…` URL scheme，网页可放「安装到 Skill Manager」按钮
- **多机同步**：基于 iCloud Drive 或用户自己的 git 仓库同步 skills 目录（免费方案，不引入服务端）
- 菜单栏常驻模式：快速搜索、最近 skill、一键打开主窗口

## 横切事项（每个版本都投入）

- 测试：核心逻辑改动同步补 Swift Testing 用例（跑 `Scripts/test.sh`）
- 性能：skill 数量大时扫描/体积统计做缓存与增量
- 打磨：深浅色、键盘导航、VoiceOver 标签、空状态文案

## 成功度量（口碑导向）

- GitHub stars / Release 下载数 / issue 与 PR 活跃度
- 公众号文章 → 仓库的转化（README 里放公众号入口形成闭环）
- 「发现页收录 skill 数」作为 v1.4 后的生态指标

## 风险与依赖

| 风险 | 对策 |
|---|---|
| Apple Developer 账号未开通 | v1.1 先按 ad-hoc + README 引导发布，公证后续补 |
| Sparkle 引入首个三方依赖 | 锁定主版本；它是 macOS 直发事实标准，风险低 |
| 各工具 skill 目录约定变化 | v1.2 的 ToolConfig 数据驱动化本身就是隔离层 |
| 发现页索引维护成本 | 索引 JSON 放仓库靠社区 PR，App 只读消费 |

## 验证方式（每版通用）

1. `swift build` + `Scripts/test.sh` 全绿
2. `Scripts/make-app.sh` 打包后真机启动冒烟：列表、安装、删除、编辑主链路各走一遍
3. v1.1 额外：干净用户环境（新建 macOS 用户）下载 dmg 安装验证 Gatekeeper 流程；Sparkle 从旧版本升级验证
4. v1.2/1.3 额外：自定义工具目录、项目目录的增删改在设置中操作后列表实时正确
