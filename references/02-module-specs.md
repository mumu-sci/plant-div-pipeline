# 02 · 模块规格（函数签名 / 输入 / 输出 / 验收要点）

所有模块共用 `00_setup.R`。调用一律形如：
```r
res <- pd_run_<module>(CONFIG, dat)
```
`CONFIG` 来自 `config/config.R`；`dat <- pd_load_data(CONFIG)` 只读一次，各模块共用。

---

## 00 `00_setup.R` — 基础设施（不是分析模块）

| 函数 | 作用 |
|---|---|
| `pd_init_locale()` | Windows 下把 `LC_CTYPE` 设为 `Chinese_China.utf8`（修中文路径解析，见 pitfalls A1） |
| `pd_setup(cfg)` | 建目录、开日志、存全局配置；**每个会话开头调用一次** |
| `pd_msg()` / `pd_warn()` | 控制台 + `logs/*.log` 双写；警告会进体检报告 |
| `pd_has(pkg)` / `pd_require(pkgs, module)` | 缺包时打印安装命令并返回 FALSE，**不抛错**（优雅降级） |
| `normalize_species(x)` | **学名主键唯一入口**：trim + 空白→下划线 + 去重复下划线 |
| `pd_read_table(path)` | csv/xlsx 自适应；csv 依次尝试 UTF-8-BOM / UTF-8 / GBK |
| `pd_load_data(cfg)` | 读五文件 → 多度矩阵（行=样方、列=学名）、元数据（因子按 `ordered_levels` 排序）、性状、对照表、树；同时做 NA→0、全 0 列剔除、稀有种剔除、sample_id 一一对应、树 tip 规范化 |
| `pd_species_align(dat)` | 四方物种名对齐表（供体检与各模块复用） |
| `pd_theme(base_pt, lang, grid, family, compact)` | 出版主题：**pt 绝对字号** + **gray80 主网格**（对齐论文 `theme_bw`）；`grid="none"` 关网格（地图）；`family` 切 Times（Fig 5）；`compact=TRUE` 紧凑字号（多面板诊断图）。论文 `rel(1.2)/rel(1.5)` 已换算 `base_pt+2 / base_pt+5` |
| `pd_pal(name, n)` | 命名色板注册表（`config$plot$palettes`）。论文图调用点专用：`box_fill` `box_point` `tree_branch` `tree_tip` `nmds_season` `pca_var` …。缺名回退 `pd_palette()` |
| `pd_fig_size(name)` | 论文图物理尺寸注册表（`config$plot$fig_size`），返回 `list(width_mm, height_mm)` |
| `pd_compose(plots, ncol, nrow, tags, ...)` | patchwork 统一拼图出口，`tag_levels="a"` 打 `(a)(b)`，`guides="collect"`。**同类多图必走此口** |
| `pd_combine_pdfs(paths, stem, module)` | base/grid 图形文件级合并（`pdftools::pdf_combine`，回退 `qpdf`）。合并后按 `plot$save_singles` 决定是否删散件 |
| `pd_cached(stem, key, expr)` | **模块级 .rds 缓存**（pitfalls E9）：包住昂贵计算，绘图总是重画。`key=NULL` 自动按数据 md5 + opts 算 |
| `pd_cache_key(cfg)` / `pd_cache_get` / `pd_cache_set` | 缓存原语；失效键 = 数据 md5 + 统计 opts 签名（样式参数不进键） |
| `pd_run_diagnostics()` | 跨模块胶水：QQ + impute → `01_data_diagnostics.pdf` |
| `pd_save_pdf(p, stem, module, w_mm, h_mm, size)` | 输出 `figures/<module>_<stem>.pdf`；新增 `size="fig2_nmds"` 等走 `fig_size` 注册表 |
| `pd_write_table(df, stem, module)` | 输出 `results/<module>_<stem>.xlsx`；**同名时加时间戳**，不静默覆盖；拒绝写入矩阵列 |
| `pd_write_matrix(mat, stem, module)` | 距离矩阵单独存 `.rds` + 长表 `.csv`（绝不并入结果总表） |
| `pd_stress_note(stress)` | NMDS stress 判读（>0.2 报"不可靠"） |

---

## 01 `01_data_health.R`

`pd_run_data_health(CONFIG, dat = NULL, save = TRUE)` → 隐式返回 `health`

