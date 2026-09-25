# 01 · 方法菜单与推荐规则

**入口是科学问题，不是模块。** 用户描述问题 → 按 §1 映射出模块组合 → 按 §2 逐模块列方法选项并给推荐。

推荐**必须**由 `01_data_health.R` 的诊断结果驱动（正态性 / 方差齐性 / 平衡性 / 每组样本量 / 物种数 vs 性状数）。禁止无依据地推荐。

---

## §1 科学问题 → 模块组合

| 科学问题（用户原话） | 推荐模块组合 |
|---|---|
| 多样性格局：谁在变、怎么变 | `10_alpha` → `12_tests` → `60_plots` |
| 群落组成：组成差异有多大 | `11_beta` → `40_ordination`（NMDS+PERMANOVA+ANOSIM） |
| 组成差异里"替换"与"嵌套"各占多少 | `11_beta`（betapart turnover/nestedness） |
| 驱动机制：多样性由什么解释 | `41_varpart` → `14_mixed_model` |
| 功能维度：功能多样性怎么变 | `20_fd` → `12_tests` → `60_plots`；性状有缺失时先 `21_impute` |
| 进化维度：谱系多样性/信号 | `30_phylo_build` → `31_pd_nti_nri` → `32_phylo_signal` |
| 性状—物种关系：物种按什么性状分群 | `21_impute` → `50_pca_hcpc` → `51_heatmap` |
| 时间自相关（季节序列） | `15_temporal` |
| 研究区描述 | `90_map` |

---

## §2 模块 → 方法选项与推荐规则

### 10 α 多样性
**固定输出**：`S`(specnumber)、`Shannon`、`Simpson`、`Pielou = Shannon/log(S)`；距离矩阵另存：`Bray`、`Jaccard`、`Kulczynski`。
**可选项**：是否 rarefy（`vegan::rarefy`）到统一个体数 —— 若各样本个体数差异 > 2 倍，推荐做，并同时报未稀释值。

### 12 组间比较（**核心分歧点，必须问用户**）

判定顺序（依 `01_data_health` 诊断）：

```
① 设计里有随机因子且有重复？
   ├─ 有 → 推荐 14_mixed_model（LMM）；同时报传统检验作对照
   └─ 无 ↓
② 因子个数
   ├─ 1 个 → 残差正态(p>α) 且 方差齐(p>α)
   │         ├─ 是 → 单因素 ANOVA + Tukey HSD
   │         └─ 否 → Kruskal-Wallis + Dunn(校正)
   ├─ 2 个 → 残差正态 且 方差齐 且 每组合 n≥3（可估交互）
   │         ├─ 是 → 双因素 ANOVA + Tukey 字母标记(multcomp::cld)
   │         │        【封丘原文口径：aov(y ~ factor(A) + factor(B)) + Tukey 字母】
   │         └─ 否 → Scheirer-Ray-Hare + Nemenyi
   └─ ≥3 个 → LMM/GLMM，或先降维再建模
```

| 选项 | 适用条件 | 输出 | 何时推荐 |
|---|---|---|---|
| `anova_tukey` | 残差正态 + 方差齐 + 设计较平衡 | ANOVA 表 + Tukey 字母 | 封丘默认；审稿人熟悉 |
| `nonparam_srh` | 两因子但正态性/方差齐性不满足 | SRH 表 + Nemenyi | 诊断不通过时 |
| `kruskal_dunn` | 单因子、非正态 | K-W 表 + Dunn(校正) p | 只看单因子时 |
| `lmm` | 有嵌套/重复测量 | 混合模型系数 + emmeans 边际均值 | 有 Site 随机效应时 |
| `perm_anova` | 分布严重偏离、样本量小 | 置换 ANOVA | 稳健性检验用 |

**字母标记方法**：`multcomp::cld(..., alpha = config$opts$alpha)`（注意参数名是 `alpha`，不是 `alpah`）。

### 11 β 多样性
| 选项 | 说明 | 推荐 |
|---|---|---|
| 距离度量 | `bray`（定量）、`jaccard`（定性）、`kulczynski` | 主用 Bray；Jaccard 作稳健性 |
| 分解 | `betapart::beta.pair` → turnover vs nestedness | 问题涉及"替换 vs 嵌套"时必做 |

