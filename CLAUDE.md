@AGENTS.md

## Claude Code 特有配置

### 插件注册

通过 skills-dir junction 全局安装，hooks 自动生效：

```
D:\Users\86150\.claude\skills\claude-tab-fix → 本仓库（junction）
```

### 手动注册（备选）

在 `.claude/settings.json` 中配置 hooks：

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Edit",
      "hooks": [{ "type": "command", "command": "claude-tab-fix" }]
    }]
  }
}
```

### 文件编辑规则

**对现有文件做局部修改时，始终使用 `Edit` 工具。** 不要使用 `Bash`（`sed`/`awk`/`perl -i` 等）或 `Write` 工具修改已有文件。原因：`Edit` 被 claude-tab-fix 的 PreToolUse hook 拦截，能自动检测并修正缩进不匹配。Bash 和 Write 绕过此 hook，会静默引入混合缩进或导致编辑失败。