**输入**：无（内部 `pd_load_data`）
**输出（1 个 xlsx，多 sheet）**：`input_fingerprint` / `species_alignment` / `suspect_synonyms` / `invisible_chars` / `design_cells` / `design_levels` / `var_diagnostics` / `method_recommend` / `warnings`
**验收**：能逐名列出四方物种差集；`var_diagnostics` 里 `normal_ok` 是"p > alpha 才算正态"（pitfalls D4）；
`invisible_chars` 给出 NBSP / 零宽 / BOM / 制表符的命中位置（pitfalls G11）

---

## 10 `10_alpha.R`

`pd_run_alpha(CONFIG, dat = NULL)` → `list(alpha, distances)`
**计算**：`S`(specnumber)、`Shannon`、`Simpson`、`Pielou = Shannon/log(S)`、`N_total`；个体数差异 > 2 倍时同时给 `S_rarefy`
**输出**：`results/10_alpha_indices.xlsx`；距离矩阵走 `pd_write_matrix`（`10_dist_bray.rds` 等）
**验收**：180 行；Shannon/Pielou/S 与论文原表对照应能对上（验证脚本已做）

## 11 `11_beta.R`

`pd_run_beta(CONFIG, dat = NULL)` → `list(distances, partition_summary, beta_partition)`
**选项**：`response$beta` 决定算哪几个距离；`opts$beta_partition` 决定是否做 turnover/nestedness
**输出**：`11_partition.xlsx` + 各距离 `.rds`

## 12 `12_tests.R` — 组间比较（核心）

`pd_run_tests(CONFIG, dat, method = NULL, vars = NULL, health = NULL)`

| `method` | 实现 | 输出 sheet |
|---|---|---|
| `anova_tukey` | `aov(y ~ f1 * f2)` + `anova` + `multcomp` Tukey 字母 | summary / group_means / posthoc / letters |
| `nonparam_srh` | `rcompanion::scheirerRayHare` + `nemenyiTest` | 同上 |
| `kruskal_dunn` | 每个因子分别 `kruskal.test` + `dunn.test(method=...)` | 同上 |
| `lmm` | 转交 `14_mixed_model` | — |

**关键**：`cld()` 的参数名是 `alpha`（不是 `alpah`，pitfalls D1）；字母表写入 `letters` sheet，`60_plots` 直接消费。
**验收**：`summary` 表含 F/H、df、p、sig、效应量；`letters` 表每组一个字母。

## 14 `14_mixed_model.R`

`pd_run_mixed(CONFIG, dat, vars = NULL)`
**输入**：`design$factors`、`opts$random_structure`（如 `"(1|Site)"`）
**输出**：`coefficients` / `anova`（Satterthwaite）/ `model_fit`（R²m、R²c、AIC、BIC、奇异拟合标记）/ `emmeans` / `r2_decomposition`
**降级**：缺 `glmm.hp` → `r2_decomposition` 为空 sheet + 明确提示，不报错
**验收**：`model_fit` 有 `singular` 列（TRUE 时会 WARN）

## 15 `15_temporal.R`

`pd_run_temporal(CONFIG, dat, vars = NULL)`
**计算**：DW 检验做两版口径 —— `DW_numeric`（时间编码为 1,2,3）与 `DW_factor`（复现原代码的 `lm(y ~ Season)`）；显著者按样点分组做一阶差分
**输出**：`15_dw_autocorr.xlsx`（`dw_test` + `diff_values`）

## 20 `20_fd.R`

`pd_run_fd(CONFIG, dat, traits = NULL)`
**计算**：`FD::dbFD` → `nbsp / sing.sp / FRic / FEve / FDiv / FDis / RaoQ / CWM_*`；可选 `betapart::functional.betapart.core`
**前置校验**：多度 vs 性状物种对齐；`NA→0`；零方差性状剔除；**样方内物种数 ≤ 性状数时提示 FRic 不可算**
**口径记录**：`opts$trait_input` 写进结果（pitfalls C3）
**验收**：物种对齐数被打印且写入日志

## 21 `21_impute.R`

`pd_run_impute(CONFIG, dat, traits = NULL)`
**计算**：`missForest`，输出 `imputed`（`21_traits_imputed.csv`）+ `impute_report`（插补前后缺失数）+ OOB NRMSE + 前 4 个缺失最多性状的分布对照图
**纪律**：结果**不自动流入下游**，需要时显式传入

## 30 `30_phylo_build.R`

