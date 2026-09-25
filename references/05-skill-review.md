# Skill 审查结论

> 本文件按 `skill-optimizer`（`D:\11-AI\skills\skill-optimizer`）**Step 3 契约格式**产出。
> 审查日期 2026-09-25。审查者：Claude Code。
> 本轮**零统计数值改动** —— 只动 skill 设计 / 文档 / 护栏。

---

## 审查对象

- **目标 skill**：`plant-div-pipeline`（`D:\01-Academic\00-学术文件\analysis-packages\plant-div-pipeline`）
- **本次范围**：skill-optimizer 8 大类清单全量复扫 + 补交契约格式审查报告 + 修浅扫项（G1–G6）
- **本轮不含**：统计口径调整（上一轮 F1–F64 已完成，`legacy_*` 开关全保留）、模块增删、skill 拆分合并
- **审查基线**：`skill-optimizer/references/review-checklist.md`（9 节）+ `references/skill-design-review-framework.md`

### 清单逐条判定

| # | 大类 | 判定 | 要点 |
|---|---|---|---|
| 1 | **Triggering** 触发语义 | ✅ 通过 | `name`/目录名一致（`plant-div-pipeline`）；description 同时写「做什么+何时用」，前置「植物群落 / 野外样方 / 论文表格」，末尾显式排除「土壤微生物 / 网络分析 / 时间序列 / 通用统计咨询（找 ecology-stats）」，不与相邻 skill 抢触发 |
| 2 | **Workflow** 工作流 | ✅ 通过 | 第 0–10 步顺序明确；三道硬门（第 3 步勾选 → 第 7 步确认 → 才执行）；缺包降级不退出；硬约束 10 条写清「应该/禁止」 |
| 3 | **Progressive Disclosure** 渐进披露 | ⚠️ → ✅ 已修 | 见 G2/G6：模块 23 行表 + 装包命令原与 `README.md` §2/§4 各一份 → 下沉；12 张表全名列原与 `04-paper-tables.md` 重复 → 收敛。文件索引原缺 `VALIDATION.md`/`assets` 其余项/`README.md` → 补全并改成「何时读哪个」表 |
| 4 | **Resource Strategy** 资源策略 | ⚠️ 存疑（已注记） | 见 G4：`assets/` 装的是脚本与模板（`simulate_env.R`/`simulate_community.R`/`05_env_template.csv`/`project_skeleton/`），按口径应只放「输出资源」。**未移动文件**（会断路径引用），已在 README 注明，并列为额外建议。外部依赖安装/校验命令**完整** |
| 5 | **Safety and Sensitivity** 安全 | ⚠️ → ✅ 已修 | 见 G1：`data/*.csv` 原**无代码层写拦截**（`00-data-contract.md` 曾自承）→ 现 `pd_assert_not_data()` 拦 4 个写出口 + `pd_verify_data_unchanged()` 交付前比对 md5 |
| 6 | **Output Contract** 输出契约 | ❌ → ✅ 已修 | 见 G3：第 7 步原只写「等确认」，**没写什么算确认** → 现写死「开始执行语才算；『我看看』『有道理』『都行』不算」 |
| 7 | **Scope Control** 范围控制 | ⚠️ → ✅ 已修 | 见 G5：skill 自身原无不改动项清单 → 现加「不改动项（稳定边界）」节 |
| 8 | **Documentation** 文档 | ✅ 通过 | `README.md` 面向人（场景/三步上手/装包）、`SKILL.md` 面向 AI（工作流/提问协议），分工清楚；原 `assets/simulate_env.R` 在 README 索引重复列两次 → 已删一处 |

**Step 5 验收复核**：

| 校验项 | 结果 |
|---|---|
| frontmatter 只含 `name` + `description` | ✅ |
| `name` / 目录名 / 触发语义一致 | ✅ |
| `description` 能独立表达触发条件 | ✅ |
| `SKILL.md` 比改动前**更短** | ✅ **217 → 202 行**（软目标 170 未达：删重复 −38，同时加了必需的「不改动项 / 确认语义」+18） |
| `references/` 只承载细节，不与 SKILL.md 大段重复 | ✅ 已修（G2/G6） |
| 文件多时有索引，助渐进加载 | ✅ 已改成「何时读哪个」表 |
| 异常场景有处理策略 | ✅ 缺包降级 / 缺数据停机 / 同名不静默覆盖 / 置换超时给预估 |
| 外部依赖附安装+校验命令 | ✅（README §4） |
| 明文敏感信息 | ⚠️ 存疑，见下 |
| 敏感操作有确认门槛 | ✅ 已修（G1 硬门槛 + 第 7 步确认语） |
| Skill 粒度合适 | ✅ 用户已定不拆 |
| `README.md` 存在且分工不同 | ✅ |

---

## 模式判断

