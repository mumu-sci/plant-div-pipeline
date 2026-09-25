# ============================================================
# 52_spearman.R · 多样性指数间 Spearman 相关（r + p 矩阵）
#   对应 Diversity 2023 Fig 6（corrplot mixed：下三角数字 r，上三角圆）+ Table 3（p 矩阵）
#   输入：meta 的响应变量列（config$table$vars，缺则回落 config$response 各组）
#   输出：results/52_spearman.xlsx（r_matrix / p_matrix / run_info）
#         figures/52_spearman_corrplot.pdf
# 依赖：corrplot（缺则只出表不出图）；stats（cor.test）
# ============================================================

# 52.1 Spearman r/p 矩阵（对角 NA；与论文口径一致）
pd_spearman_mat <- function(df, vars, cfg = .pd$cfg) {
  v <- vars[vars %in% names(df)]
  if (length(v) < 2) return(list(r = NULL, p = NULL, vars = v))
  m <- as.matrix(df[, v, drop = FALSE])
  k <- length(v)
  R <- matrix(NA_real_, k, k, dimnames = list(v, v))
  P <- matrix(NA_real_, k, k, dimnames = list(v, v))
  for (i in seq_len(k - 1)) for (j in (i + 1):k) {
    ct <- suppressWarnings(stats::cor.test(m[, i], m[, j], method = "spearman",
                                           exact = FALSE))
    R[i, j] <- R[j, i] <- unname(ct$estimate)
    P[i, j] <- P[j, i] <- ct$p.value
  }
  # ★★ 多重比较校正（2026-09-25，pitfalls I17）
  #   k 个变量 = k(k-1)/2 个检验，旧写法原始 p 直接进 t5 星表 → 胜者诅咒。
  #   opts$spearman_p_adjust = "BH"（默认）|"bonferroni"|"holm"|"none"（旧口径）。
  adj <- cfg$opts$spearman_p_adjust %||% "BH"
  if (!identical(adj, "none")) {
    iu <- upper.tri(P)
    P[iu] <- p.adjust(P[iu], method = adj)
    P[lower.tri(P)] <- t(P)[lower.tri(P)]
    diag(P) <- NA_real_
    pd_msg(sprintf("[52] p 矩阵做 %s 校正（%d 个检验）", adj, sum(iu)))
  }
  list(r = R, p = P, vars = v)
}

# 52.2 主入口
pd_run_spearman <- function(cfg = .pd$cfg, dat = NULL, save = TRUE) {
  if (!pd_require("corrplot", "52_spearman") && !pd_has("stats")) return(invisible(NULL))
  pd_msg("")
  pd_msg("### 52 Spearman 相关 ###")
  dat <- dat %||% pd_load_data(cfg)
  mt <- dat$meta

  vars <- (cfg$table$vars %||% character(0))
  vars <- c(vars, unlist(cfg$response[c("alpha", "func", "phylo", "community")]))
  vars <- unique(vars[vars %in% names(mt)])
  if (length(vars) < 2) { pd_warn("52 跳过：meta 里可用响应变量 < 2（", paste(vars, collapse = ", "), "）"); return(invisible(NULL)) }
  pd_msg("[52] 变量（", length(vars), "）：", paste(vars, collapse = ", "))

  sm <- pd_spearman_mat(mt, vars, cfg = cfg)
  if (is.null(sm$r)) { pd_warn("52 跳过：相关矩阵算不出来"); return(invisible(NULL)) }

  out <- list(r = sm$r, p = sm$p)
  if (save) {
    pd_write_table(list(
      r_matrix   = as.data.frame(sm$r),
      p_matrix   = as.data.frame(sm$p),
      run_info   = data.frame(item = c("方法", "变量", "n", "备注"),
                              value = c("Spearman", paste(sm$vars, collapse = ", "),
                                        sum(stats::complete.cases(mt[, sm$vars])),
                                        "对角线留空；p 矩阵供 tables.docx 的 t5"),
                              stringsAsFactors = FALSE)
    ), stem = "spearman", module = "52")
  }

  # 图：corrplot 混合布局（下三角数字 r，上三角圆，蓝↔红发散）
  #   ★ 美化对齐 Diversity 2023（MDPI）Fig 6：
  #     · 上三角 = 大小/明暗随 |r| 的圆，下三角 = 数字相关系数（不是 p）
  #     · 色标是 **蓝↔红 发散**（−1…1），不是蓝↔绿
  #   ★ 两个坑（见 pitfalls H3）：
  #     ① method 无 "mixed" —— 混合布局走 corrplot.mixed(lower=, upper=)
  #     ② diag 是字符 "n"/"l"/"u"，不是 TRUE/FALSE（传 FALSE → 'arg' must be NULL or a character vector）
  fig <- NULL
  if (pd_has("corrplot")) {
    pal <- pd_pal("corr_div", cfg = cfg)                 # 默认蓝 ↔ 白 ↔ 红
    cols <- colorRampPalette(pal)(200)
    fam  <- cfg$plot$font_en %||% "Arial"
    fig <- pd_capture_plot({
      old <- graphics::par(family = fam)                 # ★ Arial（corrplot 是 base 图形）
      on.exit(graphics::par(old), add = TRUE)
      corrplot::corrplot.mixed(sm$r, lower = "number", upper = "circle",
                               lower.col = "black", upper.col = cols,
                               order = "original", tl.col = "black",
                               tl.cex = 1.0, number.cex = 0.9, cl.cex = 0.9,
                               diag = "n", mar = c(0, 0, 1, 0))
    }, "spearman_corrplot", "52", width_mm = 160, height_mm = 150)
  }

  invisible(c(out, list(r_matrix = sm$r, p_matrix = sm$p, figure = fig)))
}

# 供 70_paper_tables 的 t5 用：p 矩阵（含变量名）
pd_spearman_p_table <- function(pmat) {
  if (is.null(pmat)) return(NULL)
  d <- as.data.frame(pmat)
  d <- cbind(var = rownames(d), d, stringsAsFactors = FALSE)
  rownames(d) <- NULL
  d
}