`pd_run_phylo_build(CONFIG, dat)`
**流程**：`04_species_list.csv` → sp.list（species/genus/family）→ 清理 genus/family 的不可见字符（`pd_strip_invisible`）→ 报告缺 genus/family 的物种（**不自动补**）→ `V.PhyloMaker2`（缺则回退 `V.PhyloMaker` v1）→ 写 `30_built_tree.tre` + 环形树 pdf（含按科/属/生境分组着色）
**配置**：`opts$tree_scenario` = `S1|S2|S3`（默认 S3）
**建树用时基准**（封丘 150 种，R 4.5.2）：巨树 `GBOTB.extended.TPL`（74,529 tips）载入 + 建树 ≈ **0.8 分钟**
**降级**：两个包都没装 → 输出 `30_splist_ready.xlsx` 供装包后复用
**验收**：tip 数、是否有枝长被明确报告（无枝长 → PD/MNTD 不可用）；
`results/30_invisible_chars.xlsx` 记录清理了哪些不可见字符（pitfalls G11）

## 31 `31_pd_nti_nri.R`

`pd_run_pd_nti_nri(CONFIG, dat, tree = NULL)`
**计算**：`pd()`；`ses.mntd`/`ses.mpd`（`null_model`、`abundance.weighted`、`runs`）→ `NTI = -mntd.obs.z`、`NRI = -mpd.obs.z`，并给 `pattern`（聚集 >2 / 发散 <-2 / 随机）
**输出**：`31_runs199_test.xlsx`（表名带 `runs` 与 `final/test` 标记，避免误引）
**长任务纪律**：执行前打印耗时提示；测试 199、正式 ≥999

## 32 `32_phylo_signal.R`

`pd_run_phylo_signal(CONFIG, dat, tree = NULL, traits = NULL)`
**计算**：`phyloSignal(method="all")`、`lipaMoran`、可选 `phyloCorrelogram`（默认 FALSE，耗时）
**降级**：缺 `phylosignal`/`phylobase` → 输出对齐好的 `32_traits_aligned.xlsx` + `32_tree_aligned.tre`，装包后可原样复跑

## 40 `40_ordination.R`

`pd_run_nmds(CONFIG, dat)`
**计算**：`metaMDS`（记录 stress 并判读）→ `adonis2`（加性/交互，`by` 可配）→ `anosim`（交叉验证）→ **内置两两 PERMANOVA**（`pd_pairwise_permanova`，不依赖 `pairwiseAdonis`）
**输出**：`nmds_points` / `permanova` / `anosim` / `pairwise_permanova` / `run_info` + NMDS pdf
**验收**：`run_info` 里记录距离、置换次数、模型形式、stress

## 41 `41_varpart.R`

`pd_run_varpart(CONFIG, dat, response = "community", vars = NULL, coding = NULL)`
**计算**：`vegan::varpart`。分类因子按 `coding="dummy"`（推荐）哑变量化，或 `"numeric"` 复现旧的连续编码口径
**输出**：`explained`（各集合单独/条件 adj.R²）+ `fractions`（各分片）

## 50 `50_pca_hcpc.R`

`pd_run_pca_hcpc(CONFIG, dat, traits = NULL, ncp = 5)`
**计算**：`FactoMineR::PCA`（行完整删除，剔除零方差性状）→ 特征值/载荷/贡献/得分 + `fviz_pca_biplot` + 碎石图 → `HCPC`（簇数 `opts$hcpc_nclust`）
**输出**：`eigenvalues` / `loadings` / `contributions` / `species_scores` / `hcpc_clusters`

## 51 `51_heatmap.R`

`pd_run_heatmap(CONFIG, dat, traits = NULL, which = c("species_trait","trait_trait"))`
**输出**：`51_species_trait_heatmap.pdf`、`51_trait_trait_corr.pdf`、`51_trait_corr.xlsx`
**副产物**：报告显著相关对数（按 n 与 alpha 算 r 临界值）
**注意**：`pheatmap` 画进显式 pdf 设备（不是 ggsave）

## 60 `60_plots.R`

`pd_run_plots(CONFIG, dat, tests = NULL)`
**图型**：`pd_boxplot()`（单因子，可选分组填充、可选字母标注）、`pd_boxplot_combo()`（因子组合横轴 + 字母）、`pd_quick_box()`（交互式单图）
**输入**：`tests$letters`（来自 12 模块），保证图上字母与统计结果同源
**输出**：按 `alpha/func/phylo` 分组的拼图 pdf，尺寸随面板数自适应

## 90 `90_map.R`

`pd_run_map(CONFIG)`
**输入**：`config$map$boundary`（GeoJSON/shapefile，必需）、`sites_csv`（含 lon/lat，可选）
**实现**：`sf` 底图 + 采样点 + `ggspatial` 比例尺/指北针；`xlim/ylim` 可裁剪
**纪律**：不联网、无 API 密钥；未提供边界 → 只提示不报错