- **主模式**：**Generator**（生成整套植物群落分析代码：配置 + 调用脚本 + 23 个固化模块）+ **Reviewer**（第 1 步数据体检、第 2 步科学问题→模块推荐）
- **次模式**：**Inversion**（先出勾选方案与预期产出 → 用户确认 → 才执行；三道硬门就是它的落地）
- **当前判断**：**模式匹配**。Generator/Reviewer/Inversion 三者的分工在工作流里各占一段（第 1–2 步 Reviewer、第 3–5 步 Generator 规划、第 7 步 Inversion 门槛），无模式错位。
- **无过度设计**：23 个模块看着多，但每个都对应论文里一类分析；用户明确要求保留冗余能力（见「不改动项」）。

---

## 安全与依赖

- **敏感信息**：**存疑**
  - 类型：个人本地绝对路径。位置：`SKILL.md` 定位表「存放」行。风险：分发时泄露本机目录结构。
  - 现状：已加注「⚠️ 这是个人本地路径，分发前需参数化」。**未回显完整值**。
  - 处理：保持注记，不改（个人用可接受）；分发前改 `config$paths$root` 为相对路径。
  - 未发现 API Key / Token / Cookie / 账号。
- **敏感操作**：**高风险 → 已降为低**
  - 高副作用操作：覆盖/改写 `data/*.csv`（封丘真实植物数据）。
  - 现状：**已加硬门槛**（G1）：`pd_assert_not_data()` 在 `pd_write_table` / `pd_write_matrix` / `pd_save_pdf` / `pd_save_any` 四个出口拦截，路径解析后落在 `data/` 下即 `stop()`；`pd_verify_data_unchanged()` 交付前比对 md5 快照，变了就 `stop()`。
  - 残余口子：绕过 `pd_*` 直接 `write.csv` —— 由交付校验兜底，另建议 Windows 只读属性作第四道。
  - 次要副作用：覆盖 `results/` / `figures/` / `tables/` 同名产物 —— 已有同名护栏（改存 `HHMMSS` 时间戳，不静默覆盖），旧产物移 `D:/tmp/` 不删。
- **外部依赖**：**有，安装说明完整**
  - CRAN 10 个（`glmm.hp` `MCMCglmm` `missForest` `phylosignal` `phylobase` `flextable` `officer` `readxl` `openxlsx` `pdftools`）+ GitHub 2 个（`helixcn/plantlist` `jinyizju/V.PhyloMaker2`）
  - 安装命令 + `requireNamespace` 校验代码在 `README.md` §4，可直接执行
  - 缺包行为：打印安装命令 → **该模块降级跳过**，不中断全流程

---

## 高优先级

> 影响触发、正确性或执行稳定性。**本轮已全部修复。**

- **[G1] `data/*.csv` 无代码层写拦截** —— 真实植物数据可能被静默改写。`00-data-contract.md` 自承「没有强制写拦截」。
  → 已加 `pd_assert_not_data()` + `pd_verify_data_unchanged()`。实测 18/18 PASS（拦 data/、放行 results/cache、不误伤 `data_backup/` 前缀、篡改快照必报错）。
- **[G3] 第 7 步未定义「什么算确认」** —— 「我看看」「有道理」可能被误读成授权，导致未经确认就执行并覆盖产物。
  → 已写死确认语义 + 第 3 步补「『都行/你定』不算授权，不代选」。

## 中优先级

> 影响可维护性、可复用性或上下文成本。**本轮已修复。**

- **[G2] `SKILL.md` 与 `README.md` / `references/` 三处重复** —— 模块 23 行表、装包命令、12 张表全名列各存两份，改一处漏一处。
  → 模块表与装包命令下沉到 `README.md` §2/§4 与 `references/02-module-specs.md`；12 张表全名列收敛到 `references/04-paper-tables.md`。
- **[G2] `SKILL.md` 越改越长（185 → 217）**，违反 skill-optimizer「改动后更短」。
  → 217 → **202 行**。
- **[G5] skill 自身无「不改动项」** —— 优化时容易悄悄扩大改动面。
  → 已加「不改动项（稳定边界）」节，含用户 2026-09-25 的「多余代码也保留」原话。
- **[G6] 文件索引不全** —— 缺 `VALIDATION.md`、`assets/` 其余 3 项、`README.md`、新审查报告。
  → 改成「何时读哪个文件」表，11 行覆盖全部。

## 低优先级

> 体验提升项，可选。

- **[G4] `assets/` 命名与口径不符** —— 按 skill-optimizer 定义 `assets/` 应只放输出资源，现装的是脚本与模板。
  → **未移动文件**（会断 `SKILL.md`/`README.md` 的路径引用，且 skill-optimizer 要求「尽量小步」）。已在 `README.md` 注明实情。**列为额外建议**。
- `references/00-data-contract.md` 章节编号不连续（§6 后面接 §2.3）—— 纯排版，不影响使用。
- `SKILL.md` 定位表两行（出图张数 / 缓存机制）信息密度很高，可再压缩指向 pitfalls E8/E9；但它们是 AI 常用的操作事实，压走会增加一次读文件，**保留**。

