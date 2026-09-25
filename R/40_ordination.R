# ============================================================
# 40_ordination.R · 群落排序与差异检验（完整版）
#   ① NMDS：单图组合椭圆 / 按因子分面 / 两者都出（+ 拼图）
#   ② PERMANOVA（adonis2，加性 / 交互）+ 内置两两 PERMANOVA
#   ③ ANOSIM（交叉验证）+ 秩分布箱线图 + 内置两两 ANOSIM
# 依赖：vegan ；ggplot2 / patchwork（绘图，可选）
# ============================================================

# ------------------------------------------------------------
# 40.1 内置两两 PERMANOVA（替代 pairwiseAdonis，避免额外依赖）
#   ★★ strata（= subset_by）【只是把数据按该变量切成子集、在每个水平内做两两比较】，
#     【不是】vegan/permute 意义上的「受限置换」！名字有误导（2026-09-25 pitfalls I10）。
#     要受限置换请用 opts$restrict_perm（见 pd_perm_ctrl）。
#     与 40.2 的分层 ANOSIM 同口径，供 70 的 T1 出「生境内比季节 / 季节内比生境」
#     不传 = 原行为（全数据两两）
# ------------------------------------------------------------
pd_pairwise_permanova <- function(comm, grouping, distance = "bray",
                                  permutations = 999, p.adjust.method = "BH",
                                  seed = 20260101, strata = NULL, subset_by = NULL) {
  strata <- strata %||% subset_by      # subset_by 是更准确的别名（2026-09-25）
  if (!pd_has("vegan")) return(data.frame())

  one_level <- function(sub_comm, sub_g) {
    g <- droplevels(factor(sub_g))
    lv <- levels(g)
    if (length(lv) < 2) return(data.frame())
    cmb <- utils::combn(lv, 2)
    rows <- list()
    for (i in seq_len(ncol(cmb))) {
      a <- cmb[1, i]; b <- cmb[2, i]
      idx <- which(g %in% c(a, b))
      if (length(idx) < 4) next
      sub <- sub_comm[idx, , drop = FALSE]
      sub <- sub[, colSums(sub) > 0, drop = FALSE]
      if (ncol(sub) < 2) next
      d <- vegan::vegdist(sub, method = distance)
      df <- data.frame(grp = droplevels(factor(g[idx])))
      set.seed(seed)
      ad <- tryCatch(vegan::adonis2(d ~ grp, data = df, permutations = permutations,
                                    by = "terms", parallel = 0),
                     error = function(e) NULL)
      if (is.null(ad)) next
      rows[[length(rows) + 1]] <- data.frame(
        group1 = a, group2 = b, n1 = sum(g == a), n2 = sum(g == b),
        df = ad$Df[1], sum_sqs = round(ad$SumOfSqs[1], 4), R2 = round(ad$R2[1], 4),
        F = round(ad$F[1], 4), p = ad$`Pr(>F)`[1], permutations = permutations,
        stringsAsFactors = FALSE)
    }
    if (!length(rows)) return(data.frame())
    do.call(rbind, rows)
  }

  if (is.null(strata)) {
    out <- one_level(comm, grouping)
    if (!nrow(out)) return(out)
    out$p_adj <- stats::p.adjust(out$p, method = p.adjust.method)
    out$sig <- pd_sig(out$p_adj)
    return(out)
  }

  # ---- 分层：在 strata 每个水平内部做两两比较 ----
  st <- droplevels(factor(strata)); gp <- droplevels(factor(grouping))
  rows <- list()
  for (s in levels(st)) {
    idx <- which(st == s)
    if (length(idx) < 6) next
    sub <- comm[idx, , drop = FALSE]
    r <- one_level(sub, gp[idx])
    if (nrow(r)) rows[[length(rows) + 1]] <- cbind(stratum = s, r, stringsAsFactors = FALSE)
  }
  if (!length(rows)) return(data.frame())
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out$p_adj <- stats::p.adjust(out$p, method = p.adjust.method)
  out$sig <- pd_sig(out$p_adj)
  out
}