---

## 缺包降级一览

| 缺失包 | 影响模块 | 行为 |
|---|---|---|
| `glmm.hp` | 14 | 跳过 R² 分解，其余正常 |
| `MCMCglmm` | 14（备选口径） | 未实现，跳过 |
| `missForest` | 21 | 整模块跳过 + 安装提示 |
| `phylosignal`/`phylobase` | 32 | 输出"就绪包"后跳过 |
| `plantlist` | 30 | 跳过校名（不擅自改学名） |
| `V.PhyloMaker2`/`V.PhyloMaker` | 30 | 输出 sp.list 后跳过 |
| `betapart` | 11 / 20 | 跳过 β 分解 |
| `dunn.test`/`rcompanion` | 12 | 对应方法跳过 |
| `rnaturalearth` 等 | 90 | 不需要（降级版不联网） |

---

# 补充（2026-09-21 补建）：14 项遗漏内容与新增接口

对照原文代码补全了 14 项遗漏板块（+3 项部分覆盖）。逐项落点如下。

## 01 `01_data_health.R`
- 新增 `pd_qq_diagnostics()`：与原文 `qqPlot(lm(y ~ factor))` 等价，按**变量 × 因子分面**出图，面板角标 Shapiro p，非正态标红。产出 `figures/01_qq_normality.pdf` + `results/01_qq_shapiro.csv`。

## 20 `20_fd.R`
- 功能β：新增 **性状 PCA 降维回退**（`opts$fd_axis_fallback`、`opts$fd_axis_n`）。当"最小群落物种数 ≤ 性状数"导致凸包要求不满足时，自动改用前 k 个性状 PCA 主轴——**原文正是这么做的**（`trait-FD.N-part-III.csv` 就是 5 个主轴）。
- 功能β 结果按原文 `test.core.xlsx` 的写法，把 `functional.betapart.core` 的**每个组件单独写成一个 sheet**（`core_shared` / `core_not_shared` / …）。
- `run_info` sheet 记录 FD 性状数与功能β 性状输入（可追溯口径）。

## 30 `30_phylo_build.R`
- 新增 `pd_plot_tree_grouped()`：**分组着色的环形树**，复刻原文两个版本
  ① `groupOTU` 按 `family`/`genus` 着色（`opts$tree_group`）
  ② `treeio::full_join` + `geom_tree(aes(colour=))` + `geom_tippoint(shape=, fill=)`（`opts$tree_group_file` + 列名配置）

## 32 `32_phylo_signal.R`
- 修正 `phyloSignal(method="all")` 的返回结构：是 `list(stat=data.frame, pvalue=data.frame)`，行=性状、列=统计量（Cmean/I/K/K.star/Lambda）。输出宽表 + 长表（含 `pd_sig` 标记）。
- `lipaMoran` 输出改为完整的「物种 × 性状」长表 + 显著计数。
- 新增 **phylo4d 可视化套件**：`barplot`（phylo 树型）/ `dotplot`（cladogram）/ `gridplot`（fan） + **LIPA 显著着色版**。
  注意：`barplot.phylo4d` 等**未导出**，必须用 `getS3method` 取方法函数（已封装 `pd_get_s3`）。
- 新增 **`phyloSim` 模拟**（`opts$phylo_sim` / `phylo_sim_nsim` / `phylo_sim_reps`）：导出 `sim_stat`/`sim_pvalue`/`stat_names` 三个 sheet + 两张图（分开 / 堆叠 p 值）。
- `opts$phylo_signal_plot_traits`：只对前 k 个性状出单图（避免 37 个性状刷出几十张 pdf）。

## 40 `40_ordination.R`
- **NMDS 布局**：`opts$nmds_layout = combo | facet | both`。facet 模式出「按 Habitat 分面 / 按 Season 分面」两张 + `patchwork` 拼图（对应原文论文图）。
- `opts$nmds_shape`：指定用于点形状的因子。
- **两两 ANOSIM**：新增内置 `pd_pairwise_anosim()`，按"生境内比季节"和"季节内比生境"两个方向分层，输出 R / p / 校正 p（对应原文 `Habitat_anosim_two.xlsx`、`Season_anosim_two.xlsx`）。
- **ANOSIM 秩分布箱线图**：`pd_plot_anosim_rank()`，用 ggplot 重画（对应原文 `plot(anosim)`），Between 与各组秩并列 + R/p 标注。

