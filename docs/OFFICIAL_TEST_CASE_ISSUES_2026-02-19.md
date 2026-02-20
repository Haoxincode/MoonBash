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

### 2) grep spec 的 skip 列表存在”过期 skip”（UNEXPECTED PASS）

- 文件：`tests/spec/grep/cases/gnu-bre.tests` 中的 `# SKIP:` 行
- 来源：这些 `# SKIP:` 注释从 `vercel-labs/just-bash` 原样导入（commit `aaa5af1`），经比对 just-bash 原版完全一致。当时 just-bash 使用 RE2 引擎不支持 backreference，但 MoonBash 的 `@moonbitlang/core/regexp` 已支持。
- 现象：17 个 UNEXPECTED PASS
  - “RE2 doesn't support backreferences”（13 条，行 22–44, 82）
  - “RE2 treats grouped/start *** differently”（2 条，行 49, 54）
  - “BRE literal \\{,2\\} / \\{,\\} not implemented”（2 条，行 63, 65）
- 修复：删除 `gnu-bre.tests` 中对应的 17 行 `# SKIP:` 注释

### 3) jq spec 的 skip 列表也存在”过期 skip”（UNEXPECTED PASS）

- 文件：`tests/spec/jq/skips.ts`（同样从 just-bash 导入）
- 现象：12 个 UNEXPECTED PASS
  - SKIP_TESTS（8 条）：`”u\\vw”`、`”inter\\(...)”`、`. as [] | null`、`. as {} | null`、`$bar` 未定义变量、`{(true):$foo}`、`delpaths([[-200]])`、`trim/ltrim/rtrim`
  - SKIP_PATTERNS（5 条）：`join error message`、`delpaths negative`、`”u\\vw”`、`inter\\(`、`[$foo, $bar]`
  - SKIP_INPUT_PATTERNS（1 条）：`unique sort order`
- 修复：从 `skips.ts` 移除上述 14 个条目

## MoonBash 相对于 just-bash 的兼容性优势

上述 grep 过期 skip 揭示了一个重要差异：just-bash 使用 RE2 引擎（不支持 backreference），而 MoonBash 的 `@moonbitlang/core/regexp` **已支持 backreference**（`\1`、`\2` 等反向引用）。

Backreference 在 grep/sed 中用于匹配前面括号捕获的内容，是 POSIX BRE 标准的一部分：

```bash
# 匹配连续重复字符（aa, bb, cc ...）
echo “aabcd” | grep '\(.\)\1'

# 匹配 HTML 标签配对
echo “<div>text</div>” | grep '<\([a-z]*\)>.*</\1>'
```

这意味着 MoonBash 的 grep 在正则兼容性上优于 just-bash，AI agent 使用时不会遇到 backreference 不支持的意外。

## 需要区分：并非”测试错误”的失败

- 当前 grep/jq 仍有大量失败属于实现差异/功能缺口（例如正则能力、jq 内建函数与语义覆盖），这些不应归类为“官方测试错误”。
- 建议在 issue 中将以下两类拆开跟踪：
  1. **测试资产问题**（本文件三项）
  2. **实现兼容性问题**（grep/jq 功能缺口）

## 建议 issue 标题

- `tests: fix false failures and stale skips in official imported suites (parse-errors/grep/jq)`

## 已提交的 Issue 跟踪

