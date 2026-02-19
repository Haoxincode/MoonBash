# AWK 解释器 AST 化改造记录（2026-02-19）

## 背景

当前 AWK 解释器原实现以字符串切分 + 逐条匹配执行为主，维护成本较高，控制流分支（`if` / `for` / `for in`）难以稳定扩展。

## 本次改造范围

本次完成 **语句级 AST（Statement AST）** 迁移：

- 新增 `AwkStmt` 语句节点：`Simple` / `If` / `For` / `ForIn`
- 新增递归解析入口：`awk_parse_action_ast`
- `cmd_awk` 主执行链改为：
  - 先解析语句 AST
  - 再按 AST 解释执行控制流
- 用户函数体执行（`awk_execute_function_body`）同样切换到语句 AST 分发

为确保行为稳定：

- 非控制流语句（表达式、赋值、print/printf、内建调用等）仍通过 legacy 分支执行
- 原行为兼容优先，控制流从字符串走向结构化，叶子语句暂不一次性重写

## 新增/改动文件

- 新增：`src/lib/commands/awk_ast.mbt`
- 改动：`src/lib/commands/awk_action.mbt`
- 改动：`src/lib/commands/awk_eval.mbt`

## 验证结果

- `cd src && moon check --target js` 通过
- `npx vitest run tests/comparison/awk.comparison.test.ts` 通过
- `npx vitest run tests/spec/awk/awk-spec.test.ts` 通过

## 后续建议（Phase 2）

1. 表达式层从字符串递归求值迁移到 Pratt/precedence AST。
2. 将 `Simple` 叶子节点拆分为更细粒度语句节点（如 `Print`/`Assign`/`Getline`）。
3. 最终移除 `*_legacy` 路径，统一执行栈。
