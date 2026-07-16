# Skill 发现索引

`skills.json` 是 Skill Manager App 内「发现」页的数据源（App 从 main 分支的 raw 地址实时读取，离线时回退到内置副本）。

## 收录一个 skill / skill 集合

提交 PR 向 `skills.json` 数组追加一个条目：

```json
{
  "name": "显示名称",
  "description": "一两句话说明它做什么、什么时候用",
  "author": "作者或组织",
  "url": "https://github.com/org/repo 或 https://github.com/org/repo/tree/main/skills/foo",
  "tags": ["可选", "标签"]
}
```

要求：

- `url` 必须是**公开** GitHub 仓库（或仓库子目录）链接，且其中至少包含一个带 `SKILL.md` 的 skill 目录
- 描述客观准确，不夸大
- 不收录含恶意行为（外传数据、破坏性命令等）的 skill
