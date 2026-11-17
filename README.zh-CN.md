# Unreal Engine Linux + VS Code 环境搭建（Agent Skill）

简体中文 | [English](README.md)

一个教 AI 编程助手在 Linux 上把 Unreal Engine 5 工程**跑起来 / 修好**的 skill：
声明平台支持、用命令行构建、给 VS Code 配好 clangd、让编辑器通过 MCP 被 agent
驱动、以及让 PIE 正确接管鼠标键盘（即使屏幕上挂着全屏 HUD）。

这里没有任何内容是为某个特定工程写的。经验来自真实的 UE 5.8 项目，但每个路径、
模块名、任务名都是占位符，按你的工程填一次即可。

## 覆盖内容

| 主题 | 位置 |
| --- | --- |
| 固定引擎路径、命令行构建、带显示环境启动编辑器 | `SKILL.md` 第 1–4 步 |
| VS Code：扩展、`settings.json`、`tasks.json`、`scripts/ue.sh` | [references/vscode-linux.md](references/vscode-linux.md) |
| clangd：编译数据库、过期检测、`.clangd`、误报处理 | [references/vscode-linux.md](references/vscode-linux.md) |
| UE MCP 服务 + 客户端配置 + 握手验证 | `SKILL.md` 第 7 步 |
| PIE 鼠标/键盘捕获、HUD 的 Slate 穿透 | [references/pie-input-and-hud.md](references/pie-input-and-hud.md) |
| `.uproject` 平台声明、把仅 Windows 的原生插件移植到 Linux | [references/plugins-and-vcs.md](references/plugins-and-vcs.md) |
| 忽略规则、本机专属文件、可选 `.props` 覆盖 | [references/plugins-and-vcs.md](references/plugins-and-vcs.md) |

## 安装

直接 clone 进 skills 目录即可，仓库根目录本身就是 skill 目录，不需要再挪文件：

```bash
# Codex
git clone https://github.com/Aceared0829/ue-project-setup-skill.git \
  ~/.codex/skills/ue-project-setup

# Claude Code
git clone https://github.com/Aceared0829/ue-project-setup-skill.git \
  ~/.claude/skills/ue-project-setup
```

Agent 先读 `SKILL.md`，只有某一步需要细节时才加载对应 reference，所以这些长文档
在没用到时不占上下文。

## 目录结构

```
SKILL.md                        # 有顺序的清单：构建 -> VS Code -> agent -> 输入
references/
  vscode-linux.md               # clangd、编译数据库、tasks.json、ue.sh
  pie-input-and-hud.md          # 症状 -> 原因 -> 修法，Slate 捕获代码
  plugins-and-vcs.md            # 平台声明、原生插件移植、忽略规则
```

## 说明

- 以 UE 5.8 为基准编写，除个别步骤特别注明外，5.3+ 均适用。MCP 部分需要 5.6+，
  插件位于 `Engine/Plugins/Experimental/ModelContextProtocol`。
- 刻意写得“有主张”：明确告诉 agent **不要**做什么（删掉 clangd 报未使用的 include、
  提交引擎绝对路径、用抛异常的方式做平台守卫），因为每一个都值一次完整的调试。
- 验证本身就是步骤的一部分：构建命令、curl 握手、打印 `HasMouseCapture`。
  “看起来没问题”不算一步。

## 许可证

MIT —— 见 [LICENSE](LICENSE)。