# ------------------------------------------------------------
# 40.2 内置两两 ANOSIM
#   strata：分层变量（在该变量每个水平内部做比较）
#   group ：在该水平内部变化的比较变量
#   原文两个方向：① 生境内比季节 ② 季节内比生境
# ------------------------------------------------------------
#   ★★ strata（= subset_by）同上：【只切子集】，不是受限置换（2026-09-25 pitfalls I10）
pd_pairwise_anosim <- function(comm, strata, group, distance = "bray",
                               permutations = 999, p.adjust.method = "BH", seed = 20260101) {
  if (!pd_has("vegan")) return(data.frame())
  st <- droplevels(factor(strata)); gp <- droplevels(factor(group))
  rows <- list()
  for (s in levels(st)) {
    idx <- which(st == s)
    if (length(idx) < 6) next
    sub <- comm[idx, , drop = FALSE]
    g <- droplevels(factor(gp[idx]))
    if (nlevels(g) < 2) next
    cmb <- utils::combn(levels(g), 2)
    for (i in seq_len(ncol(cmb))) {
      j <- which(g %in% cmb[, i])
      if (length(j) < 4) next
      sub2 <- sub[j, , drop = FALSE]
      sub2 <- sub2[, colSums(sub2) > 0, drop = FALSE]
      if (ncol(sub2) < 2) next
      set.seed(seed)
      a <- tryCatch(vegan::anosim(vegan::vegdist(sub2, method = distance),
                                  grouping = droplevels(factor(g[j])),
                                  permutations = permutations),
                    error = function(e) NULL)
      if (is.null(a)) next
      rows[[length(rows) + 1]] <- data.frame(
        stratum = s, group1 = cmb[1, i], group2 = cmb[2, i],
        n1 = sum(g == cmb[1, i]), n2 = sum(g == cmb[2, i]),
        R = round(a$statistic, 4), p = a$signif, permutations = permutations,
        stringsAsFactors = FALSE)
    }
  }
  if (!length(rows)) return(data.frame())
  out <- do.call(rbind, rows)
  out$p_adj <- stats::p.adjust(out$p, method = p.adjust.method)
  out$sig <- pd_sig(out$p_adj)
  out
}

# ------------------------------------------------------------
# 40.3 ANOSIM 秩分布箱线图（对应原文 plot(anosim)）
#   Between 的秩明显高于各组 → 组间差异大于组内
# ------------------------------------------------------------
# [第 3 轮删除] ANOSIM 秩分布箱线图 —— 用户决定删除 stats_tests_panel 及其组成图代码。
#   统计结果（R/p）仍在 anosim 表里；要看秩分布可临时恢复本函数。
pd_plot_anosim_rank <- function(...) NULL

# ------------------------------------------------------------
# 40.4 NMDS 绘图：combo（单图组合椭圆）/ facet（按因子分面）
# ------------------------------------------------------------
# 仅为对齐论文图外观：NMDS 图例/字号收敛 —— 旧版图例版幅过大 + 文字过大，把绘图区挤小
#   对照 60_box_panel 的协调比例（那是 legend.position="none"，所以不挤）
pd_nmds_legend_theme <- function(cfg = .pd$cfg) {
  bp <- (cfg$plot$base_pt %||% 9)
  ggplot2::theme(
    legend.position    = "bottom",     # ★ 第 3 轮：图例从 top/right 移到底部，不占版面
    legend.direction   = "horizontal",
    legend.justification = "center",
    legend.key.size    = grid::unit(0.5, "lines"),
    legend.key.height  = grid::unit(0.4, "lines"),
    legend.spacing.x   = grid::unit(0.08, "lines"),
    legend.margin      = ggplot2::margin(0, 0, 0, 0),
    legend.text        = ggplot2::element_text(size = bp - 1.5),
    legend.title       = ggplot2::element_text(size = bp - 1.5),
    axis.text          = ggplot2::element_text(size = bp - 1),
    axis.title         = ggplot2::element_text(size = bp),
    strip.text         = ggplot2::element_text(size = bp - 0.5),
    plot.margin        = ggplot2::margin(1, 1, 1, 1, "mm")
  )
}

