# AgentFS 集成分析：替代 OverlayFs / MountableFs

> **决策日期：** 2026-02-19
> **状态：** 已批准，OverlayFs / MountableFs 暂停，改为 AgentFS 适配

---

## 1. 背景

MoonBash Phase 4 原计划实现两个文件系统组件：

- **OverlayFs**（FFI 磁盘读层 + 内存写层 + deleted set 追踪）—— 让 agent 能"看到"宿主项目文件，但不修改真实磁盘
- **MountableFs**（多挂载点路由）—— 不同路径路由到不同后端（`/workspace` → OverlayFs, `/tmp` → InMemoryFs 等）

这两个组件共 8 个待办项，且需要：
1. 将 `CommandContext.fs` 从具体类型 `@fs.InMemoryFs` 抽象为 trait
2. 实现 3 个 FFI 函数（`host_read_file`, `host_stat`, `host_readdir`）
3. 实现 deleted set、path security validation、size limits 等

## 2. AgentFS 是什么

[AgentFS](https://github.com/tursodatabase/agentfs) 是 Turso 出品的 SQLite-backed 虚拟文件系统，专为 AI agent 设计。

### 核心能力

| 能力 | 说明 |
|---|---|
| **POSIX-like VFS** | inode 表 + dentry 表 + data chunk 表，完整文件/目录/符号链接支持 |
| **COW / Whiteout** | `fs_whiteout` 表天然支持 overlay/copy-on-write 语义 |
| **持久化** | 单个 `.db` 文件，断电不丢 |
| **可审计** | `tool_calls` 表记录每次工具调用 |
| **可快照/回滚** | `cp agent.db snapshot.db` 即可冻结状态 |
| **KV Store** | `kv_store` 表存储 agent 状态和上下文 |

### SDK 生态

| 语言 | 包名 | 注册表 |
|---|---|---|
| TypeScript | `agentfs-sdk` | npm |
| Python | `agentfs-sdk` | PyPI |
| Rust | `agentfs-sdk` | crates.io |

### SQLite Schema（摘要）

```sql
fs_inode   -- 文件/目录元数据（mode, nlink, uid, gid, size, timestamps）
fs_dentry  -- 目录项（parent_ino, name → ino），UNIQUE(parent_ino, name)
fs_data    -- 文件内容分块存储（ino, chunk_index → data），默认 4096 字节/块
fs_symlink -- 符号链接目标
fs_whiteout -- overlay 删除标记（COW 语义）
kv_store   -- 键值存储
tool_calls -- 工具调用审计日志
```

### 已有 just-bash 一等集成

```typescript
import { agentfs } from "agentfs-sdk/just-bash";
import { createBashTool } from "just-bash/ai";

const fs = await agentfs({ id: "ai-agent-1" });
const bashTool = createBashTool({ fs });
```

MoonBash 作为 just-bash 的 100% API 兼容替代，可直接复用此集成模式。

## 3. 逐项对比

### 3.1 OverlayFs 的 5 个待办 vs AgentFS

| OverlayFs 原计划 | AgentFS 替代方案 | 省掉了什么 |
|---|---|---|
| FFI-backed disk read layer | SQLite `fs_data` + `fs_inode` 表 | 不需要 `host_read_file` FFI |
| Memory write layer | 写回 SQLite（同一个 `.db` 文件） | 不需要内存层 + 合并逻辑 |
| Deleted file tracking | `fs_whiteout` 表天然支持 | 不需要自己维护 deleted set |
| Path security validation | AgentFS 内部处理，无宿主磁盘暴露 | 消除路径穿越风险 |
| Size limits on disk reads | SQLite 分块存储，可按需控制 | 无需 FFI 层限流 |

### 3.2 MountableFs 的 3 个待办 vs AgentFS

| MountableFs 原计划 | AgentFS 替代方案 | 省掉了什么 |
|---|---|---|
| Multi-mount point routing | 单个 SQLite = 完整命名空间 | 不需要路由器 |
| Mount/unmount API | 不需要 | 不需要 |
| Path normalization across mounts | 不需要 | 不需要 |

### 3.3 额外收益

| 维度 | OverlayFs + MountableFs | AgentFS |
|---|---|---|
| 持久化 | ❌ 内存层断电即丢 | ✅ SQLite 文件持久 |
| 可审计 | ❌ 无 | ✅ `tool_calls` 表 |
| 可快照 | ❌ 无 | ✅ `cp agent.db snapshot.db` |
| 可回滚 | ❌ 无 | ✅ 恢复快照文件 |
| KV 存储 | ❌ 无 | ✅ `kv_store` 表 |
| 浏览器/Edge | ❌ 依赖 Node.js `fs` | ✅ SQLite 有 Wasm 版 |
| Cloudflare Workers | ❌ 不可用 | ✅ `agentfs-sdk/cloudflare` |
| trait 抽象重构 | 必须（改 InMemoryFs → trait） | 不需要改 MoonBit 内核 |

## 4. 集成架构

```
┌─────────────────────────────────────────────────┐
│  用户代码                                        │
│                                                  │
│  const agent = await AgentFS.open({ id: "x" }); │
│  const bash = new Bash({ fs: agentfs(agent) });  │
│  const result = await bash.exec("cat /data.txt");│
└────────────────────┬────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────┐
│  Layer 3 - TypeScript Wrapper (src/wrapper/)     │
│                                                  │
│  AgentFS Adapter:                                │
│  ┌─────────────────────────────────────────┐     │
│  │ exec() 前:                               │     │
│  │   AgentFS.readdir("/") → initialFiles    │     │
│  │   喂给 MoonBit 内核的 InMemoryFs          │     │
│  │                                          │     │
│  │ exec() 后:                               │     │
│  │   diff(initialFiles, modifiedFiles)      │     │
│  │   写回 AgentFS (新增/修改/删除)           │     │
│  └─────────────────────────────────────────┘     │
└────────────────────┬────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────┐
│  Layer 1 - MoonBit 巨核 (src/lib/)              │
│                                                  │
│  InMemoryFs（完全不变）                           │
│  CommandContext.fs 仍是 @fs.InMemoryFs            │
│  纯计算，零感知外部存储                            │
└─────────────────────────────────────────────────┘
```

### 关键原则

1. **MoonBit 内核零改动** —— InMemoryFs 照旧，不需要 trait 抽象重构
2. **同步逻辑全在薄壳层** —— TypeScript wrapper 负责 AgentFS ↔ InMemoryFs 的双向同步
3. **符合"巨核与薄壳"架构** —— 纯计算留在 MoonBit，I/O 适配留在 JS 薄壳
4. **100% API 兼容 just-bash** —— AgentFS 的 just-bash 集成模式直接复用

### 同步策略

```
exec() 前（AgentFS → InMemoryFs）:
  1. 遍历 AgentFS 文件树
  2. 转为 initialFiles: Record<string, string>
  3. 传入 MoonBit 内核初始化 InMemoryFs

exec() 后（InMemoryFs → AgentFS）:
  1. 从内核取 snapshot（所有文件路径 + 内容）
  2. 与 exec 前快照 diff
  3. 新增文件 → AgentFS.writeFile()
  4. 修改文件 → AgentFS.writeFile()
  5. 删除文件 → AgentFS.rm()
```

## 5. 待实现工作

原 OverlayFs + MountableFs 的 8 个待办项替换为：

| 新任务 | 层级 | 说明 |
|---|---|---|
| AgentFS adapter | TypeScript wrapper | `agentfs-sdk` → `initialFiles` 转换 + 执行后回写 |
| `Bash` options 扩展 | TypeScript wrapper | `BashOptions.fs` 接受 AgentFS 实例 |
| 增量同步优化 | TypeScript wrapper | 大文件懒加载、只同步变更文件 |
| 集成测试 | tests/ | AgentFS 模式下的 comparison tests |

## 6. 仍保留 OverlayFs 的场景

AgentFS 替代方案适用于 **AI agent 主场景**。以下场景可能仍需 OverlayFs：

- **本地开发工具** —— 直接读用户项目目录，不需要预装进 SQLite
- **CI/CD 管道** —— 对宿主文件系统做只读检查
- **大型代码库** —— 不适合全量装入 SQLite 的场景

这些场景优先级较低，可在需求明确后重新激活 OverlayFs 计划。

## 7. 参考链接

- [tursodatabase/agentfs - GitHub](https://github.com/tursodatabase/agentfs)
- [agentfs-sdk - npm](https://www.npmjs.com/package/agentfs-sdk)
- [AgentFS Specification (SPEC.md)](https://github.com/tursodatabase/agentfs/blob/main/SPEC.md)
- [AgentFS + just-bash 集成](https://turso.tech/blog/agentfs-just-bash)
- [AgentFS 文档](https://docs.turso.tech/agentfs/introduction)