### 14 混合效应模型
| 选项 | 说明 |
|---|---|
| `random_structure` | `(1\|group)` 随机截距 / `(1 + x\|group)` 随机斜率 |
| R² 分解 | `glmm.hp`（缺包则跳过并提示） |
| 事后 | `emmeans` 边际均值 + 对比 |

结果表**必须**含：固定效应系数与 p、随机效应方差、AIC/BIC、收敛信息（`isSingular`）。

### 20 功能多样性
| 选项 | 说明 |
|---|---|
| `trait_input` | 原始性状 / 性状 PCA 主轴（**必须在 config 里声明来源，混用不可比**） |
| 指数 | FRic, FEve, FDiv, FDis, RaoQ, CWM（`FD::dbFD`） |
| 前置校验 | 性状数 < 各群落最小物种数（否则 FRic 不可算）；`NA → 0`（多度矩阵） |
| 功能β | `betapart::functional.betapart.core` |

### 30 建树
| 选项 | 说明 |
|---|---|
| 校名 | `plantlist::TPL`（缺包则用本地对照表，**不擅自替换学名**） |
| 建树 | `V.PhyloMaker2`（GBOTB.extended.TPL, S3）；`V.PhyloMaker` v1 作备选 |
| 树可视化 | `ggtree` 环形树。**主出 = 分组着色树**（对齐论文 Fig S1）：season 走 Set2 同族 `#66C2A5/#FC8D62/#8DA0CB`，habitat fill 走 `#1F77B4/#D62728/#9467BD`，tip 字号 3，140×133mm。简单树（`geom_tiplab2(size=3)` 无着色）为可选补充 |
| 分组来源 | `opts$tree_group`（family/genus，来自 `04_species_list.csv`）或 `opts$tree_group_file`（物种→season/habitat 对照表，出 Fig S1 完全等价图需要它） |

**缺数据的纪律：只报告缺口（哪些物种不在 GBOTB、哪些学名存疑），不自动替换、不自动补。**
**树图不套 `pd_theme()`**（pitfalls E6）。

### 31 PD / NTI / NRI
| 选项 | 说明 | 推荐 |
|---|---|---|
| `pd` | Faith's PD（`picante::pd`） | 必做 |
| `null_model` | `taxa.labels`（系统发育结构）/ `richness` / `independent.swap` | 默认 `taxa.labels`（与主流文献一致）；若强调环境梯度筛选，需说明并做敏感性分析 |
| `abundance.weighted` | TRUE/FALSE | 有可靠多度时用 TRUE |
| `runs` | 置换次数 | 测试 199，正式 ≥999（**执行前报时间预估**） |
| 输出 | `mntd.obs`, `mntd.obs.z`, `NTI = -z`, `mpd.obs.z`, `NRI = -z`, `SR` | — |

**判读**：`NTI/NRI > 2` 系统发育聚集；`< -2` 发散；`|z| ≤ 2` 随机。

### 32 系统发育信号
| 选项 | 说明 |
|---|---|
| 统计量 | `phylosignal`（Abouheif's Cmean, Moran's I, Blomberg's K, Pagel's λ） |
| 置换模拟 | `phyloSim(nsim = 100, reps = 99)` —— **耗时，先报预估** |
| 性状输入 | 原始性状或 PCA 主轴，**声明来源** |
| 缺失 | 需 `phylosignal` + `phylobase`；缺包则整模块跳过并提示安装 |

### 40 排序与群落差异
| 选项 | 说明 | 推荐 |
|---|---|---|
| 排序 | `metaMDS`（Bray，k=2，记录 stress） | stress > 0.2 必须提示"排序不可靠" |
| 分面策略 | 单图 + 组合椭圆 / 按因子分面 | **论文 Fig 2 = 两分面上下拼**（按 Habitat 分面 / 按 Season 分面）+ `(a)(b)`，180×190mm |
| 配色 | `nmds_season` `#FF9C7A/#E8754A/#4BA4C9`；`nmds_habitat`；组合 `nmds_habseas` 9 色 | 按着色因子身份自动取 |
| 椭圆 | `stat_ellipse(type="norm", level=0.95, linetype="dashed", alpha=0.6, linewidth=1)` | 论文参数 |
| PERMANOVA | `adonis2` 加性 vs 交互（`by="margin"`） | 先加性看主效应，再看交互；报 R² |
| ANOSIM | 与 PERMANOVA 交叉验证 | 组内异质性高时 ANOSIM 偏保守，需说明 |
| 两两比较 | `pairwiseAdonis`（校正方法随 config） | 必做，输出 R 与校正 p |

