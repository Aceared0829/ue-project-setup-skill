# UE Project Setup（Agent Skill）

简体中文 | [English](README.md)

一个 agent skill：把 Unreal Engine 工程整理到 AI 编程助手**真的能用**的状态 ——
运行中的编辑器能通过 MCP 被访问、PIE 正确接管鼠标与键盘、全屏 HUD 不再吞掉
Slate 输入、clangd / IDE 不再被误报淹没。

内容来自一个真实的 UE 5.8 Linux 工程（含 Windows 相关说明）。每一步都在引擎上
实测验证过，而不是猜的 —— 包括那些“看起来像引擎 bug 其实不是”的部分。

## 覆盖内容

| 领域 | 要点 |
| --- | --- |
| UE MCP 服务 | 启用 `ModelContextProtocol`、8000 端口自启动、VS Code / Codex / Claude 的客户端配置、用 curl 握手验证 |
| PIE 输入 | `FInputModeGameOnly`、Slate 鼠标捕获 reply、内嵌 PIE 的原生窗口激活、捕获重试阶梯、`UseHighPrecisionMouseMovement` |
| HUD 穿透 | widget 本身 **和** `TakeWidget()` 结果都要 `HitTestInvisible`；为什么 RmlUi `.rcss` 里的 `pointer-events: none` 不够 |
| clangd | `GenerateClangDatabase` 工具模式、用文件清单（而非 mtime）判断库是否过期、为 UE umbrella header 关闭 `clangd/unused-includes` 误报 |
| 构建 / 仓库卫生 | Linux 上的 RmlUi/Slate 桥、`.uproject` 的 `PlatformAllowList`、`.gitignore` 该放什么、为什么可选的 `.props` import 属于本机覆盖 |

## 安装

直接 clone 进 skills 目录 —— 仓库根目录本身就是 skill 目录：

```bash
# Codex
git clone https://github.com/Aceared0829/ue-project-setup-skill.git \
  ~/.codex/skills/ue-project-setup

# Claude Code
git clone https://github.com/Aceared0829/ue-project-setup-skill.git \
  ~/.claude/skills/ue-project-setup
```

Agent 先读 `SKILL.md`，需要细节时才按需加载 `references/*.md`，所以这些长文档
在没用到时不占上下文。

## 目录结构

```
SKILL.md                 # 有顺序的检查清单，入口
references/
  pie-input-and-hud.md   # 症状 -> 原因 -> 修法 表格 + Slate 捕获代码
  linux-toolchain.md     # RmlUi 桥、clangd、.uproject 平台声明、VCS 卫生
```

## 说明

- 默认面向 UE 5.8；大部分内容在 5.3+ 上无需改动即可适用。版本相关的部分会明确标注。
- 这个 skill 刻意写得“有主张”：它明确告诉 agent **不要**做什么（删 `CoreMinimal.h`、
  提交引擎绝对路径、用抛异常的方式做平台守卫），因为这些坑是实打实花了调试时间换来的。

## 许可证

MIT —— 见 [LICENSE](LICENSE)。
