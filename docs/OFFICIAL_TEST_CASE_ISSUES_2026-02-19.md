# 官方测试用例问题记录（用于提 Issue）

日期：2026-02-19

## 复现环境

- 命令统一使用：

```bash
pnpm exec vitest run --no-cache --pool=forks --maxWorkers=1 --fileParallelism=false --silent <suite>
```

- 该参数组合与 `scripts/test-safe.sh` 的执行模型一致（fork + 单 worker）。

## 已确认：测试框架/测试用例本身问题

### 1) `parse-errors.comparison` 基线采集的退出码回退逻辑有误

- 文件：`tests/comparison/parse-errors.comparison.test.ts:27`
- 问题：
  - 原逻辑使用 `err.status || 1`。
  - 在 fork 池下，`execSync` 某些场景会抛错对象（例如 `code: "EPERM"`），但同时携带 `status: 0` 和正常 `stdout`。
  - `status: 0` 被 `|| 1` 误判成 `1`，导致 real bash 基线退出码被污染。
- 影响：
  - `for/if/while/until/true/||/空白命令` 等本应通过的 case 被误报失败（11 个）。
- 修复建议：
  - 改为 `typeof err.status === "number" ? err.status : 1`。
- 本地验证：
  - 修复后 `tests/comparison/parse-errors.comparison.test.ts` 24/24 通过。
  - 整体 `tests/comparison` 在 safe 参数下恢复为 523/523 通过。

### 2) grep spec 的 skip 列表存在“过期 skip”（UNEXPECTED PASS）

- 文件：`tests/spec/grep/skips.ts:1`
- 现象：
  - 多个被 skip 的 case 实际已经通过，runner 以 `UNEXPECTED PASS` 形式报错。
  - 典型类别：
    - “RE2 doesn't support backreferences” 相关条目（多条）
    - “RE2 treats grouped *** differently ...”
    - “BRE literal \\{,2\\} / \\{,\\} ... not implemented”
- 建议：
  - 清理已不再需要的 skip 条目。
  - 将“确属实现缺口”和“历史兼容策略差异”分组，避免 skip 污染回归结果。

### 3) jq spec 的 skip 列表也存在“过期 skip”（UNEXPECTED PASS）

- 文件：`tests/spec/jq/skips.ts:1`
- 现象：
  - 多个 skip 条目已变成实际通过，导致 `UNEXPECTED PASS`。
  - 典型条目：
    - `Invalid \\v escape sequence test`
    - `String interpolation with complex expression`
    - `Empty array/object pattern ...`
    - `Undefined variable $bar behavior differs`
    - `delpaths with large negative index`
    - `join error message`
    - `unique sort order differs`
- 建议：
  - 逐项复核并移除过期 skip。
  - 在 skip 文案中标注“预期移除条件”，便于后续自动清理。

## 需要区分：并非“测试错误”的失败

- 当前 grep/jq 仍有大量失败属于实现差异/功能缺口（例如正则能力、jq 内建函数与语义覆盖），这些不应归类为“官方测试错误”。
- 建议在 issue 中将以下两类拆开跟踪：
  1. **测试资产问题**（本文件三项）
  2. **实现兼容性问题**（grep/jq 功能缺口）

## 建议 issue 标题

- `tests: fix false failures and stale skips in official imported suites (parse-errors/grep/jq)`
