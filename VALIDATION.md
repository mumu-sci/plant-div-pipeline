# VALIDATION · 包的真实数据验证记录

**验证时间**：2026-09-21
**验证数据**：封丘植物多样性论文（180 样方 = 20 样点 × 3 生境 × 3 季节；150 物种）
**验证报告**：`D:\01-Academic\02-小论文封丘文件\03-分析R代码&数据\_skill验证\plant-div-pipeline_验收报告.md`
**验证目录**：`D:\01-Academic\02-小论文封丘文件\03-分析R代码&数据\_skill验证\`（含可一键复现的脚本 `code/_run_all_validation.R`）

## 结论

17 个模块中 **14 个跑通**，3 个按设计受控跳过（21 缺 `missForest`、32 缺 `phylosignal`+`phylobase`、90 未提供边界文件）。
全流程约 3 分钟（R 4.5.2 / Windows / perm=199）。

## 数值复现强度

| 模块 | 对照对象 | 结果 |
|---|---|---|
| 10 α 多样性 | 论文原表 S / Shannon / Pielou | **S 180/180 完全相同；Shannon、Pielou r = 1.0000，max\|差\| = 0.0000** |
| 01 正态性诊断 | 论文 Shapiro-Wilk 表 | **W 值 9/9 完全一致；正态性判定 9/9 一致** |
| 01 方差齐性 | 论文 Bartlett 表 | 9/9 与原文 Habitat 列一致 |
| 31 PD | 论文 PD 列 | **r = 1.0000，中位差 0.0000**（夏季存在 +2.1 系统偏移，见报告 §4.3） |
| 31 MNTD/MPD | 论文 mntd / mpd 列 | 论文那两列实为 `obs.z`；按正确口径 **r = 0.9892 / 0.9521**（残差为置换随机性） |
| 20 功能多样性 | 论文 F.Ric 等 | r = 0.61~0.82 —— **口径不同**（37 原始性状 vs 5 PCA 主轴），非缺陷 |
| 12 组间比较 | 论文 SRH 输出 | 本包 ANOVA 结果自洽；发现**原文 SRH 表因子标签疑似对调**（报告 §4.4） |
| 40 排序/差异 | 论文相关输出 | PERMANOVA Habitat R²=0.171 p=0.005；Season R²=0.216 p=0.005；stress=0.193 |

## 验证暴露出的、包已适配的问题

1. 树 tip 与多度列名带尾随空格（150 / 150 个列名需规范化）→ `normalize_species()` 统一处理
2. 多度矩阵是**连续重要值**而非整数计数 → `rarefy` 自动跳过并说明
3. 多度物种池与性状物种池**只有 101/150 字面匹配**（TRY 按属匹配的痕迹）→ 输出 `suspect_synonyms`，只报告不改名
4. `multcomp::cld()` 结果无 rownames，字母在 `$mcletters$Letters`
5. `vegan::varpart()` 需 2~4 个解释表，不接受单表
6. `betapart::functional.betapart.core()` 要求群落物种数 > 性状数 → 自动预检并给出降维建议
7. `V.PhyloMaker` 的 GBOTB 数据须显式 `data()` 载入并作为参数传入
8. 中文路径在 C locale 下解析失败 → 启动器统一 `Sys.setlocale("LC_CTYPE","Chinese_China.utf8")`

以上全部记入 `references/03-pitfalls.md`（G 段）。

## 尚未验证

> 本节是第一轮时的状态记录，**大部分已被后续轮次解决**：建树路径见文末"第三轮"，
> 21/32/90 见"补建后复验"的"状态更新"。保留原文以便追溯。

- `99_phylo.tre` 之外的建树路径（`V.PhyloMaker2`，本机未装）　→ ✅ 第三轮已验证
- 21 / 32 两个模块（缺包）　→ ✅ 第二轮已验证
- 90 地图模块（缺边界文件）　→ ✅ 第二轮已验证
- 正式置换规模（999+）的耗时与稳定性　→ ⬜ 仍未验证
- 中文图（`plot$lang = "zh"`）在目标期刊排版下的字体嵌入　→ ⬜ 仍未验证

---

## 补建后复验（2026-09-21 第二轮）

按要求补全了对照原文代码发现的 **14 项遗漏板块 + 3 项部分覆盖**（详见 `references/02-module-specs.md` 补充段），并**安装了全部缺失依赖**。

**模块数：17 → 18**（新增 `16_mcmcglmm.R`）。

### 复验结果：18 个模块 + 括号模式共 19 项运行，全部通过，总耗时 4.7 分钟

| 补建项 | 结果 |
|---|---|
| NMDS 分面 + 拼图 | 4 张：`40_nmds_combo/facet_Habitat/facet_Season/panel.pdf` |
| 两两 ANOSIM | 18 组（生境内比季节 + 季节内比生境），全部显著 |
| ANOSIM 秩箱线图 | 2 张 |
| QQ 图 | `01_qq_normality.pdf`（10 变量 × 2 因子 = 20 面板，非正态标红） |
| 交互效应图 | 10 张（对应 `HH::interaction2wt`） |
| 显著性括号 | `sig_label = "bracket"` 模式跑通；括号 p 值与主检验同源 |
| varpart Venn 图 | 11 张（含 community 与 10 个指数） |
| ggtree 分组着色树 | `30_tree_round_by_family.pdf`（按科着色环形树） |
| betapart 多 sheet | `core_shared` / `core_not_shared` / `funcbeta_beta.sim` / `.sne` / `.sor` |
| phylo4d 套件 | 4 张（barplot / dotplot / gridplot / LIPA 显著着色） + 5 张单性状 |
| lipaMoran 局部信号 | 3737 个「物种 × 性状」组合，显著 287 个 |
| phyloSim | 已实现（默认关闭）；`nsim=5, reps=9` 实测 0.13 分钟 |
| MCMCglmm | 跑通；Shannon R²m=0.619 / R²c=0.666，S R²m=0.432 / R²c=0.554；迹图 2 张 |
| 地图（底图+采样点+嵌图+引线） | `90_study_area_main.pdf` + `90_study_area_composite.pdf`（不联网、无密钥） |
| 配色工具 | `00_palette_npg.pdf` / `00_palette_dark2.pdf` |

### 复验中新发现并处理的问题

1. **`betapart::functional.betapart.core` 在本数据规模下不可行** —— 实测 180 样方（16110 对）>10 分钟无输出；即使 **20 样方（190 对）也 >10 分钟**，折合每对 >3.2 秒，外推 180 样方 >14 小时。
   → 加门控 `opts$fd_beta_max_sites`（默认 120）+ 替代路线 `opts$fd_beta_method = "traitspace"`（性状空间分格 → 功能实体 → Baselga β，实测 180 样方秒级完成）。
2. **`MCMCglmm` 的 `VarCorr` / `autocorr` 均未导出** —— 改用 `summary()$Gcovariances` / `$Rcovariances`，自相关用 `stats::acf` 自算。
3. **MCMCglmm 对 gaussian 不返回 `r.squared`** —— 改为按后验均值 + Nakagawa 分解自算。
4. **MCMCglmm 混合诊断必须同时看固定效应链与方差成分链** —— 实测 Shannon 的 VCV 链 lag-1 = **0.247**（≥0.1，混合不足）而 Sol 链仅 0.018；只看 Sol 会漏报。
5. **`phyloSignal()` 返回结构是 `list(stat, pvalue)` 两个 data.frame**（行=性状、列=统计量），不是"每个统计量一个向量"。
6. **`barplot/dotplot/gridplot.phylo4d` 未导出且为 base 风格（画到设备返回 NULL）** —— 需 `getS3method` 取函数 + 显式开设备；新增 `pd_capture_plot()` 统一处理 ggplot / grid / base 三类返回。

### 状态更新

原先"未验证"的 3 项现已全部验证通过：**21 性状插补**、**32 系统发育信号**、**90 地图**。
仍未验证：正式置换规模（999+）、中文图字体嵌入。

---

## 第三轮：建树路径验证 + 换树对比（2026-09-21）

### 验证了什么

`30_phylo_build.R` 的 **`V.PhyloMaker2` 建树路径**（此前唯一未覆盖的代码路径）现在已实跑通过：

| 项 | 结果 |
|---|---|
| `pd_prep_splist()` | 对照表 150 条 → 与多度矩阵交集 150 条；清理 1 处 NBSP；报告 1 个物种缺 genus/family |
| `pd_make_tree(scenarios="S3")` | `attr(pd_builder) = "V.PhyloMaker2"`，tips = 149，有枝长，用时 **0.78 分钟** |
| `pd_run_phylo_build()` | 产出 `30_built_tree.tre` / `30_tree_tips.xlsx` / `30_invisible_chars.xlsx` / `30_tpl_check.xlsx` + 环形树 2 张（含按科分组着色） |
| 全包语法 | 19 / 19 通过 |

巨树 `GBOTB.extended.TPL` = 74,529 tips；150 种中 **115 种直接剪取、35 种（23.3%）按属级拼接**。

### 换建树工具对结论的影响（核心结论）

同一份 150 种名单重建树，与项目现有 `99_phylo.tre` 逐样方比对：

| 对照项 | 结果 |
|---|---|
| tip 标签 | 150 / 150 完全一致 |
| 总枝长 | 7041.5 vs 6992.5（差 **0.7%**） |
| Robinson-Foulds | 22 / 294 → 归一化 **0.075** |
| PD | r = **0.9996**（相对差中位 0.015%，最大 1.55%） |
| MNTD / MPD 观测值 | r = 0.9999 / 1.0000 |
| NTI / NRI | r = **0.9922** / **0.9750** |
| 聚集·随机·发散 判读 | NTI **178/180（98.9%）**、NRI **173/180（96.1%）** |

**结论：换建树工具/情景对结论层面无影响**；判读翻转只发生在 |z| 距阈值 2 不足 0.35 的边缘样方。
→ 不必长期纠结用哪棵树；但树文件名/建树工具/情景仍必须写进结果表 `run_info`。

### 本轮新发现并修掉的问题

1. **物种名单的 genus/family 未走规范化** —— `pd_prep_splist()` 只清理了 species 列，
   genus/family 原样传给 `phylo.maker`。实测 `Erysimum` 的 family 是 `\u00A0Brassicaceae`
   （U+00A0 NBSP 前导），触发 `Taxonomic classification not consistent` 告警。
   → 新增 `pd_strip_invisible()`，在 `pd_prep_splist()` 中清理 genus/family。
2. **`normalize_species()` 覆盖不全** —— 旧版只处理 U+00A0 与 U+3000；
   新增 U+1680、U+2000~U+200A、U+202F、U+205F、U+200B/200C/200D、U+FEFF。
   注意 `trimws()` 默认只认 `[ \t\r\n]`，**不认任何 Unicode 空格** —— 这是静默匹配失败的根源。
3. **数据体检缺"不可见字符"这一项** —— 新增 `§(a3)` 段 + `pd_scan_invisible()`，
   每次体检扫描多度列名/性状物种/树 tip/物种对照表的 species·genus·family，
   结果写入 `01_health.xlsx` 的 `invisible_chars` sheet。已在封丘数据上实测命中 1 处。

### 数据源层面的两个缺口（包只报告、不擅自补）

1. `plant_data.xlsx`（Latin name）**缺 `Lonicera_japonica`**，导致其 family=NA →
   `pd_prep_splist()` 按纪律跳过它，建出的树是 149 tips 而非 150（对结论无影响）。
2. `04_species_list.csv` 中 `Erysimum_cheiranthoides` 的科名带 U+00A0 前导空格。

