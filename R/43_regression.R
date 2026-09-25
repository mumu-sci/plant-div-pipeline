# ============================================================
# 43_regression.R · 环境因子 × 多样性指数 线性回归
#   对应 Diversity 2023 Fig 8（散点 + lm 拟合线 + 面板内 R²=0.185*）+ 回归表
#   输入：meta 的响应变量（config$table$vars）
#         + 环境表 files$env 的解释变量（config$opts$env）
#   输出：results/43_regression.xlsx（coefficients / run_info）
#         figures/43_regression_scatter.pdf（默认取 R² 最大的 4 对作 2×2）
# 依赖：stats（lm）；ggplot2 / patchwork（拼图）
# 口径：普通最小二乘 lm(y ~ env)；R² = summary(lm)$r.squared；p = 斜率 t 检验 p
# ============================================================

# 43.1 逐对回归 → 长表
pd_lm_pairs <- function(df, ys, envs) {
  rows <- list()
  for (y in ys) for (e in envs) {
    if (!all(c(y, e) %in% names(df))) next
    d <- data.frame(y = df[[y]], e = df[[e]])
    d <- d[stats::complete.cases(d), , drop = FALSE]
    if (nrow(d) < 8) next          # ★ 样本下限（2026-09-25）：旧 <4 过松，lm 自由度不够
    fit <- tryCatch(stats::lm(y ~ e, data = d), error = function(err) NULL)
    if (is.null(fit)) next
    s <- summary(fit)
    cs <- s$coefficients
    # ★ 残差诊断（2026-09-25）：正态 + 异方差。不满足时在表里标出，避免无条件打星
    rs <- tryCatch(stats::residuals(fit), error = function(e) NULL)
    shapiro_p <- if (!is.null(rs) && length(rs) >= 3 && length(rs) <= 5000)
      tryCatch(stats::shapiro.test(rs)$p.value, error = function(e) NA_real_) else NA_real_
    bp_p <- if (pd_has("lmtest"))
      tryCatch(lmtest::bptest(fit)$p.value, error = function(e) NA_real_) else NA_real_
    resid_ok <- (is.na(shapiro_p) || shapiro_p >= (cfg$opts$alpha %||% 0.05)) &&
                (is.na(bp_p)      || bp_p      >= (cfg$opts$alpha %||% 0.05))
    rows[[length(rows) + 1]] <- data.frame(
      y = y, env = e, n = nrow(d),
      intercept = unname(cs[1, 1]),
      slope     = unname(cs[2, 1]),
      slope_se  = unname(cs[2, 2]),
      t         = unname(cs[2, 3]),
      p         = unname(cs[2, 4]),
      R2        = s$r.squared,
      adj_R2    = s$adj.r.squared,
      resid_shapiro_p = shapiro_p,          # 残差正态
      resid_bp_p      = bp_p,               # 异方差（Breusch-Pagan）
      resid_ok        = resid_ok,
      stringsAsFactors = FALSE)
  }
  if (!length(rows)) return(data.frame())
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  # ★★ 多重比较校正（2026-09-25，pitfalls I18）
  #   y×env 逐对 lm 有几十次检验，旧写法原始 p 直接打星，再按 R2 挑 top-4 画图带星
  #   = 胜者诅咒，图上面板星号系统性过乐观。
  #   opts$reg_p_adjust = "BH"（默认）|"none"（旧口径）
  adj <- cfg$opts$reg_p_adjust %||% "BH"
  out$p_adj <- out$p
  if (!identical(adj, "none")) {
    out$p_adj <- p.adjust(out$p, method = adj)
    pd_msg(sprintf("[43] %d 个回归做 %s 校正；星号按校正后 p", nrow(out), adj))
  }
  out$sig <- pd_sig(out$p_adj)
  out$sig_raw <- pd_sig(out$p)      # 未校正星号留档，便于对照
  out[order(-out$R2), , drop = FALSE]
}

# 43.2 散点 + 拟合线 + 面板内 R²=…*
#   ★ 美化对齐 Diversity 2023（MDPI）Fig 8：
#     青/蓝绿单色点 + 粗拟合线（linewidth 大）+ 面板内 "R²=0.185*" 纯文本
#     theme 走 pd_theme_mdpi（白底黑边、无网格、黑轴线、Arial）—— 同 RDA 图
pd_plot_lm_scatter <- function(df, y, e, r2, p, cfg = .pd$cfg) {
  d <- data.frame(y = df[[y]], e = df[[e]])
  d <- d[stats::complete.cases(d), , drop = FALSE]
  # 原文 Fig 8 是单一青/蓝绿色（点与拟合线同色）；默认取 nmds_season 的青蓝 #4BA4C9
  pt_col <- pd_pal("reg_point", cfg = cfg)[1]
  sg   <- pd_sig(p)                                  # "***" / "**" / "*" / "ns"
  star <- if (identical(sg, "ns") || identical(sg, "NA")) "" else sg
  ggplot2::ggplot(d, ggplot2::aes(x = .data$e, y = .data$y)) +
    ggplot2::geom_point(size = 2.0, alpha = 0.85, colour = pt_col) +
    ggplot2::geom_smooth(method = "lm", se = FALSE, linewidth = 1.4, colour = pt_col) +  # ★ 粗线
    ggplot2::annotate("text", x = -Inf, y = Inf, hjust = -0.1, vjust = 1.5,
                      label = paste0("R²=", formatC(r2, format = "f", digits = 3), star),
                      size = (cfg$plot$base_pt %||% 9) * 0.75, parse = FALSE) +  # ★ 面板内文本
    pd_theme_mdpi(cfg = cfg) +
    ggplot2::labs(x = e, y = y)
}