## 41 `41_varpart.R`
- 新增 **Venn 图**（对应原文 `plot(varpart_result, bg=...)`）。解释矩阵在 `varpart` 里只能匿名绑定，图上标签是 X1/X2/X3，故**主标题里显式写出 X1/X2 对应哪个因子**。

## 60 `60_plots.R`
- **显著性括号**：`opts$sig_label = letters | bracket | none`，新增 `pd_boxplot_bracket()`。括号 p 值由 `pd_pairwise_p()` 提供，且**与主检验同源**：`anova_tukey/lmm → Tukey HSD`、`kruskal_dunn → Dunn(校正)`、其它 → `Wilcoxon + 校正`。**默认不用 t 检验**（原文对已判定非正态的数据用 t.test，口径矛盾）。括号 p 值另存 `results/60_pairwise_p_for_brackets.csv`。
- **交互效应图**：新增 `pd_interaction_plot()`（对应原文 `HH::interaction2wt`），不依赖 HH 包；由 `opts$interaction_plot` 控制。

## 00 `00_setup.R`
- **配色工具**：`pd_palette(name, n)` 支持 `custom` / ggsci 名称（`npg`、`aaas`、`nejm`…）/ `brewer:Dark2` / 直接颜色向量；`pd_show_palette()`；`rgb_to_hex()`。对应原文的 ggsci + RColorBrewer + rgbToHex 探索。
- **命名色板注册表**：`pd_pal(name, n)` 读 `config$plot$palettes`。论文图专用 token：`box_fill=#00AFBB`、`box_point=#FC4E07`、`tree_branch=Set2 #66C2A5/#FC8D62/#8DA0CB`、`tree_tip=#1F77B4/#D62728/#9467BD`、`pca_var=#0E5484`、`pca_ind=#6CBF59`、`pca_var_sig=#FF0000`、`nmds_season=#FF9C7A/#E8754A/#4BA4C9`、`map_point=#E9111A`、`heatmap=#3A558C/#ffffff/#75D155`。**色值全部来自论文 PDF 提色 / 原始 R 代码**。
- **尺寸注册表**：`pd_fig_size(name)` 读 `config$plot$fig_size`（论文 PDF MediaBox）：`fig3_shannon=263×125`、`fig5_pd_mntd=173×162`、`fig2_nmds=180×190`、`s1_tree=140×133`、`fig6_pca=180×170`、`s3_pca_heatmap=180×150`、`s4_trait_sp=180×80`。
- **拼图出口**：`pd_compose(plots, ncol, nrow, tags="a", tag_pt, guides="collect")` —— patchwork + `plot_annotation(tag_levels="a", tag_prefix="(", tag_suffix=")")`，tag 字号 `base_pt+2` 粗体。
- **新增 config 选项**：`plot$font_en`、`plot$tag_pt`、`plot$palettes`、`plot$fig_size`、`plot$paper_figs`、`opts$pca_color_by`、`opts$pca_sig_traits`。
- 新增 `pd_save_any()`：ggplot 走 ggsave，grid/base 对象走 cairo_pdf + print（phylosignal 的图两种都可能）。
- 新增 `pd_obj_to_df()`：任意对象 → 长表（用于多 sheet 导出）。

## 16 `16_mcmcglmm.R`（新增模块）
贝叶斯混合模型路线（对应原文的 `MCMCglmm` 那一段）：
- `MCMCglmm(fixed, random, family="gaussian")`，随机效应公式由 `opts$mcmc_random` 指定（如 `"~ Habitat + (1|Site)"`）
- 采样规模 `opts$mcmc_nitt / mcmc_burnin / mcmc_thin`，**执行前打印规模与提示**
- 输出：固定效应后验（post.mean / l-95%CI / u-95%CI / pMCMC / eff.samp）+ **`ci_excludes_0` 列**（科学的显著性判定：95% 可信区间是否跨 0）
- 方差成分：`summary()$Gcovariances` / `$Rcovariances`（**MCMCglmm 未导出 `VarCorr`**）
- R²：MCMCglmm 对 gaussian 不总返回 `r.squared`，缺失时按 Nakagawa 分解用后验均值自算
- 收敛诊断：DIC + **`autocorr()` 的后验一阶自相关**（Sol 与 VCV 各一列），≥0.1 报警 + 迹图 pdf

## 90 `90_map.R`（重写）
- **底图 + 采样点 + 嵌图 + 引线**（按用户决定，不做 DEM / 河流）
- 不联网、无 API 密钥；边界文件由 `config$map$boundary` / `$inset` 提供本地路径
- 经纬度列名自动识别（`lon/lng/longitude/经度` …）
- 嵌图与引线位置在 `[0,1]` npc 坐标里可配（`inset_x/y/w/h`、`line1_*`、`line2_*`）

