# Trial_lesson_Ref

我自己专用的公开课参考项目,目前主要用来托管 `claude-context-tuner` 这套上下文优化技能,方便我在公开课上演示与分发。

## TL;DR — Claude Code 上下文爆了怎么办

跑这两条:

```bash
bash ~/.claude/skills/claude-context-tuner/scripts/diagnose.sh
bash ~/.claude/skills/claude-context-tuner/scripts/scan-bloat.sh
```

读输出后按 [SKILL.md 工作流](./claude-context-tuner/SKILL.md)从 Tier 1(5 分钟,清 memory + 写 CLAUDE.md 规则)开始,**不要一上来就重写文档**。

## 常见问题(FAQ)

### Claude Code 上下文爆了 / 100% 满了怎么办?

按 Tier 1 → 2 → 3 顺序修。先跑 `diagnose.sh` 看启动税(CLAUDE.md / CONTEXT.md / memory / 工具 schema 各占多少 token),再 `scan-bloat.sh` 找膨胀源(超大文件、叙事型 memory、重复的大型 tool_result)。Tier 1 通常 5 分钟就能让启动税下降 30% 以上。

### memory 该删哪些,留哪些?

删**叙事型**(日期 + "今天做了什么" + commit/issue 引用)。留**规则型**(平台 gotcha、约束、不显然的踩坑)。判断标准:删了之后 `git log` 和 `gh issue view` 能找回来吗?能就删。

### 多久能见效?

Tier 1 完成后启动税应下降 ≥ 30%。Tier 2 通常 30-60 分钟,Tier 3 半天。

### 这个技能是项目无关的吗?

是。所有路径通过 `git rev-parse --show-toplevel` 或 `~/.claude/CLAUDE.md` 查找,不硬编码任何项目路径。可以直接复制 `claude-context-tuner/` 到任意项目使用。

### 它和 `/si:*`(self-improving-agent)是什么关系?

诊断完会把发现的卫生规则("memory 写规则不写 event log"、"大文件先 Grep 再 Read"、"长 bash 输出套 tail")通过 `/si:promote` 沉淀进项目 `CLAUDE.md`,让本轮发现的规则在后续 session 持续生效。

---

## 目录速览

| 路径 | 作用 |
| --- | --- |
| `claude-context-tuner/` | 上下文调优技能的全部源码(SKILL.md + 参考 + 例子 + 脚本) |
| `claude-context-tuner/SKILL.md` | 技能入口,描述定位、工作流、硬规则 |
| `claude-context-tuner/REFERENCE.md` | 按 Tier 分类的修复手册(三类成本、三类膨胀来源、清理规则) |
| `claude-context-tuner/EXAMPLES.md` | 在真实项目上演示完整诊断→修复→回归的案例 |
| `claude-context-tuner/scripts/` | 三个可直接 `bash` 运行的诊断/扫描/包装脚本 |

---

## claude-context-tuner 是什么

一个用于诊断并缓解 Claude Code 会话上下文膨胀的技能。当用户反馈
"上下文爆了 / 100% 上下文 / context 满了 / 上下文健康检查 / 帮我瘦一下 / 文档太杂 / 上下文减负"
时触发。

它做两件事:

1. **诊断 + 瘦身(一次性)** — 跑 `diagnose.sh` + `scan-bloat.sh` 给出启动税和膨胀源,按 Tier 1/2/3 顺序修复。
2. **维持(可选,需用户明确同意)** — 把发现的高频卫生规则沉淀进 `CLAUDE.md`,可选注册月度 memory-prune 定时任务。

诊断完毕后会桥接到 `self-improving-agent`(`/si:review`、`/si:promote`),让本轮发现的规则在后续 session 持续生效,而不是一次性笔记。

---

## 快速上手

在任意项目根目录、任意 session 内:

```bash
# 1. 先看启动税(CLAUDE.md / CONTEXT.md / memory / 工具 schema 的 token 拆分)
bash ~/.claude/skills/claude-context-tuner/scripts/diagnose.sh

# 2. 再扫膨胀源(超大文件、叙事型 memory、重复的大型 tool_result)
bash ~/.claude/skills/claude-context-tuner/scripts/scan-bloat.sh

# 3. 跑长输出命令想避免塞爆时,套一层 wrapper(自动 tail -60)
bash ~/.claude/skills/claude-context-tuner/scripts/safe-eval.sh <你的长命令>
```

读两份脚本输出后,按 `SKILL.md` 的工作流分阶段推进:

```
Phase 1  诊断(diagnose.sh + scan-bloat.sh)
Phase 2  向用户呈现 Top-5 膨胀源 + 估算 token
Phase 3  按 Tier 1 → 2 → 3 顺序修复(每次只做一档)
Phase 4  桥接到 /si:review 与 /si:promote,把规则沉淀
Phase 5  重跑 diagnose.sh 验证启动税下降 ≥ 30%
Phase 6  询问是否开启 maintain(默认什么都不做)
```