---

## 不改动项

- **23 个模块一个不删**，含只对特定设计适用的：`15_temporal`（仅固定样方跟踪）、功能 β 分格（离散化近似口径）、`90_map`（降级版）、`16_mcmcglmm`。
  依据：用户 2026-09-25「**已有的多余代码也可以保留，因为这个 skill 是为以后的论文服务的，指不定是什么实验设计**」。
  处置方式：靠 `config$design$sampling` 等**设计门槛**启用/跳过，不砍代码。
- **统计口径零改动**。上一轮的 `opts$legacy_*` 开关（`dca_gradient` / `rda_scale` / `mds_autotransform` / `jaccard_binary` / `anova_type` / `*_p_adjust`）全部保留，旧算法可复现。
- **`data/*.csv` 永不改写**（硬约束 10 + G1 硬门槛）。
- **已由用户拍板的规则不擅改**：
  - 12 张论文表格的结构与列
  - 显著性标注规则：**>4 组用字母，≤4 组才用括号**
  - 三项不许代选：① 响应变量 ② 出哪些三线表 ③ RDA/排序双标图显示
- **不做 skill 拆分/合并**（粒度已定）。**不动 `ecology-stats`**（边界已在 description 写清）。
- **不拆 `assets/` → `scripts/`**（见额外建议）。

---

## 额外建议

> 超出本次范围，单列。**均未实施**，等用户拍板。

1. **`assets/` → `scripts/` 归位**（可选重构）
   现状：`assets/` 装 `simulate_env.R` / `simulate_community.R` / `05_env_template.csv` / `project_skeleton/`，是脚本与模板而非输出资源。
   若做：新建 `scripts/` 放两个模拟器，`assets/` 只留 `05_env_template.csv` 与骨架；同步改 `README.md`/`SKILL.md` 引用。
   代价：动 4 处引用；收益：命名合规。**优先级低**，当前注记已够用。

2. **`references/00-data-contract.md` 章节重排**
   §6 出现在 §2.3 之前，编号不连续。重排会让外部引用（SKILL.md「见 §6」）需同步改，收益低。

3. **第四道数据保护：Windows 只读属性**
   对 `data/*.csv` 设只读。注意换机器/拷贝后失效，故只能作补充，不能替代 G1 代码层拦截。

4. **`SKILL.md` 定位表两行再压缩**（出图张数 / 缓存机制 → 指向 pitfalls E8/E9）
   可再省约 2 行显示空间，但会多一次文件读取。见「低优先级」。

5. **跨 skill 协作面**
   本 skill 与 `ecology-stats` 的边界已在 description 写清。若将来做土壤微生物/网络分析的论文，应新建 skill 而非扩展本 skill（本 skill 的 12 张表与 23 模块都是植物群落专用）。

---

# 优化计划

| # | 目标文件 | 变更内容 | 原因 | 用户指定 |
|---|---|---|---|---|
| G1 | `R/00_setup.R` | 新增 `pd_data_dir` / `pd_assert_not_data` / `pd_data_md5` / `pd_verify_data_unchanged`；4 个写出口各加一行 assert；`pd_setup()` 记 md5 快照 | 敏感操作缺硬门槛 | **是**（用户选「加代码层硬门槛」） |
| G1 | `references/00-data-contract.md` | §6 从「没有强制写拦截」改为「三道防线」；§2.5 引言同步 | 措辞与实况一致 | 是 |
| G2 | `SKILL.md` | 删 23 行模块表 + 装包命令块 + 12 张表全名列 → 指向 `references/`/`README.md` | 渐进披露 / 消重复 / 改短 | **是**（用户选「瘦身，重复段下沉」） |
| G2 | `README.md` | 删重复的 `assets/simulate_env.R` 索引行 | 同上 | 是 |
| G3 | `SKILL.md` | 第 7 步补「什么算确认 / 不算确认 / 确认后才动」；第 3 步补「都行/你定不授权」 | 输出契约不通过 | 是 |
| G4 | `README.md` | `assets/` 行注明「是脚本与模板，非输出资源」 | 资源策略存疑（最小改动） | 是 |
| G5 | `SKILL.md` | 新增「不改动项（稳定边界）」节 + 硬约束第 10 条 | 范围控制 | 是 |
| G6 | `SKILL.md` | 文件索引改成「何时读哪个」表并补全 6 项 | 渐进披露 / 索引不全 | 是 |
| — | `references/05-skill-review.md` | **本文件** | 补交 skill-optimizer Step 3 契约格式审查结论 | 是（用户选「出报告 + 修浅扫项」） |

**本次未做**：额外建议 1–5 全部（等用户拍板）；统计数值（零改动）；模块增删（不改动项）。

---

*审查完成 2026-09-25。证据：`D:/tmp/pd_test_guard.R`（G1 护栏 18/18 PASS）、23 个 R 文件 `parse()` 全过、`data/*.csv` md5 与审查前一致。*