## 本轮新增 config 选项汇总

| 选项 | 默认 | 说明 |
|---|---|---|
| `nmds_layout` | `both` | `combo` / `facet` / `both` |
| `nmds_shape` | `NA` | 用于点形状的因子 |
| `sig_label` | `letters` | `letters` / `bracket` / `none` |
| `interaction_plot` | `TRUE` | 是否出交互效应图 |
| `palette_name` | `custom` | `custom` / ggsci 名 / `brewer:名` |
| `fd_axis_fallback` / `fd_axis_n` | `TRUE` / `5` | 功能β 的 PCA 降维回退 |
| `phylo_signal_plot_traits` | `5` | 32 出图性状数 |
| `phylo_sim` / `phylo_sim_nsim` / `phylo_sim_reps` | `FALSE` / `100` / `99` | phyloSim（长任务） |
| `tree_group` | `family` | 环形树分组列 |
| `tree_group_file` + `tree_group_label_col/color_col/shape_col` | `NA` | 分组表版本② |
| `mcmc_nitt` / `mcmc_burnin` / `mcmc_thin` / `mcmc_random` | `13000` / `3000` / `10` / `NA` | MCMCglmm |
| `map$inset`、`map$county_lon/lat`、`map$inset_*`、`map$line*_*` | — | 地图拼接与引线 |

---

## 42_rda · DCA + RDA/CCA + envfit
```
pd_run_rda(cfg, dat, save) -> list(model, envfit, dca, envfit_table, figure, method)
pd_env_join(dat, cfg)      -> list(df, envs, id)     # meta ⋈ files$env（按 sample_id）
pd_dca_gradient(veg)       -> data.frame(axis, gradient_length)   # SD 单位
pd_plot_rda_biplot(mod, ef, grp, site_scores, cfg)  -> ggplot
```
输出 `results/42_rda.xlsx`（`dca_gradient` / `envfit` / `model_test` / `run_info`）+ `figures/42_rda_biplot.pdf`。
口径写进 `run_info`：Hellinger + env z-score + DCA 阈值（>4 CCA；3–4 取 RDA；<3 RDA）+ 置换次数。

**envfit sheet 列**：`env, r, R2, p, sig, RDA1, RDA2`
- `RDA1/RDA2` = `ef$vectors$arrows[,1:2]` **单位长度方向余弦**（`RDA1²+RDA2²=1`）→ 供 **t7**
- 图箭头另用 `scores(mod, display="bp")`（长度∝拟合优度）—— 两者不同，见 pitfalls H11

**biplot 美化**：**Fig3b_dbRDA_rf_gam 面板 A 风格**（2026-09-25）——
样方按组着色（`size=0.9, alpha=0.4, stroke=0`，`palettes$rda_site`）/ **物种小方块 `#F37A70`、只画点不画箭头** /
**只有环境因子画箭头**（`#3182BD`, `linewidth=0.45`, `arrow(length=0.09cm, type="closed")`）/
**箭头长度归一** `arrow_mul = 0.78 * site_radius / bp_radius` / 标签黑字白描边 / 零轴 `grey90` 细线 /
轴标一位小数且**占总惯量** / 标题 `RDA (Hellinger)` + 副标题 `R²adj, p` / `pd_theme_isme()` + `coord_fixed()` + 图例内嵌。

**物种名**：种数 < `plot$rda_sp_label_max`（默认 30）才标；上百种只画点不标名。
旧口径（MDPI / 硕士论文 Fig7-1）见 pitfalls H11 备注。

## 43_regression · 线性回归散点
```
pd_run_regression(cfg, dat, save, n_panel = 4) -> list(table, figure)
pd_lm_pairs(df, ys, envs)  -> data.frame(y, env, n, intercept, slope, ..., R2, adj_R2, p, sig)
pd_plot_lm_scatter(df, y, e, r2, p, cfg) -> ggplot   # 面板内标 R²=0.185*
```
输出 `results/43_regression.xlsx` + `figures/43_regression_scatter.pdf`（R² 最大的 n_panel 对作多面板）。

