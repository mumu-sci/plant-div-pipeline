# ============================================================
# _TEMPLATE_run_all.R · 调用脚本模板
# 用法：复制到 <论文项目>/run/run_all.R，只改 PROJECT_DIR 与开关。
# 纪律：不把函数体复制进来；只 source 模块 + 一行调用。
# ============================================================

# ---- 0. 路径 ----
PROJECT_DIR <- "D:/path/to/your/paper-project"
PKG_DIR     <- "D:/01-Academic/00-学术文件/analysis-packages/plant-div-pipeline"

# ---- 1. 环境（中文 locale，见 references/03-pitfalls.md A1） ----
if (.Platform$OS.type == "windows")
  suppressWarnings(Sys.setlocale("LC_CTYPE", "Chinese_China.utf8"))
options(encoding = "UTF-8")

# ---- 2. 加载包内函数库 ----
for (f in list.files(file.path(PKG_DIR, "R"), pattern = "\\.R$", full.names = TRUE))
  source(f, encoding = "UTF-8")

# ---- 3. 读配置 ----
source(file.path(PROJECT_DIR, "config", "config.R"), encoding = "UTF-8")
setwd(PROJECT_DIR)
pd_setup(CONFIG)

# ---- 4. 按需开启的模块（TRUE / FALSE） ----
RUN <- list(
  health   = TRUE,    # 01 数据体检（必跑）
  alpha    = TRUE,    # 10 α 多样性
  beta     = FALSE,   # 11 β 多样性
  tests    = TRUE,    # 12 组间比较
  mixed    = FALSE,   # 14 混合效应模型
  temporal = FALSE,   # 15 时间自相关
  fd       = FALSE,   # 20 功能多样性
  impute   = FALSE,   # 21 性状插补
  phylo_b  = FALSE,   # 30 建树
  pd_nti   = FALSE,   # 31 PD/NTI/NRI
  signal   = FALSE,   # 32 系统发育信号
  ord      = FALSE,   # 40 NMDS/PERMANOVA/ANOSIM
  varpart  = FALSE,   # 41 方差分解
  pca      = FALSE,   # 50 PCA/HCPC
  heatmap  = FALSE,   # 51 热图
  plots    = TRUE,    # 60 箱线图
  rda      = TRUE,    # 42 DCA + RDA/CCA + envfit
  reg      = TRUE,    # 43 线性回归散点
  spearman = TRUE,    # 52 Spearman 相关矩阵
  map      = FALSE,   # 90 研究区底图
  tables   = TRUE     # 70 论文表格 tables.docx
)

# ---- 5. 读数据（一次读入，各模块共用） ----
dat <- pd_load_data(CONFIG)

# ---- 6. 依次执行 ----
health <- if (RUN$health) pd_run_data_health(CONFIG, dat) else NULL
if (RUN$alpha)    alpha_res  <- pd_run_alpha(CONFIG, dat)
if (RUN$beta)     beta_res   <- pd_run_beta(CONFIG, dat)
# ★ vars 必须覆盖 config$table$vars（Shannon/FRic/PD/SES.MNTD）—— 默认只测 alpha 组，
#   否则 70 的 T3/S2 里 func/phylo 列会全 "-"（60 也会自动补跑）
test_vars <- unique(c(unlist(CONFIG$response[c("alpha", "func", "phylo")]),
                      CONFIG$table$vars %||% character(0)))
tests <- if (RUN$tests) pd_run_tests(CONFIG, dat, method = CONFIG$opts$alpha_test,
                                     vars = test_vars, health = health) else NULL
if (RUN$mixed)    mixed_res  <- pd_run_mixed(CONFIG, dat)
if (RUN$temporal) temp_res   <- pd_run_temporal(CONFIG, dat)
if (RUN$fd)       fd_res     <- pd_run_fd(CONFIG, dat)
if (RUN$impute)   imp_res    <- pd_run_impute(CONFIG, dat)
ph <- if (RUN$phylo_b) pd_run_phylo_build(CONFIG, dat) else NULL
if (RUN$pd_nti)   pnti_res   <- pd_run_pd_nti_nri(CONFIG, dat, tree = ph$tree %||% NULL)
if (RUN$signal)   sig_res    <- pd_run_phylo_signal(CONFIG, dat, tree = ph$tree %||% NULL)
if (RUN$ord)      ord_res    <- pd_run_nmds(CONFIG, dat)
if (RUN$varpart)  vp_res     <- pd_run_varpart(CONFIG, dat)
if (RUN$pca)      pca_res    <- pd_run_pca_hcpc(CONFIG, dat)
if (RUN$heatmap)  hm_res     <- pd_run_heatmap(CONFIG, dat)
if (RUN$plots)    plot_res   <- pd_run_plots(CONFIG, dat, tests = tests)
if (RUN$rda)      rda_res    <- pd_run_rda(CONFIG, dat)
if (RUN$reg)      reg_res    <- pd_run_regression(CONFIG, dat)
if (RUN$spearman) sp_res     <- pd_run_spearman(CONFIG, dat)
if (RUN$map)      map_res    <- pd_run_map(CONFIG)
# 论文表格最后出：它只读 results/*.xlsx（与缓存解耦）
if (RUN$tables)   tab_res    <- pd_run_paper_tables(CONFIG, dat = dat)

pd_msg("")
pd_msg("全部完成。结果表 -> results/，图 -> figures/，论文表格 -> tables/tables.docx，日志 -> logs/")