### 41 方差分解
`vegan::varpart`。需保证解释变量矩阵之间**不共线**；输出各分量的调整 R² 与显著性（`anova.cca` 检验）。
注意：`div.varpart.csv` 类文件常缺随机因子列，需先检查。

### 50 PCA / HCPC
标准化 → PCA → 记录各轴解释率与载荷 → HCPC 聚类（簇数由用户定）。

### 51 热图
| 选项 | 说明 |
|---|---|
| 数据 | 物种×性状（z-score 后） / 性状×性状（相关系数矩阵） |
| 聚类 | `euclidean` + `complete`（可在 config 改） |
| 配色 | 蓝-白-绿（`#3A558C` / `#ffffff` / `#75D155`，沿用原文，走 `pd_pal("heatmap")`） |
| 尺寸 | 性状-物种 → `s4_trait_sp` 180×80mm；性状-性状 → 自适应方阵 |
| 合成 | 若 50 模块已出 biplot，自动合成 **Fig S3 等价图**（PCA \| 热图，180×150mm，标 `(a)(b)`） |

### 50 PCA
| 选项 | 说明 |
|---|---|
| biplot 配色 | `col.var = #0E5484`, `col.ind = #6CBF59`（论文实测） |
| 显示参 | `arrow.size=1, alpha.ind=0.7, alpha.var=0.7, labelsize=2, repel=TRUE` |
| `opts$pca_color_by` | `"none"`（默认）\| `"signal"` —— Fig 6 式按系统发育信号显著性着色：显著 `#FF0000`，不显著 `#000000`。需传 `sig_traits` 或设 `opts$pca_sig_traits` |
| 尺寸 | biplot → `fig6_pca` 180×170mm |

### 60 绘图
| 选项 | 说明 | 推荐 |
|---|---|---|
| 尺寸 | 论文图尺寸见 `config$plot$fig_size`；通用双栏 190mm / 单栏 90mm | 默认走 `fig_size` |
| 字号 | pt 绝对值（基准 9pt）；论文 `rel(1.2)/rel(1.5)` 已换算 `base_pt+2 / base_pt+5` | 不用 `rel()` |
| 箱体样式 | 论文 Revise 色板：fill `#00AFBB` 统一、边框黑、`alpha=0.7`、`width=0.5`；散点 `#FC4E07`、`size=1.5` | 走 `pd_pal("box_fill"/"box_point")` |
| 统计标注 | Tukey 字母 / 显著性括号 / 无 | **按分组数自动选（2026-09-25 规则）**：>4 组 → 字母；≤4 组 → 括号。双因素恒字母（combo 横轴没有对应括号画法）。`opts$sig_label` 显式写了就不自动。见 pitfalls H12 |
| **拼图（硬规则）** | **同类多图必须合成一张**：交互图×N → `60_interaction_panel`；箱线 Fig3/4/5 → `60_box_panel` 4 面板。`pd_compose()` 打 `(a)(b)`；base 图形用 `pd_combine_pdfs()` | 散件不落地 |
| **例外** | ① 树图变体各自成文件（写论文挑一张）② 论文图可裁（Fig3/4/5、S3/S4 合一后投稿前裁开）③ 真冗余必消 | 见 pitfalls E8 |
| `plot$save_singles` | `FALSE`（默认）只出合并图；`TRUE` 两者都留，便于逐图检查 | 检查期开 TRUE |
| 论文等价图 | `config$plot$paper_figs` 驱动，4 面板合一 | 自动出 |

### 90 地图
**降级版**：行政区底图 + 采样点 + 指北针/比例尺。
用 `sf` + `ggspatial`，底图边界由用户提供（GeoJSON/shapefile 路径写进 config）。
**不联网、不用 mapbox API、不硬编码密钥。** DEM 高程 / 河流 / 嵌图留作扩展。

---

## 6. 约束排序 / 回归 / 相关（Diversity 2023 补齐项）

