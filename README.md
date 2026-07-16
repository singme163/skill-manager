# Skill Manager

macOS 原生（SwiftUI）的 skill 管理工具，统一管理本机 **Claude Code**（`~/.claude/skills/`）与 **Codex**（`~/.codex/skills/`）的 Agent Skill。

> **English**: Skill Manager is a native macOS (SwiftUI) app for managing Agent Skills across Claude Code and Codex — browse and search skills from both tools in one window, install from local folders / zip / GitHub repos, copy skills between tools with one click, edit SKILL.md with frontmatter validation, and delete safely to Trash. Requires macOS 14+. Build with `Scripts/make-app.sh` (Command Line Tools are enough, no Xcode needed).

产品需求见 [PRD.md](PRD.md)，产品化迭代计划见 [ROADMAP.md](ROADMAP.md)。基于 [MIT License](LICENSE) 开源。

## 功能

- **查**：三栏布局按来源筛选，按名称、描述即时搜索；同名 skill 跨工具合并显示；目录变更自动刷新
- **多工具**（v1.2）：工具列表数据驱动——内置 Claude Code / Codex / Gemini CLI / OpenCode 预设，也可在设置中添加任何遵循 `目录/skill 名/SKILL.md` 约定的自定义工具；Claude 插件缓存作为只读源展示，插件 skill 可一键复制为自己的 skill
- **增**：导入本地文件夹 / zip（支持拖拽到窗口）、新建规范模板、跨工具一键复制、从 GitHub 公开仓库链接安装
- **删**：确认后移入系统废纸篓（可恢复，永不硬删）；双端安装时可选删除哪一端
- **编辑**：SKILL.md Markdown 预览 + 内置编辑器（⌘S 保存，保存前校验 frontmatter）、文件清单、Finder / 默认编辑器快捷跳转
- **用法**：详情页「用法」标签展示自动触发说明（基于 description）、可复制的显式调用命令（`/skill-name`、自然语言提及）、示例提示词与安装位置

## 构建与运行

需要 macOS 14+ 与 Swift 6 工具链（Command Line Tools 即可，无需完整 Xcode）。

```sh
# 开发运行
swift run

# 单元测试（脚本会处理 CLT 下 Swift Testing 的框架路径）
Scripts/test.sh

# 打包成 .app（输出到 dist/SkillManager.app）
Scripts/make-app.sh
open dist/SkillManager.app

# 打包成 dmg（输出到 dist/SkillManager.dmg，用于分发）
Scripts/make-dmg.sh
```

> 注：当前构建产物为 ad-hoc 签名。从网上下载后首次打开若被 Gatekeeper 拦截，请在 App 上**右键 → 打开**，或在「系统设置 → 隐私与安全性」中允许。Developer ID 签名与公证在迭代计划中。

## 结构

```
Sources/SkillManagerCore/   核心逻辑（无 UI，可单测）
  Tool.swift                工具枚举与 skills 目录解析（支持设置覆盖）
  Skill.swift               SkillCopy / Skill（跨工具合并）模型
  FrontmatterParser.swift   轻量 YAML frontmatter 解析 + 模板生成 + 名称校验
  SkillScanner.swift        目录扫描、体积统计、文件清单
  SkillInstaller.swift      导入 / 新建 / 复制 / GitHub 安装（覆盖前移废纸篓）
  SkillStore.swift          应用状态（@MainActor ObservableObject）
  DirectoryWatcher.swift    目录变更监听（去抖）
Sources/SkillManager/       SwiftUI 界面（三栏 + sheet + 设置）
Tests/                      Swift Testing 单元测试
```

说明：App 未启用 Sandbox（需直接读写 `~/.claude` / `~/.codex`），适合个人直发使用；skills 目录路径可在「设置」中自定义覆盖。
