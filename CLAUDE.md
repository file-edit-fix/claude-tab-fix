# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概览

`claude-tab-fix` 是一个 Claude Code hook 二进制，拦截 Read/Edit/Bash/Write 工具调用，解决 tab 缩进文件中的编辑问题。整个项目是单文件 Go CLI（`main.go` + `main_test.go`），无外部依赖。

## 架构

```
main.go（单文件，~418 行）
├── 数据结构: hookInput, editInput, bashInput, readInput, hookOutput, indentStyle
├── 核心算法: detectIndent → reindent → fuzzyFindBlock (三级缩进修正)
├── Hook 处理:
│   ├── handleEdit    — PreToolUse: 检测缩进 → 重缩进 → 精确/模糊匹配 → exit 2 反馈
│   ├── handleBashOrWrite — PreToolUse: 警告 (context note, 不阻塞)
│   └── handleRead    — PostToolUse: 注入 tab 分隔符提示
└── main() — stdin JSON 解码 → 按 tool_name 分发
```

**关键设计决策：**
- **Exit 2 机制** — 不通过 `updatedInput` 返回修正字符串，而是 exit 2 + stderr 反馈。Claude Code 将 stderr 作为错误信息返回给模型，模型据此重试 Edit，比 `updatedInput` 更可靠（Claude Code 在应用 hook 输出前会预校验 old_string）
- **模糊匹配** — `fuzzyFindBlock` 使用行级 LCS 相似度，当缩进修正后 old_string 仍不精确匹配时，滑动窗口找最佳匹配块（阈值：≥85% 的行 ≥0.85 相似度后取平均分最高者）
- **无外部依赖** — 仅使用 Go 标准库

## 命令速查

```bash
go build -o claude-tab-fix .          # 构建
make build                            # 同上（含版本注入）
make fmt                              # gofmt -w
make install                          # go install
make release                          # goreleaser release --clean
make release-snapshot                 # 本地测试发布

# 运行全部测试
go test ./...

# 运行单个测试
go test -v -run TestGolden -count=1
go test -v -run TestIntegration_DeepIndentSpaceToTab -count=1
go test -v -run TestDetectIndent_Tabs -count=1

# 模糊匹配测试
go test -v -run TestFuzzyFindBlock -count=1
go test -v -run TestLineSimilarity -count=1

# 查看覆盖率
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out
```

## 退出码

| 代码 | 含义 | Hook |
|------|------|------|
| `0` | Pass-through — 放行，不修改 | Edit / Bash / Write / Read |
| `2` | Blocked with feedback — stderr 作为错误返回给模型，模型重试 | Edit 缩进不匹配时 |

## 测试架构

测试通过 `runHook()` 辅助函数模拟 stdin JSON pipe 调用 `main()`，捕获 exit code 和 stderr：

- **单元测试** — `TestDetectIndent_*`、`TestReindent_*`、`TestLineSimilarity_*`、`TestFuzzyFindBlock_*`
- **集成测试** — `TestIntegration_*`：创建临时文件 → `makeInput()` → `runHook()` → `assertBlocked()` / `assertPassThrough()`
- **Golden 测试** — `TestGolden`：8 个 testdata fixture 文件，9 组用例覆盖 tab 和空格缩进
- **Bash/Write 告警测试** — `TestBash_*`、`TestWrite_*`：验证 `additionalContext` 警告内容

测试辅助函数：
- `runHook()` — 重定向 stdin/stdout/stderr 后调用 `main()`，返回结构化结果
- `makeInput()` — 构建 hook input JSON
- `assertBlocked()` / `assertPassThrough()` — 断言 exit code 和 stderr 内容
- `extractFeedbackOldString()` — 从 stderr 反馈消息中提取修正后的 old_string

## 测试夹具（testdata/）