# 43.3 主入口
pd_run_regression <- function(cfg = .pd$cfg, dat = NULL, save = TRUE, n_panel = 4) {
  if (!pd_require("ggplot2", "43_regression")) return(invisible(NULL))
  pd_msg("")
  pd_msg("### 43 线性回归（环境 × 多样性）###")
  dat <- dat %||% pd_load_data(cfg)

  envs <- cfg$opts$env %||% character(0)
  env_df <- pd_read_table(cfg$files$env)
  if (is.null(env_df) || !nrow(env_df)) {
    pd_warn("43 跳过：缺环境表 files$env（", cfg$files$env %||% "NA", "）")
    return(invisible(NULL))
  }
  # 与 meta 按 sample_id 对齐
  id <- cfg$key$sample_id %||% "sample_id"
  if (!(id %in% names(env_df))) { pd_warn("43 跳过：环境表缺列 ", id); return(invisible(NULL)) }
  mt <- dat$meta
  if (!(id %in% names(mt))) { pd_warn("43 跳过：meta 缺列 ", id); return(invisible(NULL)) }
  m <- merge(mt, env_df, by = id, suffixes = c("", ".env"))
  envs <- envs[envs %in% names(m)]
  if (!length(envs)) { pd_warn("43 跳过：opts$env 列都不在环境表里"); return(invisible(NULL)) }

  ys <- unique(c(cfg$table$vars %||% character(0),
                 unlist(cfg$response[c("alpha", "func", "phylo", "community")])))
  ys <- ys[ys %in% names(m)]
  if (!length(ys)) { pd_warn("43 跳过：meta 里没有可用响应变量"); return(invisible(NULL)) }
  pd_msg("[43] 响应（", length(ys), "）：", paste(ys, collapse = ", "))
  pd_msg("[43] 解释（", length(envs), "）：", paste(envs, collapse = ", "))

  tab <- pd_cached("43_lm_pairs", NULL, pd_lm_pairs(m, ys, envs), cfg = cfg)
  if (!nrow(tab)) { pd_warn("43 跳过：回归全失败"); return(invisible(NULL)) }

  if (save) {
    pd_write_table(list(
      coefficients = tab,
      run_info     = data.frame(
        item  = c("方法", "公式", "★ 口径声明", "多重校正", "星号依据",
                  "残差诊断", "画图选样", "响应变量", "解释变量", "n"),
        value = c("stats::lm 最小二乘（逐对简单回归）",
                  "y ~ env（每个环境变量单独拟合）",
                  # ★★ F43 口径声明（2026-09-25）
                  "逐对【简单回归】，非多元回归：pH/AK/AP/AN/SOM/SMC 等共线时 R² 混淆共享方差，不能解释为单因子独立解释力",
                  cfg$opts$reg_p_adjust %||% "BH",
                  "按【校正后 p_adj】打星（sig_raw 列保留未校正星号供对照）",
                  "Shapiro（残差正态）+ Breusch-Pagan（异方差）→ resid_ok 列",
                  paste0("按 -R2 取 top-", n_panel, " 画图 ⚠️ 胜者诅咒：图上 R² 系统性偏乐观，",
                         "正文应报全表而非只报这 ", n_panel, " 张"),
                  paste(ys, collapse = ", "), paste(envs, collapse = ", "),
                  paste(unique(tab$n), collapse = ", ")),
        stringsAsFactors = FALSE)
    ), stem = "regression", module = "43")
  }

  # 图：取 R² 最大的 n_panel 对做多面板（论文 Fig 8 是 2×2）
  pls <- list()
  k <- min(n_panel, nrow(tab))
  for (i in seq_len(k)) {
    r <- tab[i, ]
    pls[[paste(r$y, r$env, sep = " ~ ")]] <-
      pd_plot_lm_scatter(m, r$y, r$env, r$R2, r$p, cfg = cfg)
  }
  fig <- NULL
  if (length(pls)) {
    nc <- if (length(pls) <= 2) length(pls) else 2
    if (pd_has("patchwork") && length(pls) > 1) {
      pk <- pd_compose(pls, ncol = nc, tags = "a")
      fig <- pd_save_pdf(pk, "regression_scatter", "43",
                         size = "default_double", width_mm = 180,
                         height_mm = ceiling(length(pls) / nc) * 85 + 20)
    } else {
      fig <- pd_save_pdf(pls[[1]], "regression_scatter", "43",
                         width_mm = 100, height_mm = 85)
    }
  }

  invisible(list(table = tab, figure = fig))
}