## 52_spearman · 指数间 Spearman 相关
```
pd_run_spearman(cfg, dat, save) -> list(r, p, r_matrix, p_matrix, figure)
pd_spearman_mat(df, vars) -> list(r, p, vars)         # 对角 NA
pd_spearman_p_table(pmat) -> data.frame               # 供 70 的 t5
```
输出 `results/52_spearman.xlsx`（`r_matrix` / `p_matrix` / `run_info`）+ `figures/52_spearman_corrplot.pdf`
（`corrplot::corrplot.mixed(lower="number", upper="circle", diag="n")`，见 pitfalls H3）。

## 70_paper_tables · 表 t4/t5/t6/t7/t8/s3/s4
```
pd_table_t4(ab, mt, cfg)          -> flextable   # 优势种重要值（组内均值→归一 %）
pd_table_t5(pmat, cfg)            -> flextable   # Spearman p 矩阵（对角留空）
pd_table_t6(envfit_tab, env_df, cfg) -> flextable # 环境因子 M±SD / R² / p
pd_table_t7(envfit_tab, cfg)      -> flextable   # RDA Monte-Carlo：RDA1/RDA2/R²/p（← 硕士论文表 7-1）
pd_table_t8(group_means, cfg)     -> flextable   # ★ 时间×分组 mean±SD，多指标纵向堆叠（← Plant and Soil S3–S6）
pd_table_s3(base, cfg)            -> flextable   # ★ 并排双栏基线描述（← Plant and Soil S1）
pd_table_s4(sp_list, cfg)         -> flextable   # ★ 物种名录 Latin/Genus/Family/Order（← Plant and Soil S2）
pd_baseline_stats(dat, cfg)       -> data.frame  # ★ s3 的数据准备（全体样地合并 mean±SD）
pd_table_vars(cfg, cols)          -> list(disp, act)   # 论文名 ↔ 实际列名（别名解析）
```
`pd_run_paper_tables(cfg, which = c("t1".."t7","t8","s1".."s4"), dat = NULL, save = TRUE)`。
默认 12 张：`t1,t2,t3,s1,s2,t4,t5,t6,t7,t8,s3,s4` → 显示号 Table 1..12。

**t7 精度**：RDA1/RDA2 = 5 位小数；R² = 4 位小数；p = `pd_fmt_p("lt001")`（`<0.001 ***`）。
**t7 缺列降级**：`envfit` 表没有 `RDA1/RDA2` 列（旧版 42 的输出）→ 跳过 + 登记 `skipped`，不造数。

**t8（2026-09-25）**：行 = `cfg$design$time` 的水平（示例 Season），列 = 另一因子的水平（示例 Habitat），
单元格 `pd_fmt_mean_sd`；多指标纵向堆叠、指标名只写首行（`merge_v`）。
数值与 **s2 同源**（`results/12_<method>.xlsx:group_means`），只重排**不重算**。
指标集 = `table$t8_vars`。**需双因素**，单因素自动跳过并提示改用 s2。
论文原版是 Month×干扰（6 月 × 6 处理），skill 用 `design$time`（Season）替代 Month —— 不搬 Month。

**s3（2026-09-25）**：全体样地**合并**（不分组）的 `mean±SD`，拆两栏并排省版面。
指标集 = `table$s3_vars`，缺省 = `response` 四组 + `opts$env`。
单位走 `table$community_units` / `table$env_units`（缺则不带括号）。
**缺列就跳过该指标，不造数。**

**s4（2026-09-25）**：`cfg$files$species` 的物种名录。`order` 列**缺则整列省略**（优雅降级）。
不自动从 V.PhyloMaker2 的树里猜 Order（「缺数据只报告不动手」）。

## 新增配置项