pd_plot_nmds <- function(pd_data, cfg = .pd$cfg, mode = "combo",
                         shape_fac = NULL, stress = NA_real_) {
  if (!pd_has("ggplot2")) return(NULL)
  fac <- pd_design_factors(cfg)   # 单/双因素由 config$design$factor_mode 决定
  f1 <- fac[1]
  f2 <- if (length(fac) > 1) fac[2] else NULL
  if (!is.null(f2) && is.na(f2)) f2 <- NULL
  # 仅为对齐论文图外观：按着色因子身份取论文色板
  #   Season → nmds_season(#FF9C7A/#E8754A/#4BA4C9)；Habitat → nmds_habitat；组合 → nmds_habseas(9色)
  #   椭圆 alpha=0.6, linewidth=1（论文参数；旧版 0.12 太淡）
  pick_pal <- function(fname, k) {
    if (identical(fname, ".combo") || grepl("×", fname, fixed = TRUE))
      return(pd_pal("nmds_habseas", n = k, cfg = cfg))
    if (identical(fname, cfg$design$time) || grepl("season|time", fname, ignore.case = TRUE))
      return(pd_pal("nmds_season", n = k, cfg = cfg))
    pd_pal("nmds_habitat", n = k, cfg = cfg)
  }
  # ★ 第 3 轮：stress 放进图内（annotate），不再用 subtitle ——
  #   subtitle 会把图推下去留大片空白（用户反馈）
  sub <- sprintf("stress = %.3f", stress)

  if (identical(mode, "combo")) {
    grp <- if (!is.null(f2)) {
      pd_data$.combo <- factor(paste(pd_data[[f1]], pd_data[[f2]], sep = " | "))
      ".combo"
    } else f1
    lab <- if (!is.null(f2)) paste(f1, "×", f2) else f1
    pal <- pick_pal(grp, nlevels(factor(pd_data[[grp]])))
    use_shape <- !is.null(shape_fac) && shape_fac %in% names(pd_data)
    # ★ 第 3 轮修正：只映射 colour，不映射 fill —— 旧写法 labs(fill=NULL) 让 colour/fill
    #   各出一个图例（名称不同不合并）→ 图例版幅翻倍，把绘图区挤小。
    a <- if (use_shape)
      ggplot2::aes(x = .data$NMDS1, y = .data$NMDS2, colour = .data[[grp]],
                   shape = .data[[shape_fac]])
    else
      ggplot2::aes(x = .data$NMDS1, y = .data$NMDS2, colour = .data[[grp]])
    p <- ggplot2::ggplot(pd_data, a) +
      ggplot2::geom_point(size = 2) +
      ggplot2::stat_ellipse(type = "norm", level = 0.95, linetype = "dashed",
                            alpha = 0.6, linewidth = 1, show.legend = FALSE, fill = NA) +
      ggplot2::scale_colour_manual(values = pal) +
      ggplot2::guides(colour = ggplot2::guide_legend(reverse = TRUE, nrow = 1)) +
      ggplot2::labs(x = "NMDS1", y = "NMDS2", colour = lab) +
      ggplot2::annotate("text", x = -Inf, y = Inf, label = sub,
                        hjust = -0.08, vjust = 1.4, size = 2.6, fontface = "italic") +
      pd_theme() + pd_nmds_legend_theme(cfg)   # 图例/字号收敛，不压绘图区
    return(p + ggplot2::coord_fixed())
  }

  # facet：两张 —— 按 f1 分面（f2 着色）、按 f2 分面（f1 着色）
  out <- list()
  mkgrp <- function(facet_f, colour_f) {
    pal <- pick_pal(colour_f, nlevels(factor(pd_data[[colour_f]])))
    # ★ 只映射 colour（见上）：避免 colour+fill 双图例挤版面
    ggplot2::ggplot(pd_data, ggplot2::aes(x = .data$NMDS1, y = .data$NMDS2,
                                          colour = .data[[colour_f]])) +
      ggplot2::geom_point(size = 1.5) +
      ggplot2::stat_ellipse(type = "norm", level = 0.95, linetype = "dashed",
                            alpha = 0.6, linewidth = 1, show.legend = FALSE, fill = NA) +
      ggplot2::scale_colour_manual(values = pal) +
      ggplot2::guides(colour = ggplot2::guide_legend(reverse = TRUE, nrow = 1)) +
      ggplot2::facet_wrap(stats::as.formula(paste("~", facet_f)), nrow = 1) +
      ggplot2::labs(x = "NMDS1", y = "NMDS2", colour = colour_f) +
      ggplot2::annotate("text", x = -Inf, y = Inf, label = sub,
                        hjust = -0.08, vjust = 1.4, size = 2.6, fontface = "italic") +
      pd_theme() + pd_nmds_legend_theme(cfg) + ggplot2::coord_fixed()
  }
  if (!is.null(f2)) {
    out[[paste0("facet_", f1)]] <- mkgrp(f1, f2)
    out[[paste0("facet_", f2)]] <- mkgrp(f2, f1)
  } else {
    out[[paste0("facet_", f1)]] <- mkgrp(f1, f1)
  }
  out
}

