# 公众号文章草稿：Skill Manager v2.0

> 使用说明：
> - 标题三选一（或自行组合）
> - 【截图：…】处替换为实际截图（⌘⇧4 + 空格键截带阴影的窗口图效果最好）
> - 「彩蛋」一节如果不想暴露开发方式，可整段删除，不影响文章完整性

---

## 标题备选

1. 我把 Claude Code 和 Codex 的 Skill 管理做成了 Mac App，今天开源（附下载）
2. Skill 装了一堆记不住、两边不同步、写完不触发？这个开源 Mac App 全管了
3. 从「增删查」到发现、体检、多机同步：一个 Skill 工作台的诞生

---

## 正文

如果你同时在用 Claude Code 和 Codex，大概率遇到过和我一样的问题。

Skill（技能）是现在 AI 编程工具最好用的扩展方式：一个文件夹、一份 `SKILL.md`，就能教会 AI 一套新本事——做 PPT、修图、分析磁盘、跑发布流程……社区里的优质 skill 越来越多。

但管理它们的体验，还停留在石器时代：

- 装了哪些？`ls ~/.claude/skills` 和 `ls ~/.codex/skills` 各看一遍
- 两边想共用？手动 `cp -r`
- 看到好 skill？clone、找目录、再拷进去
- 自己写的 skill 死活不自动触发？盯着 frontmatter 猜半天
- 换了台电脑？全部重来

于是我做了 **Skill Manager**——一个 macOS 原生 App。三个月前它还只是个"增删查"小工具，现在迭代到 v2.0，已经长成一个完整的 **skill 工作台**：发现、管理、写好、同步，一站式。

【截图：App 主界面三栏视图】

### 一个窗口，管住所有 skill

不只是 Claude Code 和 Codex：

- **任何遵循 `目录/skill 名/SKILL.md` 约定的工具**都能接入——内置 Gemini CLI、OpenCode 预设，也可以在设置里添加自定义工具
- **项目级 skill**：把项目文件夹拖进窗口，它的 `.claude/skills` 就进了侧边栏「项目」分组，项目和全局之间一键"提升/下沉"
- **Claude 插件自带的 skill** 也扫出来只读展示，看中了就复制成自己的
- 同名 skill 跨来源合并成一行，双徽标一目了然；目录一变列表自动刷新
- **菜单栏常驻**：点一下拼图图标即搜，选中直接跳回主窗口

### 装 skill，五个入口

1. **发现页**：内置精选索引（Anthropic 官方 skills、Superpowers 等），浏览、搜索、一键安装——索引托管在仓库里，欢迎 PR 收录你的 skill
2. **GitHub 链接**：粘贴仓库或子目录链接直接装，私有仓库配个 Token（存钥匙串）也能装
3. **本地文件夹 / zip**：拖进窗口就行
4. **新建模板**：基础 / 参考文档型 / 脚本型三种骨架，秒建规范 skill
5. **跨工具复制**：Claude Code 里好用的，右键复制到 Codex（或任何工具、任何项目）

【截图：发现页】

所有安装都能选目标、都有同名冲突确认，被覆盖的旧版本先进废纸篓。

### 不止管理，还帮你把 skill 写好

这是 v1.5 之后我自己最常用的部分：

- **检查（Skill Lint）**：一键体检——frontmatter 缺不缺、name 和目录名一不一致、description 是不是太短了触发不了、正文里引用的文件到底存不存在……改一行，问题实时消失
- **编辑器**：Markdown / frontmatter 语法高亮，name 和 description 直接表单化编辑，不用再数缩进
- **编辑历史**：每次保存前自动快照（每个 skill 留 20 份），改崩了随时回滚
- **用法页**：每个 skill 的斜杠命令、自然语言调用模板、示例提示词，点一下就复制——"装了但忘了怎么用"这件事从此消失

【截图：检查标签，展示几条 lint 结果】

### 保持最新，多机同步

- 从 GitHub 装的 skill 会自动记录**来源和版本**，详情页一键「检查更新」，上游有新 commit 就一键升级
- **多机同步**：填一个你自己的 git 仓库地址，这台推送、那台拉取，skill 就在多台电脑之间同步了——**没有任何服务端**，数据只经过你自己的仓库
- **分享**：一键导出「zip + 说明文档」，说明里自带 `skillmanager://install?url=…` 深链，对方装了 Skill Manager 就能点开即装

【截图：设置页多机同步区】

### 一些底线

- 原生 SwiftUI，整个 App 几 MB，秒开，中英文双语，自动适配深色模式
- 删除永远只进废纸篓，绝不硬删
- Token 存系统钥匙串，skill 数据不离开本机（除了你主动的 GitHub 安装和 git 同步）
- MIT 开源，42 个单元测试，每次发版 CI 全绿才出包

---

### 彩蛋：这个 App 是怎么长大的

坦白说：从 PRD 到 v2.0 的每一行代码、每一个测试、连 CI/CD 流水线和这篇文章，都是我和 Claude Code 结对完成的。

节奏大概是：先让它写 PRD，我拍板技术选型和功能边界；然后 v1.0 一个下午出可用版本；之后每说一句"继续迭代下一版"，它就按路线图交付一个版本——工具可配置化、项目级支持、发现与更新、编辑质量工具、分享与同步，六个版本，一路发到 GitHub Release。

更有意思的是，我这台 Mac **连 Xcode 都没装**，只有 Command Line Tools。纯 Swift Package Manager 工程，`swift build` 编译，一个脚本打包成 .app。

用 AI 编程工具，做了一个管理 AI 编程工具的工具，然后用它管理教 AI 干活的技能。这大概就是 2026 年写代码的样子。

---

### 获取方式

项目已开源：**https://github.com/singme163/skill-manager**

**直接下载**（推荐）：[Releases 页面](https://github.com/singme163/skill-manager/releases/latest) 下载 `SkillManager.dmg`，拖进 Applications 即可。首次打开如被 Gatekeeper 拦截，在 App 上**右键 → 打开**（目前是 ad-hoc 签名，公证在路线图上）。

**从源码构建**（有 Command Line Tools 就行）：

```
git clone https://github.com/singme163/skill-manager
cd skill-manager
./Scripts/make-app.sh
open dist/SkillManager.app
```

要求 macOS 14+。

如果你也在用 AI 编程工具，欢迎试试。觉得有用的话给个 Star；写了好 skill 想被更多人看到，欢迎 PR 到 `index/skills.json` 进发现页。

---

*你平时是怎么管理 skill 的？评论区聊聊。*