### 42_rda · DCA + RDA/CCA + envfit
**科学问题**：环境因子如何解释群落组成变异？
**方法**：先 `vegan::decorana`（DCA）看梯度长度 —— 最大梯度 **>4 用 CCA；3–4 皆可（本包取 RDA）；<3 用 RDA**（抄硕士论文《代码简述》）。
多度 **Hellinger 变换**（`decostand "hellinger"`，不转则长尾物种主导），环境变量 **z-score**。
`envfit`（999 置换）出各因子 R² 与 p；`permutest` 出整模型检验。
**输出**：`42_rda.xlsx`（dca_gradient / envfit / model_test / run_info）+ `42_rda_biplot.pdf`。
**biplot 美化 = Fig3b_dbRDA_rf_gam 面板 A 风格**（2026-09-25 用户拍板；来源 `03-生态学数据分析/R代码/3_environmental_drivers.R` L939–967）：
| 元素 | 参数 |
|---|---|
| 样方点 | **按组着色** `size=0.9, alpha=0.4, stroke=0`，`scale_colour_manual` 用 `palettes$rda_site`（柔和低饱和） |
| **样方/物种二选一** | `plot$rda_biplot_show`（**勾选时问用户**）：`"sites"` 默认 / `"species"` / `"both"`（仅样方<40 且物种<30 才采纳） |
| **物种** | 小方块 `shape=15`，同档 size/alpha，色 `#F37A70`；**只画点不画箭头** |
| 物种名 | **种数 < `plot$rda_sp_label_max`（默认 30）才标**；上百种只画点不标名 |
| **环境因子** | **只有它画箭头**：`#3182BD`、`linewidth=0.45`、`arrow(length=0.09cm, type="closed")` |
| **箭头长度归一** | `arrow_mul = 0.78 * site_radius / bp_radius`（最长箭头 = 样方云半径 0.78） |
| 环境标签 | 黑字 + **白描边**（`bg.colour="white", bg.r=0.12`），灰连接线 `grey55` |
| 零轴 | `linewidth=0.2, colour="grey90"`（浅灰细线，**不是点线**） |
| 轴标 | `sprintf("RDA1 (%.1f%%)", 100*eig/tot.chi)` —— **占总惯量**，一位小数 |
| 标题/副标题 | `RDA (Hellinger)` + `R²adj = x.xxx, p < 0.001` |
| 主题 | **`pd_theme_isme()`**（`theme_bw` + 无网格 + panel.border 黑 0.5 + Arial + 8/9pt）+ `coord_fixed()` + 图例内嵌右下 |
| 得分口径 | 图箭头 = `scores(display="bp")`；**表 7-1 的 RDA1/RDA2 = `ef$vectors$arrows`（单位长度）** —— 见 pitfalls H11 |
**口径必须写进 run_info**：Hellinger、z-score、DCA 阈值、置换次数。

### 43_regression · 线性回归散点
**科学问题**：单个环境因子与单个响应变量（多样性指数 / 群落结构变量）的线性关系？
**方法**：`stats::lm(y ~ env)` 逐对；R² = `summary(lm)$r.squared`，p = 斜率 t 检验 p。
**响应集**：`table$vars` + `response$alpha/func/phylo/**community**`（含株高/盖度/密度）。
**输出**：`43_regression.xlsx`（slope/intercept/R2/p/sig，按 R² 降序）+ `43_regression_scatter.pdf`（默认取 R² 最大的 4 对作多面板，面板内标 `R²=0.185*`）。

### 52_spearman · 指数间 Spearman 相关
**科学问题**：各多样性指数 / 群落结构变量之间是否冗余？
**方法**：`stats::cor.test(method="spearman")` 逐对 → r 矩阵 + p 矩阵（对角留空）。
**变量集**：`table$vars` + `response$alpha/func/phylo/**community**`。
**输出**：`52_spearman.xlsx`（r_matrix / p_matrix / run_info）+ `52_spearman_corrplot.pdf`（`corrplot.mixed`：下三角数字 r、上三角圆、蓝↔红）。
p 矩阵供 `tables.docx` 的 **t5**。

> **12 / 60 也吃 `response$community`**（Height/Coverage/Density）—— 组间比较箱线图、交互图、Tukey 字母都覆盖群落结构变量。
> **写新论文时因变量必须先和用户沟通**（SKILL.md 第 3 步），不代选。

### 图型 / 因子数 / 标注 —— 见 SKILL.md 第 3 步勾选表
这 4 项（图型、散点层、单/双因素、显著性标注）**在方法勾选时和用户商量**，不硬编码。