| 键 | 默认 | 说明 |
|---|---|---|
| `response$community` | `c("Height","Coverage","Density")` | 群落结构变量（株高/盖度/密度）；12/52/60/43 都吃这组。**写新论文时因变量要和用户沟通** |
| `response$alpha` | `c("Shannon","Pielou","S","Simpson")` | ★ 2026-09-25 加 `Simpson` |
| `response$phylo` | `c("PD","mntd","mpd","NTI","NRI")` | ★ 2026-09-25 加 `NTI`/`NRI`（系统发育结构指数） |
| `opts$enrich_meta` | `TRUE` | ★ 把 `results/` 已算好的响应指数并进 meta（只并内存、不写 CSV）。见 pitfalls H14 |
| `opts$sig_label` | `NULL` | ★ 显著性标注。`NULL` = 按分组数自动（>4 组字母 / ≤4 组括号）；显式写 `letters\|bracket\|none` 就不自动。见 pitfalls H12 |
| `table$t8_vars` | `c("Height","Coverage","Density")` | ★ t8 纵向堆叠哪几个指标（论文 S3 是群落结构，S6 是 NRI/NTI） |
| `table$s3_vars` | `NULL` | ★ s3 的指标集；`NULL` = `response` 四组 + `opts$env` 自动合 |
| `table$which` | `NULL` | ★★ **出哪几张三线表，必须先和用户沟通、不默认全出**（用户 2026-09-25）。`NULL` = 兜底全出 12 张并打提示；填了就只出填的那几张。可选 `t1 t2 t3 s1 s2 t4 t5 t6 t7 t8 s3 s4` |
| `plot$box_type` | `"box"` | `box` \| `beeswarm` \| `both` —— 组间比较图型（**勾选时问用户**） |
| `plot$points` | `"jitter"` | `jitter` \| `beeswarm` \| `none` —— 箱体内散点层（**勾选时问用户**） |
| `plot$rda_sp_scale` | `2` | RDA biplot 物种得分放大倍数（原文 `*2`，注释留旋钮） |
| `plot$rda_sp_label_max` | `30` | 物种名标注阈值：种数 **< 此值**才标名（论文 47 种标了）；上百种只画点不标名 |
| `plot$rda_biplot_show` | `"sites"` | ★ 双标图显示什么 —— **二选一，勾选时问用户**：`sites`（默认，只出样方点）\| `species`（只出物种点）\| `both`（样方<40 且物种<30 才采纳，否则自动降级） |
| `plot$rda_pt_size` / `$rda_pt_alpha` | `0.9` / `0.4` | RDA 点大小/透明度（Fig3b-A 的 `PT_SIZE_STD`/`PT_ALPHA_STD`） |
| `plot$s_tick`/`$s_ttl`/`$s_leg`/`$s_ann` | `8`/`9`/`7.5`/`7.5` | `pd_theme_isme` 字号（pt，绝对值） |
| `plot$palettes$rda_sp_point` | `"#F37A70"` | RDA 物种点色 |
| `plot$palettes$rda_env_arrow` | `"#3182BD"` | RDA 环境箭头蓝（Fig3b-A 原色） |
| `plot$palettes$rda_site` | `c("#60859E","#B98079","#959BB0","#989898")` | 样方点色板（Fig3b-A 的 `cols_veg` 原色） |
| `plot$palettes$rda_env_arrow` | `"#24BDC0"` | RDA 环境箭头色（毕业论文原色） |
| `plot$palettes$rda_site_shape` | `1:18` | RDA 样方点形状（`scale_shape_manual`） |
| `design$factor_mode` | `"double"` | `double` = c(Habitat, Season) \| `single` = c(Season)（**勾选时问用户**）；由 `pd_design_factors()` 统一解析 |
| `files$env` | `data/05_env_simulated.csv` | 环境表（可选）。**示例这份是模拟数据** |
| `opts$env` | `c("pH","AK","AP","AN","SOM","SMC")` | 哪些列是解释变量 |
| `table$vars` | `c("Shannon","FRic","PD","SES.MNTD")` | 表格用的响应变量（**论文显示名**，`pd_table_vars` 会解析成实际列名）。**新论文要和用户沟通后改** |
| `table$factors` | `NULL` | 覆盖 `design` 的因子；NULL = 跟 `pd_design_factors()` |
| `table$t4_group` | `"Season"` | t4 按哪一列分组（列名由其水平决定） |
| `table$iv_threshold` | `1` | t4 入选阈值（全数据平均 IV%，超过才进表） |
| `table$env_units` | `list(pH="-", AK="mg/kg", ...)` | t6 的单位字典；没有留 `-` |
| `table$community_units` | `list(Height="cm", Coverage="%", Density="株·m⁻²")` | community 响应的单位；缺则 `-` |
| `table$captions$t7` / `$footnotes$t7` | 英文题注 | 表 7-1 的题注与星号脚注（中文原题注见 04-paper-tables.md） |

## 单因素模式下的行为

| 模块 | `factor_mode="single"` 时 |
|---|---|
| 12 / 14 / 40 / 60 | **本就支持**（`f2=NA` 分支、`cellv=f1` 单层、单因子 PERMANOVA 公式、交互图跳过） |
| **70** | T1 只出 overall 两两（ANOSIM+PERMANOVA 仍并排）；T2 行只有 `f1`/`Residual`；T3 行只有 `f1`（无交互）；S2 行只有 f1 各水平；S1 不受影响 |
| 41 varpart | **优雅跳过**（`vegan::varpart` 需 ≥2 组解释变量，单因素下无物可分）—— 文档已注明 |