| 文件 | 缩进 | 用途 |
|------|------|------|
| `deep_nested.go` | Tab | 深层嵌套 Go 代码，测试深度缩进规范化 |
| `component.templ` | Tab | templ 组件，测试 quote drift 模糊匹配 |
| `tab_indented.go` | Tab | 基础 tab 缩进 |
| `test.templ` | Tab | 更多 templ 场景 |
| `service.ts` | 空格 | 空格缩进文件，验证 hook 不干预 |
| `pipeline.py` | 空格 | Python 空格缩进 |
| `layout.html` | 空格 | HTML 空格缩进 |
| `ci.yaml` | 空格 | YAML 空格缩进 |

## 发布与版本

- **版本文件** — `VERSION` 记录两个版本号：`app: X.Y.Z`（应用版本）、`plugin: X.Y.Z`（插件版本）
- **GoReleaser** — `.goreleaser.yaml` 配置跨平台构建（linux/darwin/windows × amd64/arm64），发布时归档 README、CLAUDE.md、FLOW.md、LICENCE、PRIVACY.md、logo.png
- **GitHub Actions** — `.github/workflows/release.yml`：tag push `v*` 触发，先跑测试再用 goreleaser 发布
- **发布命令** — `make release`（生产）或 `make release-snapshot`（本地测试）；version 通过 `-ldflags -X main.version={{.Version}}` 注入

## 插件注册与全局 hooks

`.claude-plugin/` 目录是插件注册基础：
- `plugin.json` — 元数据（名称 `claude-tab-fix`、版本 `1.0.3`、描述、作者 WithHolm、仓库 URL）
- 用户通过 `/plugin install claude-tab-fix@WithHolm/claude-tab-fix` 注册插件

**插件系统会从 `hooks/hooks.json` 自动加载 hooks**，当插件启用时，hooks 全局生效（包括所有项目及 worktrees）。不需要手动配置全局 `settings.json`。

### 插件安装

```bash
go install github.com/WithHolm/claude-tab-fix@latest
/plugin marketplace add WithHolm/claude-tab-fix
/plugin install claude-tab-fix@WithHolm/claude-tab-fix
```

### 更新插件缓存

如果 `hooks/hooks.json` 有更新，需要重新安装插件或手动更新缓存：

```bash
# 方式一：重新安装
/plugin uninstall claude-tab-fix@claude-tab-fix
/plugin install claude-tab-fix@WithHolm/claude-tab-fix

# 方式二：手动更新缓存（适用于 fork）
# 更新 ~/.claude/plugins/cache/claude-tab-fix/claude-tab-fix/<version>/hooks/hooks.json
```

### 使用 fork 安装

如果从 fork 安装，需要先添加 fork 作为 marketplace：

```bash
/plugin marketplace add your-org/claude-tab-fix
/plugin install claude-tab-fix@your-org/claude-tab-fix
```

### `hooks/hooks.json` 配置

当前 hooks 配置覆盖以下工具：

- **PreToolUse/Edit** — 缩进不匹配时自动修正（exit 2）
- **PreToolUse/Bash** — 对 tab 缩进文件发出警告
- **PreToolUse/Write** — 对 tab 缩进文件发出警告
- **PostToolUse/Read** — 注入 tab 分隔符提示

### 回退方案：手动全局配置

如果插件系统不可用（如 Claude Code 版本过低），可以使用安装脚本将 hooks 添加到 `~/.claude/settings.json`：

```bash
./scripts/install-global.sh     # Linux/macOS
.\scripts\install-global.ps1    # Windows (PowerShell)
```

## 文件编辑规则

本项目（以及使用此 hook 的任何项目）包含 tab 缩进文件。

**对现有文件做局部修改时，始终使用 `Edit` 工具。** 不要使用 `Bash`（`sed`/`awk`/`perl -i` 等）或 `Write` 工具修改已有文件。原因：`Edit` 被 claude-tab-fix 的 PreToolUse hook 拦截，能自动检测并修正缩进不匹配。Bash 和 Write 绕过此 hook，会静默引入混合缩进或导致编辑失败。

Hook 在 Bash/Write 操作 tab 缩进文件时会发出警告，但无法自动修正这些操作。