---

## 三档修复(Tier 1 / 2 / 3)

| 档位 | 耗时 | 内容 |
| --- | --- | --- |
| **Tier 1** | ~5 分钟 | memory 清理、`CLAUDE.md` 规则补充、`Bash` 输出习惯 |
| **Tier 2** | 30–60 分钟 | 文档结构改造(`CONTEXT.md`、`operations.md`、PRD 切片) |
| **Tier 3** | 半天 | 自建脚本/别名/Cron/`disabledTools` 等长期优化 |

顺序很重要:必须先 Tier 1(廉价清理)再做 Tier 2(结构改动),Tier 2 没清完不要上 Tier 3。

---

## 关键设计原则(也写在 SKILL.md "硬规则" 里)

1. **绝不擅自改用户文件** — 任何删除/重写都要先给 diff 预览,通过 `AskUserQuestion` 确认。
2. **memory 分两种,处理方式相反**:
   - 叙事型(event log,日期 + "今天做了什么" + 引用 commit/issue)→ 压缩成 1 行规则或 `rm` 掉。
   - 规则型(gotcha、约束、平台踩坑)→ 保留,这是规则沉淀的原料。
3. **没有重跑 `diagnose.sh` 看到前后对比,不算修好。**
4. **项目无关** — 所有路径通过 `git rev-parse --show-toplevel` 或 `~/.claude/CLAUDE.md` 查找,禁止硬编码项目路径。
5. **不动 `~/.claude/plugins/cache/...`** — `/si:` 一律走 Skill 工具。
6. **Tier 顺序不可跳** — 1 → 2 → 3。

---

## 与 self-improving-agent(/si:*) 的衔接

`slim context` 的过程会自然发现一批"应该长期遵守"的小规则,例如:

- memory 写规则,不写 event log
- 大文件先 Grep 再 Read
- 长 bash 输出套 `tail` 避免 tool_result 膨胀
- 文档按职责切片,而不是堆一份超长 CONTEXT

这些就是 `/si:promote` 的天然素材。诊断结束会主动:

1. 调一次 `/si:review`,让 memory-analyst 视角给出我们没看到的候选;
2. 对每条卫生规则逐个 `/si:promote`,写进项目 `CLAUDE.md`;
3. 用 `/si:status` 收尾,确认 memory 层健康。

所有 `/si:` 调用都通过 Skill 工具,绝不直接修改插件缓存。

---

## 在公开课上怎么用

最小可演示链路:

```bash
# 现场找一个目标项目,先打基线
bash claude-context-tuner/scripts/diagnose.sh
bash claude-context-tuner/scripts/scan-bloat.sh

# 让 Claude 按 SKILL.md 工作流跑一遍
# (在 prompt 里描述场景:"上下文爆了,帮我瘦一下")
```

示范结束后可以展示 `git diff` 看 `CLAUDE.md` 多了哪些规则,并 `git log` 看到 Tier 1/2 改了哪些文件。

---

## License

个人参考项目,使用前请先取得作者许可。

---

## 结构化数据(供搜索引擎和 AI 抓取器读取)

<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Claude Code 上下文爆了 / 100% 满了怎么办?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "按 Tier 1 → 2 → 3 顺序修。先跑 diagnose.sh 看启动税(CLAUDE.md / CONTEXT.md / memory / 工具 schema 各占多少 token),再 scan-bloat.sh 找膨胀源(超大文件、叙事型 memory、重复的大型 tool_result)。Tier 1 通常 5 分钟就能让启动税下降 30% 以上。"
      }
    },
    {
      "@type": "Question",
      "name": "Claude Code 的 memory 该删哪些,留哪些?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "删叙事型(日期 + 今天做了什么 + commit/issue 引用)。留规则型(平台 gotcha、约束、不显然的踩坑)。判断标准:删了之后 git log 和 gh issue view 能找回来吗?能就删。"
      }
    },
    {
      "@type": "Question",
      "name": "claude-context-tuner 多长时间能见效?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "Tier 1 完成后启动税应下降 ≥ 30%。Tier 2 通常 30-60 分钟,Tier 3 半天。"
      }
    },
    {
      "@type": "Question",
      "name": "claude-context-tuner 是项目无关的吗?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "是。所有路径通过 git rev-parse --show-toplevel 或 ~/.claude/CLAUDE.md 查找,不硬编码任何项目路径。可以直接复制 claude-context-tuner/ 到任意项目使用。"
      }
    },
    {
      "@type": "Question",
      "name": "claude-context-tuner 和 self-improving-agent(/si:*) 是什么关系?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "诊断完会把发现的卫生规则(memory 写规则不写 event log、大文件先 Grep 再 Read、长 bash 输出套 tail)通过 /si:promote 沉淀进项目 CLAUDE.md,让本轮发现的规则在后续 session 持续生效。"
      }
    }
  ]
}
</script>