| 仓库 | Issue | 内容 | 涉及失败数 |
|---|---|---|---|
| [Haoxincode/MoonBash#4](https://github.com/Haoxincode/MoonBash/issues/4) | tests: fix false failures and stale skips in official imported suites | 测试基础设施修复（parse-errors 退出码 + grep/jq 过期 skip） | ~29 |
| [Haoxincode/MoonBash#5](https://github.com/Haoxincode/MoonBash/issues/5) | chore: integrate real gzip and tar to replace sandbox-only stubs | ✅ gzip 已集成真实 DEFLATE（commit `1d0b311`）；tar: `bobzhang/tar` 仅为内存数据结构（无二进制序列化），保留 MBTAR1 自有格式 | 部分完成 |
| [Haoxincode/MoonBash#6](https://github.com/Haoxincode/MoonBash/issues/6) | tests: clean up 29 stale skips inherited from just-bash | 移除 grep 17 + jq 12 个过期 skip（MoonBash regexp 已支持 backreference） | 29 |
| [moonbit-community/moonbit-jq#5](https://github.com/moonbit-community/moonbit-jq/issues/5) | Feature gaps & semantic issues found via jq official test suite | moonjq 解析器/缺失函数/语义 bug | ~155 |
| [moonbitlang/regexp.mbt#16](https://github.com/moonbitlang/regexp.mbt/issues/16) | Missing POSIX character classes, word boundaries, and lenient brace handling | regexp 库缺失 POSIX 字符类/词边界/花括号容错 | 27 |

## 当前失败快照（2026-02-19，已复核）

复核命令（与 `test-safe` 同参数）：

```bash
pnpm exec vitest run --no-cache --pool=forks --maxWorkers=1 --fileParallelism=false --silent <suite>
```

### 通过套件

- `tests/unit`：`168 passed`
- `tests/comparison`：`522 passed`（1 awk 回归自 `b38190a`，见下方）
- `tests/spec/sed`：`237 passed`
- `tests/security/sandbox`：`178 passed`
- `tests/security/limits`：`86 passed | 1 skipped`
- `tests/security/attacks`：`188 passed` ✅（原 1 failed，已修复 `6cbd88f`）
- `tests/agent-examples/*`：本轮抽检全部通过

### 未通过套件（需要继续修）

1. `tests/spec/grep/grep-spec.test.ts`
   - `54 failed | 227 passed | 51 skipped`
   - 失败构成：实现缺口（regex 兼容）+ 过期 skip（`UNEXPECTED PASS`）

2. `tests/spec/jq/jq-spec.test.ts`
   - `170 failed | 598 passed`
   - 失败构成：实现缺口（jq 语义/内建函数）+ 过期 skip（`UNEXPECTED PASS`）

3. ~~`tests/security/attacks`~~ ✅ **已修复** (commit `6cbd88f`)

4. `tests/spec/awk/awk-spec.test.ts`（回归自 `b38190a`）
   - `6 failed | 146 passed | 1 skipped`
   - 失败构成：getline condition caching 引入的回归

5. `tests/comparison`（回归自 `b38190a`）
   - `1 failed | 522 passed`
   - 失败点：awk 相关 comparison fixture

6. `tests/security/prototype-pollution`（回归自 `b38190a`）
   - `6 failed | 414 passed`
   - 失败构成：awk sub/gsub 相关回归

7. `tests/spec/bash/spec.test.ts`（按 `test-safe` 分片）
   - `[1/10]` `205 failed | 179 passed | 1952 skipped`
   - `[2/10]` `142 failed | 135 passed | 2059 skipped`
   - `[3/10]` `146 failed | 194 passed | 1996 skipped`
   - `[4/10]` `51 failed | 133 passed | 2152 skipped`
   - `[5/10]` `138 failed | 87 passed | 2111 skipped`
   - `[6/10]` 超时（120s，无 summary）
   - `[7/10]` 超时（120s，无 summary）
   - `[8/10]` 超时（120s，无 summary）
   - `[9/10]` 超时（120s，无 summary）
   - `[10/10]` `1 failed | 2 passed | 2333 skipped`

### 追踪建议（优先级）

1. 先清理 `grep/jq` 过期 skip（低风险、高收益，能快速去掉 `UNEXPECTED PASS` 噪音）
2. ~~单独修复 `security/attacks` 那个 broken symlink 断言~~ ✅ 已修复（commit `6cbd88f`）
3. 调查并修复 awk 回归（commit `b38190a` getline condition caching 引入的 6+6+1=13 个失败）
4. 再处理 `grep` regex 兼容缺口
5. 最后集中攻 `bash spec`（量级最大，且存在超时分片）
