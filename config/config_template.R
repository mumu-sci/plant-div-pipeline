# ============================================================
# plant-div-pipeline · 配置模板
# 用法：复制到 <论文项目>/config/config.R，按实际数据修改。
# 所有模块只读本文件，不把参数写在模块内部。
# ============================================================

CONFIG <- list(

  # ---------- 项目标识 ----------
  project = "FQ2012",
  note    = "封丘植物多样性：季节 × 生境",

  # ---------- 路径（相对项目根目录，或绝对路径） ----------
  paths = list(
    root    = ".",
    data    = "data",
    code    = "code",
    results = "results",
    figures = "figures",
    logs    = "logs",
    cache   = "cache"      # 模块级 .rds 缓存（见 pitfalls E9）
  ),

  # ---------- 五个契约文件 + 环境数据（可选） ----------
  # 默认指向 skill 自带的示例数据 data/（仅用于跑通示例）。
  # 新论文：把 data/ 换成你自己的数据，并把下面的路径改指到你的 <论文项目>/data/
  files = list(
    abundance = "data/01_abundance.csv",
    meta      = "data/02_sample_meta.csv",
    traits    = "data/03_traits.csv",     # 无则置 NA
    species   = "data/04_species_list.csv", # 无则置 NA
    phylo     = "data/99_phylo.tre",       # 无则置 NA
    env       = "data/05_env_simulated.csv" # 可选：样方级环境/协变量表
                                            # ⚠️ 示例这份是【模拟数据，非实测】（见文件首行注释）
                                            # 新论文请填实测值（表头模板 assets/05_env_template.csv）
  ),

  # ---------- 键 ----------
  key = list(
    sample_id = "sample_id",   # 多度矩阵与元数据表的第一列名
    species   = "species"      # 性状表第一列名
  ),

  # ---------- 实验设计（因子完全通用：名字与个数随数据） ----------
  design = list(
    factor_mode = "double",  # ★ 勾选时问用户（见 SKILL.md 第 3 步）
                             #   "double" = 双因素 c("Habitat","Season")，可拆交互作用
                             #   "single" = 单因素 c("Season")
                             #   与 factors 二选一：写了 factor_mode 以它为准（pd_design_factors）
    # ★★★ 采样设计 —— 【写新论文时必须先和用户沟通，不代选】（用户 2026-09-25）
    #   这一项决定：15_temporal 是否适用、LMM 随机效应用谁、置换要不要受限、ANOVA 是否够。
    #   三选一：
    #     "fixed_plot"   固定样方跟踪：同一样地跨时间重复采样（重复测量）
    #                    → 15_temporal 适用；LMM (1|plot)；需重复测量 ANOVA 或 LMM
    #     "fixed_site"   站固定、站内样方每季重选（示例数据 = 这种）
    #                    → 15_temporal 【不适用】；LMM (1|Site) 空间区组；独立样本 ANOVA 可用
    #     "independent"  全独立（站也每季重选）
    #                    → 15_temporal 不适用；不设随机效应；独立样本 ANOVA 正好
    sampling  = "fixed_site",
    factors   = c("Habitat", "Season"),  # 分组因子；第 1 个为"主因子"（factor_mode 未设时用这个）
    random    = "Site",                  # 随机效应分组；无则 NA。sampling="fixed_plot" 时通常是 plot
    time      = "Season",                # 时间因子（时序自相关用）；无则 NA
    ordered_levels = list(               # 需要固定顺序的因子；不需要则留空 list()
      Season  = c("Spring", "Summer", "Autumn"),
      Habitat = c("Woodland", "Hedgerow", "Filed road")
    )
  ),

  # ---------- 因变量分组（决定哪些指数进哪些模块） ----------
  response = list(
    # ★ Simpson 2026-09-25 并入默认响应集（10_alpha 一直在算，只是以前没进响应集）
    alpha = c("Shannon", "Pielou", "S", "Simpson"),
    beta  = c("bray", "jaccard"),
    func  = c("F.Ric", "F.Eve", "F.Div", "RaoQ"),
    # ★ NTI / NRI 2026-09-25 并入默认响应集（31_pd_nti_nri 一直在算，同上）
    phylo = c("PD", "mntd", "mpd", "NTI", "NRI"),
    # ★ 群落结构变量（硕士论文 height/coverage/density）—— 12/52/60/43 都吃这组
    #   写新论文时因变量要和用户沟通后填（SKILL.md 第 3 步）
    community = c("Height", "Coverage", "Density")
  ),

  # ---------- 统计选项 ----------
  opts = list(
    seed                = 20260101,      # 随机种子（置换检验、稀释、插补统一）
    alpha               = 0.05,          # 显著性水平（全包统一）
    multiple_adj        = "BH",          # 多重校正：BH | bonferroni | holm
    alpha_test          = "anova_tukey", # anova_tukey | nonparam_srh | kruskal_dunn | lmm
    include_interaction = TRUE,          # 双因素检验是否含交互项
    letter_method       = "cld",         # Tukey 字母标记：cld
    enrich_meta         = TRUE,          # ★ 把 results/ 已算好的响应指数并进 meta（Simpson/NTI/NRI…）
                                         #   只并内存、绝不改写 data/*.csv（封丘真数据有 md5 校验）
                                         #   要严格复现旧口径（只用 meta 原有列）就设 FALSE
    sig_label           = NULL,          # ★ 图上显著性标注。NULL = 按【分组数】自动选（默认，见下）
                                         #   letters | bracket（成对括号）| none  —— 显式写了就不再自动
                                         #   ★★ 自动规则（用户 2026-09-25）：分组数 > 4 → letters；
                                         #      ≤ 4 → bracket。原因：>4 组画括号会挤成一团看不清。
                                         #      别照搬论文的 p.format 精确 p / t.test / 只比对照（见 H12）
    interaction_plot    = TRUE,          # 是否出交互效应图（对应原文 HH::interaction2wt）
    random_structure    = NULL,          # ★ 混合模型随机效应。NULL = 按 design$sampling + design$random 自动推导
                                         #   （fixed_plot → (1|plot)；fixed_site → (1|Site)；independent → 不设）
                                         #   要随机斜率时显式写，如 "(Habitat|Site)"
                                         #   ⚠️ 这是【唯一】的随机结构入口；15/16 也从这里读（2026-09-25 统一）
    ref_levels          = list(),        # 参考水平，如 list(Habitat = "Hedgerow", Season = "Summer")
    fit_r2_decomp       = TRUE,          # 是否做 glmm.hp 方差分解（缺包自动跳过）
    distance            = "bray",        # 群落距离
    permanova_by         = "terms",      # ★ adonis2 的 by 参数。
                                         #   "margin" + 交互模型 → 只出交互行、丢主效应（实测）
                                         #   "terms"  → 主效应 + 交互 + Residual 全出，
                                         #              R² 与 EI 论文 Table 2 逐位一致
                                         #   （"margin" 只在加性模型下能出全主效应）
    permanova_model     = "interaction", # ★ 默认 interaction —— 与 12_tests 的 include_interaction=TRUE
                                         #   口径一致，也与 EI 论文 Table 2（含 Season*Habitat 行）一致。
                                         #   若设 "additive"，T2 不出交互行、Residual R² 会虚高（交互量被并进去）
    nmds_layout         = "both",        # combo（单图组合椭圆）| facet（按因子分面）| both
    nmds_shape          = NA,            # 用哪个因子区分点形状；NA = 不区分
    env                 = c("pH","AK","AP","AN","SOM","SMC"),
                                          # ★ 环境/解释变量列名（在 files$env 的表里）
                                          #   供 42_rda / 43_regression 用；42 也据此做 envfit
                                          #   示例这 6 个是【模拟数据】的列，新论文换成你的实测变量名
    beta_partition      = TRUE,          # betapart turnover / nestedness
    null_model          = "taxa.labels", # picante 零模型
    abundance_weighted  = TRUE,          # NTI/NRI 是否多度加权
    abundance_is_iv     = NA,            # ★ 多度矩阵是不是【重要值】（2026-09-25 口径声明）
                                         #   TRUE  → run_info 标「重要值」；Shannon/Simpson 是 IV 多样性、
                                         #           NTI/NRI 是 IV 加权、dbFD 的 a 是 IV（与文献 PA 版不可比）
                                         #   FALSE → 个体计数
                                         #   NA    → 自动判（各行和≈1 视为重要值）
    runs                = 999,           # 置换次数（测试用 199）
    restrict_perm       = NULL,          # ★ 区组受限置换（2026-09-25）。NULL = 自由置换（默认，生态学主流）
                                         #   设为列名（如 "Site"）→ permute::how(blocks = ...)，置换在区组内做
                                         #   适用：随机区组 / 重复测量设计，可交换性被区组破坏时
                                         #   实测 E2：本示例数据自由 vs 受限 0 翻转（效应太强、p 触底）
                                         #   取舍见 pitfalls I10

    # ==== 批 1 口径开关（2026-09-25）—— 每项都留 legacy 值可复现旧口径 ====
    # 统计量只搬运不发明；改了口径必须在 run_info / 题注里显式写出。
    dca_gradient        = "range1",      # ★ "range1"=DCA 第1轴物种得分极差（业界标准）
                                         #   "legacy_max4"=旧口径 max(rproj[,1:4])，会低估梯度、可能错选 RDA/CCA
    rda_scale           = FALSE,         # ★ vegan::rda 的 scale 是【标准化响应物种列】（不是解释变量）
                                         #   与 Hellinger 冲突、把稀有种权重加回来。默认 FALSE。
                                         #   TRUE = 旧口径（照抄硕士论文原代码），可复现
    mds_autotransform   = FALSE,         # ★ metaMDS 的 autotransform=TRUE 会静默 sqrt + Wisconsin，
                                         #   与 PERMANOVA/ANOSIM 的原始 Bray 【不同口径】。默认 FALSE。
    jaccard_binary      = TRUE,          # ★ vegdist("jaccard") 是否 binary=TRUE（定性 Jaccard）
                                         #   FALSE = 定量 Jaccard（Ružička），数值与文献定性版不同
    signal_p_adjust     = "BH",          # ★ 32 系统发育信号多检验校正（5 统计量 × N 性状）；"none" = 旧口径
    reg_p_adjust        = "BH",          # ★ 43 回归多检验校正（y×env 几十次）；"none" = 旧口径
    spearman_p_adjust   = "BH",          # ★ 52 相关矩阵 p 校正（k(k-1)/2 个）；"none" = 旧口径
    anova_type          = "III",         # ★ 12 ANOVA 平方和类型。"III"=car::Anova(type=3)（不平衡设计稳健）
                                         #   "I" = stats::anova（顺序平方和，旧口径，受项序影响）

    # ==== 批 5（2026-09-25 由执行者按最保守默认拍板，可改）====
    impute_max_miss     = 0.5,           # ★ 21 插补：单个性状缺失率上限，超过就剔除不硬插
                                         #   （RF 插补向条件均值收缩 → FRic/RaoQ 被压缩）
    impute_max_nrmse    = 0.3,           # ★ 21 插补：OOB NRMSE 上限，超过醒目警告
    hcpc_nclust         = "auto",        # ★ 50 HCPC 簇数。"auto"=按惯量拐点（nb.clust=-1）
                                         #   设整数（如 4）= 先验指定（旧口径），日志会注明是先验值
    signal_reps         = 999,           # ★ 32 phyloSignal 的置换次数（显式传，不吃包默认）
    runs_label          = "final",       # final | test  —— 结果文件名会带此标记
    trait_input         = "raw",         # raw（03_traits.csv）| pca_axis（性状 PCA 主轴）
    trait_transform     = "none",        # none | log10 | zscore
    fd_impute           = FALSE,         # 是否用 21_impute 结果（缺数据只报告不动手）
    fd_axis_fallback    = TRUE,          # 功能β 凸包要求不满足时，自动改用性状 PCA 主轴（原文做法）
    fd_axis_n           = 5,             # 回退时取几个主轴
    fd_beta_pairwise    = FALSE,         # 是否算功能β 逐样方两两矩阵（multi=TRUE，极慢，原文未用）
    fd_beta_max_sites   = 120,           # 样方数超过此值时功能β 默认跳过（O(n^2) 凸包交叠）
    fd_beta_confirm     = FALSE,         # 设为 TRUE 才在超出阈值时仍强制计算功能β
    fd_beta_method      = "auto",        # auto（超阈值自动换快路线）| betapart | traitspace
    fd_traitspace_bins  = 4,             # 性状空间分格的每轴分位数段数
    fd_traitspace_axes  = 3,             # 用前几个性状 PCA 主轴分格
    na_to_zero          = TRUE,          # 多度矩阵 NA -> 0
    rare_remove_min_occ = 0,             # 出现样方数 < n 的物种剔除阈值（0 = 不剔）
    rarefy              = FALSE,         # α 是否稀释（数据为重要值时 vegan::rarefy 不可用）
    varpart_coding      = "dummy",       # dummy（推荐）| numeric（复现旧的连续编码口径）
    varpart_community_transform = "hellinger",  # 群落矩阵转换：hellinger（推荐）| none
    phylo_correlogram   = FALSE,         # 32 模块的系统发育相关图（耗时）
    phylo_signal_plot_traits = 5,        # 32 出图取前几个性状（避免刷出几十张 pdf）
    lipa_reps           = 999,           # lipaMoran 置换次数（耗时随此增长）        # 32 出图取前几个性状（避免刷出几十张 pdf）
    phylo_sim           = FALSE,         # 32 是否做 phyloSim 模拟（长任务）
    phylo_sim_nsim      = 100,           # phyloSim 参数（原文 nsim=100, reps=99）
    phylo_sim_reps      = 99,
    tree_scenario       = "S3",          # 30 建树情景：S1 | S2 | S3
    tree_group          = "family",      # 30 环形树按哪一列分组着色：family | genus
    tree_group_file     = NA,            # 30 版本②：物种分组表（label, season, habitat）
    tree_group_label_col = "label",      # 分组表里与树 tip 对应的列（论文 sample_group_FQ.N.xlsx 用 "label"）
    tree_group_color_col = "season",     # 分支/标签着色列
    tree_group_shape_col = "habitat",    # 末端点形状/填充列
    # ---- 16 MCMCglmm（贝叶斯路线） ----
    mcmc_nitt           = 13000,         # 采样总步数（首次建议 3000 测时间）
    mcmc_burnin         = 3000,
    mcmc_thin           = 10,
    mcmc_random         = NA,            # ★ MCMCglmm 随机效应公式。NA = "~ <design$random>"
                                         #   ⚠️ MCMCglmm 【不接受 lme4 的 (1|Site) 写法】，会报
                                         #   "invalid substring arguments"。正确写法：
                                         #     随机截距        "~ Site"
                                         #     Site 下随机斜率  "~ us(Habitat):Site"
                                         #     截距 + 斜率     "~ Site + us(Habitat):Site"
    hcpc_nclust         = 4,             # HCPC 簇数
    pheatmap_dist       = "euclidean",
    pheatmap_method     = "complete",

    # ---------- 缓存（见 pitfalls E9） ----------
    FORCE_RECALC        = FALSE,  # TRUE = 无视缓存重算并覆盖
    FIGURE_ONLY         = FALSE   # TRUE = 分析全走缓存，只重画图（改样式后秒级重出）
  ),

  # ---------- 绘图 ----------
  # 图规格对齐论文原图（Ecological indicators 接收版）：
  #   pt 绝对字号（论文 rel(1.2)/rel(1.5) 已换算 base_pt+2 / base_pt+5，见 pitfalls E1）
  #   + 物理尺寸（论文图 mm 见 fig_size）+ 同类图 pd_compose() 合成并标 (a)(b)
  plot = list(
    lang        = "en",        # en | zh（zh 需中文字体）
    size        = "double",    # single(90mm) | double(190mm) | custom
    width_mm    = 190,
    base_pt     = 9,           # 基准字号（pt，绝对字号，不用 rel()）；并排比对偏小则改 10/11
    dpi         = 300,         # 栅格备用
    font_zh     = "SimSun",    # 中文图字体
    font_en     = "Arial",     # 全图统一 Arial（用户第 3 轮拍板）
    tag_pt      = NULL,        # 拼图 (a)(b) 标签字号；NULL = base_pt + 2
    save_singles = FALSE,      # ★ 散图清理规则（用户：「如果拼图已经包括了散图，散图就可以删（冗余）。
                               #     其他情况下不删」）
                               #   FALSE（默认）= 复合图已包含散图 → 散图冗余，复合图落地且非空后删
                               #   TRUE         = 散图与复合图都留，便于逐图检查
                               #   未并入复合图的图、历史输出：一律不删（新图写新文件/新文件夹）
    box_type   = "box",        # ★ 组间比较图型 —— 勾选时问用户（见 SKILL.md 第 3 步）
                               #   "box"      = 箱体 + 散点（箱线图；SCI Fig3/4/5 风格）
                               #   "beeswarm" = 纯蜜蜂图（无箱体）
                               #   "both"     = 两张都出（文件后缀 _box / _swarm）
    points     = "jitter",     # ★ 箱体内的散点层 —— 勾选时问用户
    rda_sp_scale = 2,          # ★ RDA biplot 物种得分放大倍数（毕业论文原文 *2，
                               #   注释写「可适当增减放大倍数」→ 留旋钮）
    rda_sp_label_max = 30,     # ★ 物种名标注阈值：种数 < 此值才标名（毕业论文 47 种标了）；
                               #   skill 示例上百种 → 只画点不标名，避免糊成一团
                               #   物种永远是点、不画箭头（箭头只给环境因子）
    rda_pt_size  = 0.9,        # ★ RDA 点大小（Fig3b-A 的 PT_SIZE_STD）
    rda_pt_alpha = 0.4,        # ★ RDA 点透明度（Fig3b-A 的 PT_ALPHA_STD）
    rda_biplot_show = "sites", # ★ 双标图显示什么 —— **二选一**，勾选时问用户（SKILL.md 第 3 步）
                               #   "sites"   = 只出样方点（默认；样方多时物种点会糊成一团）
                               #   "species" = 只出物种点
                               #   "both"    = 两者都出（仅样方 < 40 且物种 < 30 时才采纳，
                               #               否则自动降级回 "sites" 并打日志）
    # Fig3b-A 的 theme_isme 字号（pt，绝对值，不走 base_pt 偏移）
    s_tick = 8, s_ttl = 9, s_leg = 7.5, s_ann = 7.5,
                               #   "jitter" | "beeswarm" | "none"
    palette_name = "custom",   # custom | npg/aaas/nejm/lancet/jama/...（ggsci）| brewer:Dark2
    palette     = c("#D55F4D", "#2C89A2", "#FFA07A", "#882255", "#70B52B"),

    # ---- 命名色板注册表（pd_pal(name)）----
    # 色值全部来自论文 PDF 提色 / 原始 R 代码，不许发明。
    palettes = list(
      # 箱线图 Fig 3/4/5 —— Revise 色板（✅ PDF 实测：#00AFBB 填充 ×9/9/18，#FC4E07 点 ×177–353）
      box_fill        = "#00AFBB",
      box_border      = "black",
      box_point       = "#FC4E07",
      # 分类色板（非论文图/未来用）
      boxplot_season  = c("#D55F4D", "#2C89A2", "#FFA07A"),
      boxplot_habitat = c("#D55F4D", "#2C89A2", "#FFA07A", "#882255"),
      # NMDS Fig 2
      nmds_season     = c("#FF9C7A", "#E8754A", "#4BA4C9"),
      nmds_habitat    = c("#D55F4D", "#2C89A2", "#FFA07A", "#882255"),
      nmds_habseas    = c("#FF7F50","#FFD700","#FFA500","#32CD32","#6495ED",
                          "#9370DB","#FF1493","#00CED1","#FF4500"),
      # 系统发育树 Fig S1（✅ PDF 实测：season = Set2[1:3]；habitat fill）
      tree_branch     = c("#66C2A5", "#FC8D62", "#8DA0CB"),
      tree_tip        = c("#1F77B4", "#D62728", "#9467BD"),
      # PCA Fig 6 / S3（✅ PDF 实测）
      pca_var         = "#0E5484",
      pca_ind         = "#6CBF59",
      pca_var_sig     = "#FF0000",    # Fig 6 有信号（实测纯红，caption 称 orange-red）
      pca_var_nosig   = "#000000",
      # 地图 Fig 1
      map_point       = "#E9111A",
      map_dem         = c("#33A02C","#B2DF8A","#FDBF6F","#1F78B4","#999999","#E6E6E6","#A6CEE3"),
      # 热图 S3/S4（skill 已与论文一致）
      heatmap         = c("#3A558C", "#ffffff", "#75D155"),
      # Diversity 2023（MDPI）图型专用 —— 美化抄该文 Fig 6/8（RDA 已改抄硕士论文）
      reg_point       = "#4BA4C9",                            # Fig 8 散点/拟合线：青蓝单色
      corr_div        = c("#2166AC", "#ffffff", "#B2182B"),   # Fig 6 相关矩阵：蓝↔白↔红发散
      rda_hull        = "grey70",                             # 旧 RDA 凸包（已不用，保留兼容）
      # 硕士论文 RDA 图 7-1 专用（✅ 毕业论文R代码.docx 原文色值）
      rda_sp_point    = "#F37A70",                            # 物种点：小方块 shape=15
      rda_env_arrow   = "#3182BD",                            # ★ 环境箭头蓝（Fig3b-A 原色）
      rda_site_shape  = 1:18,                                 # （旧口径留兼容）
      # Fig3b_dbRDA_rf_gam 面板 A 样方点色板（✅ 00c cols_veg 原色，柔和低饱和）
      rda_site        = c("#60859E", "#B98079", "#959BB0", "#989898"),
      # 非论文图，轻统一
      venn            = c("hotpink", "skyblue"),
      qq              = c("#D55F4D", "#C00000")
    ),
    heatmap_col = c("#3A558C", "#ffffff", "#75D155"),  # 同 palettes$heatmap（保留兼容）

    # ---- 论文图物理尺寸注册表 mm（宽, 高）—— 来自论文 PDF MediaBox ----
    # 注意（pitfalls E5）：论文 PDF 页宽含 PPTX 边距（TIFF 内容 2126px ≈ 180mm）。
    # 若照抄 263mm 导致内容过满，把 fig3/fig4 改成内容框尺寸 ≈180×125。
    fig_size = list(
      fig1_map        = c(186, 274),
      fig2_nmds       = c(180, 190),
      fig3_shannon    = c(263, 125),
      fig4_fric       = c(264, 125),
      fig5_pd_mntd    = c(173, 162),
      fig6_pca        = c(180, 170),
      s1_tree         = c(140, 133),
      s1_tree_group   = c(140, 140),
      s2_phylosignal  = c(190, 157),
      s3_pca_heatmap  = c(180, 150),
      s4_trait_sp     = c(180,  80),
      rda_biplot      = c(180, 130),   # Fig7 RDA（MDPI 原文 topptx 6×6 in，这里单栏宽）
      regression_scatter = c(180, 175), # Fig8 回归 2×2
      spearman_corr   = c(150, 140),   # Fig6 相关矩阵
      box_panel       = c(320, 230),   # Fig3+4+5 合一（4 面板 2×2）
      heatmaps        = c(180, 330),   # Fig S3+S4 合一（2 面板）—— 150mm 会把 pheatmap gtable 挤压、字号显得过大
      interaction_panel = c(190, 360), # 交互图 ×10（2 列 5 行）
      data_diagnostics  = c(190, 220), # QQ + impute
      stats_tests_panel = c(190, 400), # ANOSIM + Venn + MCMC（多页）
      default_single  = c( 90, 120),
      default_double  = c(190, 120)
    ),

    # ---- 论文图 ↔ 变量/布局映射（60_plots / 40_ordination 读）----
    # layout: combo = 单面板 Season×Habitat 组合横轴；stack = 多面板上下拼
    # 布局已用 PDF 提色定案：Fig3/4 = 单 combo（各 9 箱体）；Fig5 = 2 combo 上下（18 箱体）
    paper_figs = list(
      fig3 = list(vars = "Shannon",           layout = "combo", size = "fig3_shannon", tags = NULL, font = "sans"),
      fig4 = list(vars = "FRic",              layout = "combo", size = "fig4_fric",    tags = NULL, font = "sans"),
      fig5 = list(vars = c("PD", "SES.MNTD"), layout = "stack", size = "fig5_pd_mntd", tags = "a",   font = "sans"),
      fig2 = list(size = "fig2_nmds", tags = "a", layout = "stack")
    )
  ),

  # ---------- 论文表格（70_paper_tables：只做论文那 5 个表，不做全分析表格） ----------
  # 范围铁律：T1/T2/T3（正文）+ S1/S2（附录），结构逐列照抄论文；
  #   新分析只换因子名/响应变量，不新增表类型。见 references/04-paper-tables.md
  table = list(
    dir      = "tables",
    file     = "tables.docx",
    # ★★ 出哪几张三线表 —— 【写新论文时必须先和用户沟通，不代选、不默认全出】
    #    （用户 2026-09-25：「出什么三线表也要提前和我沟通，不用所有的全出」）
    #    NULL = 未勾选 → 兜底全出 12 张并打提示；填了就只出填的那几张
    #    可选键：t1 t2 t3 s1 s2 t4 t5 t6 t7 t8 s3 s4
    #    例：which = c("t1","t3","t7")  → 只出 Table 1/2/3
    which    = NULL,
    font     = "Times New Roman",   # 论文表字体（图是 Arial，两条线不混）
    size_pt  = 8,                   # 论文实测 w:sz=16 半磅 = 8pt
    # 显著性星号阈值沿用 pd_sig()：*** <0.001, ** <0.01, * <0.05, 否则无后缀
    p_fmt    = "lt001",             # "<0.001 ***"；备选 "paper"（0***）仅供对照
    digits   = list(num = 3, f = 2, mean_sd = 2, p = 3),
    # T3 / S2 / t5 的响应变量列（论文为 Shannon/FRic/PD/SES.MNTD）——新分析可换
    vars     = c("Shannon", "FRic", "PD", "SES.MNTD"),
    # 因子名：默认与 design 一个来源（pd_design_factors 解析），这里不再单独写一份
    #   要覆盖时才填，如 factors = c("Habitat","Season")；否则留 NULL
    factors  = NULL,
    # t4 优势种重要值：分组列（列名由它的各水平决定）
    t4_group = "Season",
    iv_threshold = 1,          # 入选阈值：全数据平均 IV（%）大于它才进表
    # t6 环境因子单位（config$opts$env 的列名 → 单位）；没有就留 "-"，不发明
    env_units = list(pH = "-", AK = "mg/kg", AP = "mg/kg",
                     AN = "mg/kg", SOM = "g/kg", SMC = "%"),
    # community 响应的单位（response$community 的列名 → 单位）；缺则 "-"，不发明
    community_units = list(Height = "cm", Coverage = "%", Density = "株·m⁻²"),
    # ★ t8「时间 × 分组」mean±SD 表要纵向堆叠哪几个指标（2026-09-25，对应论文 S3–S6 版式）
    #   行 = design$time 的水平（Season），列 = factors[1] 的水平（Habitat）
    #   指标名只写首行，同 pd_table_s2 的 merge_v 思路
    #   论文 S3 是 c("Height","Coverage","Density")；S6 是 c("NTI","NRI")
    t8_vars = c("Height", "Coverage", "Density"),
    # s3「并排双栏基线描述表」的指标集；NULL = vars + opts$env + response$community 自动合
    s3_vars = NULL,
    # T1 的分层顺序：先在 factors[1] 每水平内比 factors[2]，再反过来
    # S1 性状显示名（short_name → 论文列名）；不填则从 trait_name_map 去括号
    trait_labels = c(
      Seed_dry_mass                              = "Seed dry mass",
      Seed_length                                = "Seed length",
      Leaf_thickness                             = "Leaf thickness",
      Leaf_density                               = "Leaf density",
      Leaf_nitrogen_2                            = "Leaf N",
      Photosynthesis_rate_per_leaf_area          = "Photosynthesis rate",
      Leaf_dry_mass                              = "Leaf dry mass",
      Seed_germination_rate                      = "Seed germination rate",
      Leaf_carbon_nitrogen                       = "Leaf C/N",
      Leaf_fresh_mass                            = "Leaf fresh mass",
      Species_genotype_chromosome_number         = "Species genotype",
      Species_environmental_indicator_value_according_to_Ellenberg_light      = "Light Ellenberg",
      Species_environmental_indicator_value_according_to_Ellenberg_moisture   = "Moisture Ellenberg",
      Species_environmental_indicator_value_according_to_Ellenberg_nitrogen   = "Nitrogen Ellenberg",
      Species_environmental_indicator_value_according_to_Ellenberg_pH         = "pH Ellenberg",
      Plant_height_vegetative                    = "Plant height",
      Leaf_area_1                                = "Leaf area",
      Leaf_area_per_leaf_dry_mass_1              = "Specific leaf area",
      Leaf_area_per_leaf_dry_mass_2              = "Leaf area homogenization",
      Leaf_potassium                             = "Leaf K",
      Leaf_length                                = "Leaf length",
      Leaf_width                                 = "Leaf width",
      Root_rooting_depth                         = "Root rooting depth",
      Leaf_nitrogen_phosphorus                   = "Leaf N/P",
      Plant_lifespan                             = "Plant lifespan",
      Leaf_carbon_2                              = "Leaf C",
      Leaf_water_content_per_leaf_dry_mass       = "Leaf water",
      Leaf_texture                               = "Leaf texture",
      Leaf_phosphorus_2                          = "Leaf P"
    ),
    # S1 单位：优先取 trait_name_map 的 TRY 长名括号；此处可覆盖。
    # 注意 Leaf_width：TRY 原单位 cm（均值 2.175），论文写 21.75 mm（×10 换算）。
    # 用户已定：照数据 2.175 cm，不做换算。要跟论文一致就在此覆盖为 mm 并自行换算。
    trait_units  = list(
      Leaf_width = "cm",            # 照数据
      Species_genotype_chromosome_number = "number",
      `Species_environmental_indicator_value_according_to_Ellenberg_light`    = "-",
      `Species_environmental_indicator_value_according_to_Ellenberg_moisture` = "-",
      `Species_environmental_indicator_value_according_to_Ellenberg_nitrogen` = "-",
      `Species_environmental_indicator_value_according_to_Ellenberg_pH`       = "-",
      Leaf_carbon_nitrogen = "-", Leaf_nitrogen_phosphorus = "-"
    ),
    # 题注逐字抄论文（Manuscript.docx / Appendix A；t4/t5/t6 来自 Diversity 2023, 15, 9922）
    captions = list(
      t1 = "ANOSIM and PERMANOVA pairwise comparisons results. The ANOSIM R value indicates inter-group differences, while the PERMANOVA F value represents the inter-group-to-intra-group differences ratio. The R2 value signifies the proportion of inter-group differences to total differences. The p-values for each pair indicate significance.",
      t2 = "Explained variance proportion (R2), analysis of variance F-values, and p-values from PERMANOVA analysis for the effects of seasons, habitats, their interaction, and residuals on plant community dissimilarity.",
      t3 = "Analysis of variance F-values, and p-values from Two-Way ANOVA for the effects of seasons, habitats, and their interaction on plant diversity indices.",
      t4 = "Seasonal variation in dominant plant species importance values. Species listed in this table are dominant plant species with average importance values greater than 1%, classified using the Angiosperm Phylogeny Group IV (APG IV) classification system.",
      t5 = "The significance of the Spearman correlation analysis of each diversity index. Significance results are indicated by asterisks: \"*\", p < 0.05; \"**\", p < 0.01; \"***\", p < 0.001.",
      t6 = "Values of soil environmental factors and their explanatory power for changes in plant communities. Monte Carlo permutation test analysis was conducted to determine the significance of soil environmental factors on plant community changes. M ± SD represents the mean ± standard deviation of soil environmental factors. R2 represents the proportion of variation in plant community changes explained by the soil environmental factors.",
      s1 = "Plant functional traits and their phylogenetic signals. Light Ellenberg, Moisture Ellenberg, Nitrogen Ellenberg, and pH Ellenberg represent the Ellenberg plant ecological indices, indicating plant adaptability and preference towards light, moisture, nitrogen content, and soil pH values. K and λ represent Blomberg's K and Pagel's λ values, respectively. p.K and p.λ indicate the significance of differences based on Blomberg's K test and Pagel's λ test, respectively.",
      s2 = "Plant species, functional, and phylogenetic diversity indices (mean ± standard deviation) by seasons and habitats.",
      t7 = "Quantitative analysis of the effects of soil environmental factors on plant community composition (Monte-Carlo permutation test). Axis 1 and Axis 2 are the direction cosines of each environmental factor on the first and second constrained ordination axes (RDA or CCA, selected by DCA gradient length; unit length, Axis1^2 + Axis2^2 = 1). R2 is the squared Pearson correlation between the environmental factor and the site scores of the first two ordination axes (envfit r2, choices = c(1,2)) — NOT the proportion of community variation explained. Note that the environmental variables shown are the same ones constraining the ordination axes, so r2 and p are descriptive rather than an independent significance test. p is the permutation significance level.",
      t8 = "Mean ± standard deviation of vegetation structural variables across seasons and habitats. Rows are time levels defined by design$time; columns are the levels of the primary design factor.",
      s3 = "Baseline values of vegetation and soil variables (mean ± standard deviation across all plots).",
      s4 = "Inventory of plant species in the study area. Species and their taxonomic information are classified according to the Angiosperm Phylogeny Group IV (APG IV) classification system."
    ),
    footnotes = list(
      t1 = "", t2 = "",
      t3 = "\"*\", \"**\", and \"***\" represent p-values of <0.05, <0.01, and <0.001, respectively.",
      t4 = "",
      t5 = "\"*\", \"**\", and \"***\" represent p-values of <0.05, <0.01, and <0.001, respectively.",
      t6 = "\"*\", \"**\", and \"***\" represent p-values of <0.05, <0.01, and <0.001, respectively.",
      s1 = "\"*\", \"**\", and \"***\" represent p-values of <0.05, <0.01, and <0.001, respectively.",
      s2 = "",
      t7 = "\"*\", \"**\", and \"***\" represent p-values of <0.05, <0.01, and <0.001, respectively.",
      t8 = "", s3 = "", s4 = ""
    )
  ),

  # ---------- 地图（90_map：底图 + 采样点 + 嵌图 + 引线；不做 DEM / 河流） ----------
  map = list(
    boundary      = NA,   # 主图边界：GeoJSON/shapefile 路径，如 "data/boundary/henan.json"
    boundary_name = "Fengqiu County",
    inset         = NA,   # 嵌图边界（研究区放大图），如 "data/boundary/fengqiu.json"
    sites_csv     = NA,   # 采样点坐标表，需含经纬度两列
    lon_col       = "lon",
    lat_col       = "lat",
    county_lon    = NA,   # 研究区中心经度（在主图上标星号）
    county_lat    = NA,
    xlim          = NULL, ylim = NULL,
    scale_loc     = "br", north_loc = "tl",
    # 嵌图与引线在 [0,1] npc 坐标里的位置（按你的版式调）
    inset_x = 0.60, inset_y = 0.36, inset_w = 0.38, inset_h = 0.38,
    line1_x = 0.32, line1_y = 0.72, line1_xe = 0.62, line1_ye = 0.44,
    line2_x = 0.30, line2_y = 0.66, line2_xe = 0.56, line2_ye = 0.16
  )
)
