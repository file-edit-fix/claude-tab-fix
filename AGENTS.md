# claude-tab-fix — AGENTS.md

单文件 Go CLI，作为 Claude Code hook 拦截 Read/Edit/Bash/Write 工具调用，解决 tab 缩进文件的编辑问题。

## Tech Stack

Go 1.x（仅标准库，无外部依赖）· Claude Code hook 协议（stdin JSON pipe）

## Dev Environment Tips

```bash
# 构建
go build -o claude-tab-fix .
make build              # 同上（含版本注入）

# 调试（模拟 hook 输入）
echo '{"tool_name":"Edit",...}' | ./claude-tab-fix
```

## Build & Test

| 命令 | 用途 |
|------|------|
| `go test ./...` | 全部测试 |
| `go test -v -run TestGolden -count=1` | 缩进匹配 golden 测试 |
| `go test -v -run TestIntegration_* -count=1` | 集成测试 |
| `go test -v -run TestFuzzyFindBlock -count=1` | 模糊匹配测试 |
| `go test -coverprofile=coverage.out ./...` | 覆盖率 |
| `go vet ./...` | 静态检查 |

## Project Structure

```
claude-tab-fix/
├── main.go                        ← 单文件，~418 行，包含所有逻辑
│   ├── 数据结构: hookInput, editInput, hookOutput, indentStyle
│   ├── 核心算法: detectIndent → reindent → fuzzyFindBlock
│   └── Hook 处理: handleEdit / handleBashOrWrite / handleRead
├── main_test.go                   ← 所有测试
├── testdata/                      ← 8 个 fixture 文件（tab + 空格缩进）
├── FLOW.md                        ← 完整决策流程图
├── .claude-plugin/
│   ├── plugin.json                ← 插件元数据
│   └── hooks/hooks.json           ← 4 个 hook 定义
├── Makefile                       ← 构建/发布/格式化
└── .goreleaser.yaml               ← 跨平台发布配置
```

## Core Algorithm

```
detectIndent(fileContent) → indentStyle (tabs | spaces)
reindent(text, from, to)  → reindented text (tab↔space 转换)
fuzzyFindBlock(...)       → best match block (LCS 相似度，阈值 85%)
```

## Exit Codes

| 代码 | 含义 | Hook |
|------|------|------|
| `0` | Pass-through — 放行 | 全部 |
| `2` | Blocked with feedback — stderr 返回给模型重试 | Edit 缩进不匹配 |

**关键设计：** 不通过 `updatedInput` 返回修正字符串，而是 exit 2 + stderr 反馈。Claude Code 将 stderr 作为错误信息返回给模型，模型据此重试 Edit。比 `updatedInput` 更可靠——Claude Code 在应用 hook 输出前会预校验 old_string。

## Boundaries

- ✅ **Always**: 修改核心算法（detectIndent/reindent/fuzzyFindBlock）、添加测试、修改 hook 处理逻辑
- ⚠️ **Ask first**: 修改退出码语义、改变 hook 注册方式、发布新版本
- 🚫 **Never**: 移除 Exit 2 机制改用 `updatedInput`（会破坏缩进修正可靠性）、修改 `.claude-plugin/hooks/hooks.json` 的 hook matcher 规则（影响全局所有项目）

## Reference

详细测试架构和 fixture 文件说明见 `CLAUDE.md`，完整决策流程图见 `FLOW.md`。