# ------------------------------------------------------------
# 40.5 主入口
# ------------------------------------------------------------
pd_run_nmds <- function(cfg = .pd$cfg, dat = NULL, save = TRUE) {
  if (!pd_require("vegan", "40_ordination")) return(invisible(NULL))
  dat <- dat %||% pd_load_data(cfg)
  pd_msg("")
  pd_msg("### 40 NMDS + PERMANOVA + ANOSIM ###")

  ab <- dat$abundance
  mt <- dat$meta
  sid <- as.character(mt[[cfg$key$sample_id]])
  if (!all(rownames(ab) %in% sid)) {
    pd_warn("多度矩阵的样方名不全在元数据中，40 模块跳过")
    return(invisible(NULL))
  }
  mt <- mt[match(rownames(ab), sid), , drop = FALSE]
  dist <- cfg$opts$distance %||% "bray"
  perm_num <- as.integer(cfg$opts$runs %||% 999)
  # ★ 主检验用区组受限置换（opts$restrict_perm 设了才用，默认自由）；两两比较用整数（子集内自由置换）
  perm <- if (exists("pd_perm_ctrl", mode = "function"))
    pd_perm_ctrl(cfg, mt, nperm = perm_num) else perm_num
  layout <- cfg$opts$nmds_layout %||% "combo"    # combo | facet | both

  # ---- NMDS ----
  set.seed(cfg$opts$seed %||% 20260101)
  # metaMDS（trymax=50）是本模块耗时点 → 包缓存
  # ★★ autotransform 口径（2026-09-25，pitfalls I15）
  #   autotransform=TRUE 时 vegan 会【静默】做 sqrt（max>50）与 Wisconsin 双标准化（max>9），
  #   而 PERMANOVA/ANOSIM 用的是原始矩阵的 Bray → 【图与检验不同口径】，解释会打架。
  #   默认 FALSE 与检验一致；TRUE = 旧口径（opts$mds_autotransform=TRUE 可复现）。
  at <- cfg$opts$mds_autotransform %||% FALSE
  if (isTRUE(at))
    pd_msg("[40] metaMDS autotransform=TRUE（旧口径）—— 与 PERMANOVA 的原始距离【不同口径】")
  nm <- pd_cached("40_metaMDS", NULL, {
    tryCatch(vegan::metaMDS(ab, distance = dist, k = 2, trymax = 50,
                            autotransform = at, trace = FALSE),
             error = function(e) { pd_warn("metaMDS 失败: ", conditionMessage(e)); NULL })
  }, cfg = cfg)
  if (is.null(nm)) return(invisible(NULL))
  st <- nm$stress
  pd_msg(sprintf("[40] NMDS stress = %.4f —— %s", st, pd_stress_note(st)))
  # ★ stress > 0.2 → 自动试 k=3（2026-09-25）。2 维不可靠时只喊话没用，给可用的替代结果。
  if (is.finite(st) && st > 0.2 && isTRUE(cfg$opts$mds_try_k3 %||% TRUE)) {
    pd_msg("[40] stress > 0.2 → 自动试 k=3（结果存 nmds_k3，图仍是 2 维）")
    nm3 <- tryCatch(vegan::metaMDS(ab, distance = dist, k = 3, trymax = 50,
                                   autotransform = at, trace = FALSE),
                    error = function(e) NULL)
    if (!is.null(nm3) && is.finite(nm3$stress))
      pd_msg(sprintf("[40] k=3 的 stress = %.4f%s", nm3$stress,
                     if (nm3$stress < st) "（优于 k=2，建议正文用 3 维或改报 PCoA）" else ""))
    else nm3 <- NULL
  } else nm3 <- NULL

  pd_data <- data.frame(NMDS1 = nm$points[, 1], NMDS2 = nm$points[, 2],
                        sample_id = rownames(ab), stringsAsFactors = FALSE)
  fac <- pd_design_factors(cfg)   # 单/双因素由 config$design$factor_mode 决定
  for (f in fac) pd_data[[f]] <- mt[[f]]
  f1 <- fac[1]; f2 <- if (length(fac) > 1) fac[2] else NA
  shape_fac <- cfg$opts$nmds_shape
  figs <- list()
  if (layout %in% c("combo", "both")) {
    p <- pd_plot_nmds(pd_data, cfg, "combo", shape_fac = shape_fac, stress = st)
    # 单件已被 Fig 2 覆盖，仅 save_singles=TRUE 时出（便于逐图检查）
    if (!is.null(p) && isTRUE(cfg$plot$save_singles))
      figs$combo <- pd_save_pdf(p, "nmds_combo", "40", height_mm = 130)
  }
  if (layout %in% c("facet", "both")) {
    fl <- pd_plot_nmds(pd_data, cfg, "facet", shape_fac = shape_fac, stress = st)
    if (isTRUE(cfg$plot$save_singles))
      for (nmk in names(fl)) figs[[nmk]] <- pd_save_pdf(fl[[nmk]], paste0("nmds_", nmk), "40", height_mm = 95)
    if (length(fl) >= 2) {
      # 仅为对齐论文图外观：Fig 2 = 两分面上下拼 + (a)(b)，180×190mm
      #   论文源码 patchwork::p1/p2（按 Habitat 分面 / 按 Season 分面）
      both <- pd_compose(fl, ncol = 1, tags = (cfg$plot$paper_figs$fig2$tags %||% "a"))
      if (!is.null(both))
        figs$fig2_nmds <- pd_save_pdf(both, "nmds_fig2", "40",
                                      size = (cfg$plot$paper_figs$fig2$size %||% "fig2_nmds"))
    }
  }

  # ---- PERMANOVA ----
  pm_rows <- list()
  d <- vegan::vegdist(ab, method = dist)
  perm_form <- if (length(fac) >= 2) {
    if (identical(cfg$opts$permanova_model, "interaction"))
      stats::as.formula(paste("d ~", paste(sprintf("`%s`", fac[1:2]), collapse = " * ")))
    else
      stats::as.formula(paste("d ~", paste(sprintf("`%s`", fac[1:2]), collapse = " + ")))
  } else stats::as.formula(sprintf("d ~ `%s`", f1))

  set.seed(cfg$opts$seed %||% 20260101)
  # 置换检验是本模块耗时点 → 包缓存
  ad <- pd_cached("40_permanova", NULL, {
    tryCatch(vegan::adonis2(perm_form, data = mt, permutations = perm,
                            by = cfg$opts$permanova_by %||% "margin"),
             error = function(e) { pd_warn("adonis2 失败: ", conditionMessage(e)); NULL })
  }, cfg = cfg)
  permanova <- data.frame()
  if (!is.null(ad)) {
    adf <- as.data.frame(ad); adf$term <- rownames(adf)
    adf <- cbind(model = paste(deparse(perm_form), collapse = ""), adf)
    names(adf)[names(adf) == "Pr(>F)"] <- "p"
    adf$sig <- pd_sig(adf$p)
    permanova <- adf
    cat("\n--- PERMANOVA ---\n"); print(adf)
    tot <- sum(adf$R2[!is.na(adf$F)], na.rm = TRUE)
    pd_msg(sprintf("[40] PERMANOVA 解释量合计 R2 = %.3f（%s，置换 %d）",
                   tot, cfg$opts$permanova_by %||% "margin", perm))
  }

  # ★★ betadisper / PERMDISP（2026-09-25，pitfalls I12）
  #   PERMANOVA 显著【可能来自组间离散度差异】而非位置差异；ANOSIM 对离散度也敏感。
  #   不查 betadisper 就无法区分。这里对每个因子各跑一次，结果进 40_ordination.xlsx。
  disp <- tryCatch({
    do.call(rbind, lapply(fac, function(f) {
      g <- droplevels(factor(mt[[f]]))
      if (nlevels(g) < 2) return(NULL)
      bd <- vegan::betadisper(vegan::vegdist(ab, method = dist), g)
      pt <- vegan::permutest(bd, permutations = perm_num)
      pv <- pt$tab[["Pr(>F)"]][1]
      data.frame(factor = f, n_levels = nlevels(g),
                 F = round(pt$tab$F[1], 4), p = signif(pv, 4), sig = pd_sig(pv),
                 mean_dist_to_centroid = round(mean(bd$distances, na.rm = TRUE), 4),
                 stringsAsFactors = FALSE)
    }))
  }, error = function(e) { pd_warn("betadisper 失败: ", conditionMessage(e)); NULL })
  if (!is.null(disp) && nrow(disp)) {
    cat("\n--- betadisper（组间离散度同质性）---\n"); print(disp)
    bad <- disp$factor[which(disp$p < (cfg$opts$alpha %||% 0.05))]
    if (length(bad))
      pd_warn("betadisper 显著（组间离散度不齐）：", paste(bad, collapse = ", "),
              " → PERMANOVA/ANOSIM 的显著【可能来自离散度差异】而非位置差异，正文须区分")
    else pd_msg("[40] betadisper 全不显著 → 组间离散度齐，PERMANOVA 可按位置效应解释")
  }

  # ---- ANOSIM + 秩分布箱线图 ----
  ano_tab <- list(); ano_figs <- list()
  for (f in fac) {
    a <- tryCatch(vegan::anosim(ab, grouping = mt[[f]], permutations = perm, distance = dist),
                  error = function(e) NULL)
    if (is.null(a)) next
    ano_tab[[length(ano_tab) + 1]] <- data.frame(factor = f, R = round(a$statistic, 4),
                                                 p = a$signif, permutations = perm, sig = pd_sig(a$signif))
    pd_msg(sprintf("[40] ANOSIM %s：R = %.3f, p = %.4f", f, a$statistic, a$signif))
    # [第 3 轮删除] ANOSIM 秩图不再出（用户决定删 stats_tests_panel 组成图）
  }
  anosim_tab <- if (length(ano_tab)) do.call(rbind, ano_tab) else data.frame()

  # ---- 两两 PERMANOVA ----
  pw <- list()
  pw <- pd_cached("40_pw_permanova", NULL, {
    tmp <- list()
    if (!is.null(f2) && !is.na(f2)) {
      combo <- factor(paste(mt[[f1]], mt[[f2]], sep = " | "))
      tmp[[paste(f1, f2, sep = "_x_")]] <- pd_pairwise_permanova(
        ab, combo, distance = dist, permutations = perm_num,
        p.adjust.method = cfg$opts$multiple_adj)
    } else {
      tmp[[f1]] <- pd_pairwise_permanova(ab, mt[[f1]], distance = dist, permutations = perm_num,
                                         p.adjust.method = cfg$opts$multiple_adj)
    }
    tmp
  }, cfg = cfg)
  bind <- function(l) {
    z <- do.call(rbind, lapply(names(l), function(n) {
      x <- l[[n]]; if (is.null(x) || !nrow(x)) return(NULL)
      cbind(contrast = n, x)
    }))
    z
  }
  pw_perm <- bind(pw)

  # ---- 两两 ANOSIM（两个方向）----
  # 两两 ANOSIM（置换）→ 包缓存
  pw_ano_rows <- pd_cached("40_pw_anosim", NULL, {
    tmp <- list()
    if (!is.null(f2) && !is.na(f2)) {
      a1 <- pd_pairwise_anosim(ab, strata = mt[[f1]], group = mt[[f2]], distance = dist,
                               permutations = perm_num, p.adjust.method = cfg$opts$multiple_adj)
      if (nrow(a1)) tmp[["生境内比季节"]] <- cbind(direction = "within_f1_compare_f2", a1)
      a2 <- pd_pairwise_anosim(ab, strata = mt[[f2]], group = mt[[f1]], distance = dist,
                               permutations = perm_num, p.adjust.method = cfg$opts$multiple_adj)
      if (nrow(a2)) tmp[["季节内比生境"]] <- cbind(direction = "within_f2_compare_f1", a2)
    } else {
      a1 <- pd_pairwise_anosim(ab, strata = factor(rep("all", nrow(mt))), group = mt[[f1]],
                               distance = dist, permutations = perm_num,
                               p.adjust.method = cfg$opts$multiple_adj)
      if (nrow(a1)) tmp[["单因子"]] <- cbind(direction = "overall", a1)
    }
    tmp
  }, cfg = cfg)
  pw_anosim <- if (length(pw_ano_rows)) do.call(rbind, pw_ano_rows) else data.frame()
  rownames(pw_anosim) <- NULL
  if (nrow(pw_anosim)) {
    pd_msg(sprintf("[40] 两两 ANOSIM：%d 组比较，其中校正后显著 %d 组",
                   nrow(pw_anosim), sum(!(pw_anosim$sig %in% c("ns", "NA")), na.rm = TRUE)))
  }

  # ---- 分层两两 PERMANOVA（与上面的分层 ANOSIM 同口径；供 70 的 T1 出 18 行）----
  pw_perm_strat <- pd_cached("40_pw_permanova_strat", NULL, {
    tmp <- list()
    if (!is.null(f2) && !is.na(f2)) {
      a1 <- pd_pairwise_permanova(ab, grouping = mt[[f2]], strata = mt[[f1]],
                                  distance = dist, permutations = perm_num,
                                  p.adjust.method = cfg$opts$multiple_adj)
      if (nrow(a1)) tmp[["生境内比季节"]] <- cbind(direction = "within_f1_compare_f2", a1)
      a2 <- pd_pairwise_permanova(ab, grouping = mt[[f1]], strata = mt[[f2]],
                                  distance = dist, permutations = perm_num,
                                  p.adjust.method = cfg$opts$multiple_adj)
      if (nrow(a2)) tmp[["季节内比生境"]] <- cbind(direction = "within_f2_compare_f1", a2)
    } else {
      a1 <- pd_pairwise_permanova(ab, grouping = mt[[f1]],
                                  distance = dist, permutations = perm_num,
                                  p.adjust.method = cfg$opts$multiple_adj)
      if (nrow(a1)) tmp[["单因子"]] <- cbind(direction = "overall",
                                             stratum = "all", a1)
    }
    if (length(tmp)) do.call(rbind, tmp) else data.frame()
  }, cfg = cfg)
  if (is.data.frame(pw_perm_strat) && nrow(pw_perm_strat)) rownames(pw_perm_strat) <- NULL
  pd_msg(sprintf("[40] 分层两两 PERMANOVA：%d 组比较",
                 if (is.data.frame(pw_perm_strat)) nrow(pw_perm_strat) else 0L))

  out <- list(nmds = nm, points = pd_data, stress = st, figures = figs,
              permanova = permanova, anosim = anosim_tab, anosim_figures = ano_figs,
              pairwise = pw_perm, pairwise_anosim = pw_anosim,
              pairwise_permanova_strat = pw_perm_strat,
              distance = dist, layout = layout)
  if (save) {
    tabs <- list(nmds_points = pd_data,
                 permanova = permanova,
                 betadisper = if (is.null(disp)) data.frame() else disp,
                 anosim = anosim_tab,
                 pairwise_permanova = if (is.null(pw_perm)) data.frame() else pw_perm,
                 pairwise_permanova_strat = pw_perm_strat,
                 pairwise_anosim = pw_anosim,
                 run_info = data.frame(
                   item = c("距离", "置换次数", "置换方式", "PERMANOVA模型", "NMDS布局",
                            "stress", "多重校正", "autotransform"),
                   value = c(dist, perm_num,
                             if (is.null(cfg$opts$restrict_perm)) "自由置换" else
                               paste0("受限置换(blocks=", cfg$opts$restrict_perm, ")"),
                             cfg$opts$permanova_model %||% "additive",
                             layout, round(st, 4), cfg$opts$multiple_adj %||% "BH",
                             as.character(cfg$opts$mds_autotransform %||% TRUE)),
                   stringsAsFactors = FALSE))
    pd_write_table(tabs, stem = "ordination", module = "40")
  }
  invisible(out)
}
