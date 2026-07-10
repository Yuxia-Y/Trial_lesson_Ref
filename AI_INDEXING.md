# AI 索引配置记录

记录 Trial_lesson_Ref 仓库为了让 AI 引擎(ChatGPT / Claude / Gemini / Perplexity)在"网站搜索"时能找到并引用我们内容所做的全套配置。

最后更新:2026-07-10

---

## 目的

仓库本身是公开课参考项目,但默认情况下 GitHub 仓库的 `blob/main/...` URL 会被 GitHub 包成 HTML,搜索引擎 / AI 抓取器读到的是页面外壳,不是纯内容。本文档记录为了让它们能干净地抓到内容做的所有配置。

---

## 改动清单

| 文件 | 作用 |
| --- | --- |
| `README.md` | 项目说明 + TL;DR + FAQ + JSON-LD FAQPage 结构化数据 |
| `llms.txt` | AI 抓取器入口,声明仓库结构、适用场景、硬规则 |
| `sitemap.xml` | 搜索引擎收录索引,URL 全部用 GitHub Pages |
| `claude-context-tuner/` | 完整技能源(SKILL.md / REFERENCE.md / EXAMPLES.md / scripts/) |
| `.github/workflows/indexnow.yml` | 每次 push 自动调 IndexNow API 通知 Bing/Yandex/Seznaz |
| `<key>.txt` | IndexNow 验证文件,文件名 = 32 位 hex key,内容 = key(无换行) |

---

## 关键决策

### 为什么用 GitHub Pages 而不是 `github.com/.../blob/main/...`

`blob/` URL 会被 GitHub 包成 HTML 框架,Bing 验证时拿到 HTML 不是纯 XML,验证失败。GitHub Pages `yuxia-y.github.io/Trial_lesson_Ref/...` 是**原样 serve**,所有验证/抓取走这一套 URL。

### 为什么有 `llms.txt`

新兴的 LLM 入口协议(类比 robots.txt),Perplexity / Cursor / 一些 RAG 抓取器主动读根目录的 `/llms.txt`,告诉 AI 这个站是什么、有哪些入口。比 README 优先级高。

### 为什么 README 末尾有 `<script type="application/ld+json">`

GitHub Markdown 渲染器**会原样输出** HTML 块,所以 JSON-LD FAQPage schema 会被写到页面里,Google Rich Results 和 AI 抓取器都能读到。

### 为什么 IndexNow 不用主站 "Get Key"

`indexnow.org` 主站不再直接提供"Get Key"按钮。IndexNow 文档允许**任意 8-128 位字符串**(a-zA-Z0-9-)作为 key,我们用 `openssl rand -hex 16` 自助生成 32 位 hex。

---

## 当前状态

| 组件 | 状态 | 备注 |
| --- | --- | --- |
| GitHub Pages | ✅ 已启用 | https://yuxia-y.github.io/Trial_lesson_Ref/ |
| Bing Webmaster | ✅ sitemap 处理成功 | 6 条核心 URL 已提交 |
| Google Search Console | ⏳ 已提交 sitemap + Request Indexing | 抓取中(几小时 - 24 小时) |
| IndexNow | ✅ workflow 跑通 | 见下"已知坑"第 1 条 |
| 外部反向链接 | ⏳ 待做 | 决定 AI 是否真引用 |

### IndexNow Key

```
f78ad613349cf349bc6e191e03933217
```

**必须同时存在**:
1. 仓库根的 `f78ad613349cf349bc6e191e03933217.txt`(32 字节无换行)
2. GitHub Settings → Secrets → Actions → `INDEXNOW_KEY` secret

任一缺失 workflow 都会失败。

---

## 已知坑(以后回看避免)

### 1. IndexNow workflow 第一次失败:`Could not access 'HEAD~1'`

GitHub Actions 默认 `actions/checkout` 是 shallow clone(只有一层),`git diff HEAD~1 HEAD` 拿不到上一次 commit。

**修复**:workflow 里加
```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0
```

### 2. BingSiteAuth.xml / Google 验证 HTML 文件必须在 Pages 启用后才有意义

GitHub Pages 启用前,Bing/GSC 验证失败。**先**启用 Pages,**再**做验证。

### 3. Windows Git 的 LF → CRLF warning 无害

`warning: in the working copy of 'X', LF will be replaced by CRLF the next time Git touches it`
是 Windows Git 自动转换行尾符,不影响功能。可以配 `.gitattributes` 关掉,但没必要。

### 4. `printf "%s" "$KEY"` 不要用 `echo`

`echo` 会加换行符,IndexNow 验证文件必须**精确 32 字节**。

### 5. GitHub Pages 用 README 当首页

仓库根没有 `index.html`,GitHub Pages 默认把 `README.md` 当成首页渲染。这对我们刚好(README 就是想被 AI 抓的)。

---

## 维护指南

### 改 README / 加新文件

正常 commit + push 即可:
- IndexNow workflow 自动通知 Bing/Yandex
- Bing 已索引过,会重新抓
- Google 需要 1-3 天自然更新,或去 GSC URL Inspection Request Indexing

### 想看哪些文件被 AI 引用

1-2 周后,在 Perplexity / ChatGPT / Gemini 直接搜:
- "Claude Code 上下文爆了"
- "Claude Code context 100%"
- "Claude context tuner"

看 Sources 列表有没有 `yuxia-y.github.io/Trial_lesson_Ref/` 或 `github.com/Yuxia-Y/Trial_lesson_Ref/`。

### 想重新生成 IndexNow key

如果 key 泄漏 / 想轮换:
```bash
NEW_KEY=$(openssl rand -hex 16)
printf "%s" "$NEW_KEY" > "$NEW_KEY.txt"
git rm <旧key>.txt
git add "$NEW_KEY.txt"
git commit -m "rotate IndexNow key"
git push
```
然后去 GitHub Secrets 改 `INDEXNOW_KEY` 为新值。

### 想撤掉所有 AI 索引配置

```bash
# 撤 Pages
# (在 GitHub Settings → Pages → Source → None)

# 撤 IndexNow
rm .github/workflows/indexnow.yml
git rm <key>.txt
git commit -m "remove IndexNow"
git push
```

sitemap.xml / llms.txt / JSON-LD 不撤也行,撤了只是让搜索引擎少一个入口。

---

## 一次性进度日志

```
2026-07-10  仓库从空 README 起步
            clone + 上传 claude-context-tuner skill
            README 重写 + FAQ + JSON-LD
            加 llms.txt / sitemap.xml
            启用 GitHub Pages(yuxia-y.github.io)
            sitemap 改用 Pages URL
            Bing Webmaster 验证 + sitemap 提交成功
            IndexNow 自助生成 key + workflow
            workflow 第一次失败:HEAD~1 问题
            workflow 加 fetch-depth: 0 修复
            Google Search Console 提交 sitemap + Request Indexing
```

---

## 参考资料

- [IndexNow 协议](https://www.indexnow.org/)
- [Google 结构化数据 FAQPage](https://schema.org/FAQPage)
- [GitHub Pages 文档](https://docs.github.com/en/pages)
- [Bing Webmaster Tools](https://www.bing.com/webmasters)
- [Google Search Console](https://search.google.com/search-console)