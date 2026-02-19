# AWK 解释器 AST 迁移记录（2026-02-19）

## 目标

把 AWK 执行链从「运行时字符串分发」迁移为「解析期结构化 + 运行时 AST 分发」，降低维护成本并减少循环内重复解析。

## 当前进度（已完成）

### 1. 语句层 AST 主干已落地

`AwkStmt` 已覆盖控制流与主要语句类型：

- 控制流：`If` / `For` / `ForIn` / `While`
- 流程控制：`Next` / `Exit` / `Return`
- 输出与 I/O：`Print` / `Printf` / `Getline` / `PipeGetline`
- 赋值相关：`AssignStmt` / `CompoundAssignStmt` / `FieldAssignStmt`
- 其他：`Delete` / `SystemStmt` / `SubstituteStmt` / `ExprStmt`

`Simple(String)` 已完全移除，`awk_execute_action_simple` 路径已删除。

### 2. 表达式层 AST 已成为统一入口

- `awk_eval_expr` 已统一为：`parse_expr_ast -> eval_expr_ast`
- 条件判断统一走 `awk_eval_condition_ast`
- `If/For/While` 条件都使用 `AwkExprAst`，不再在循环内重复字符串解析
- 函数调用参数已携带 AST（同时保留 raw 形态用于 `split/match` 等语义）

### 3. 执行器双路径同步

- 主 action 执行器：`awk_execute_action_ast_list` 全量按 `AwkStmt` 分发
- 函数体执行器：`awk_execute_function_statements` 同步按 `AwkStmt` 分发

## 本轮新增

- 新增 `While(AwkExprAst, Array[AwkStmt])` 语句节点
- 新增 `awk_parse_while_statement`
- 在语句合并阶段补齐 bare `while (...)` header 识别，保证与 `if/for` 一致的拼接行为
- 在 action/function 两条执行链新增 `While` 执行分支
- 将 `SubstituteStmt` 参数从字符串列表迁移为 `Array[AwkExprAst]`
- 将 `Print` / `Printf` 载荷迁移为 AST：格式串、参数、重定向目标均在解析期结构化
- 新增 `awk_render_print_output_ast` / `awk_eval_sub_pattern_ast`
- 删除对应字符串版本遗留辅助函数（`awk_render_print_output` / `awk_eval_sub_pattern`）
- 将 `Delete` 语句的数组下标表达式迁移为 AST（`Delete(arr_name, idx_ast?)`）
- 将 `Getline` 的 `< file` 路径表达式迁移为 AST（`Getline(target_raw, path_ast?)`）

## 验证方式

- `cd src && moon check --target js`
- `npx vitest run tests/comparison/awk.comparison.test.ts`
- `npx vitest run tests/spec/awk/awk-spec.test.ts`

## 仍待收口（下一阶段）

1. 继续减少语句节点里的原始字符串负担（例如 `Getline` 目标参数与 `PipeGetline` 目标参数结构化）。
2. 评估并补齐函数体里当前保守 no-op 语句分支（按兼容性逐项推进）。
3. 迁移完成后清理剩余中间兼容辅助函数与重复逻辑。
