# ============================================================
# 32_phylo_signal.R · 系统发育信号（完整版）
#   ① phyloSignal(method="all") 全局信号统计
#   ② phyloCorrelogram 信号深度（耗时，开关控制）
#   ③ lipaMoran 局部信号
#   ④ barplot / dotplot / gridplot.phylo4d 性状-树联合可视化（含 LIPA 显著着色）
#   ⑤ phyloSim 模拟 + 两张图（耗时，开关控制 + 先报预估）
# 依赖：phylosignal + phylobase（缺包只报告并输出"就绪包"，不自作主张）
# ============================================================

pd_prep_p4d <- function(tree, traits, sp_col = NULL) {
  tr <- as.data.frame(traits)
  if (!is.null(sp_col) && sp_col %in% names(tr)) { rownames(tr) <- tr[[sp_col]]; tr[[sp_col]] <- NULL }
  tr <- tr[, vapply(tr, is.numeric, logical(1)), drop = FALSE]
  tree$tip.label <- normalize_species(tree$tip.label)
  common <- intersect(tree$tip.label, rownames(tr))
  tree <- ape::drop.tip(tree, setdiff(tree$tip.label, common))
  tr <- tr[common, , drop = FALSE]
  list(tree = tree, traits = tr, n = length(common))
}

pd_run_phylo_signal <- function(cfg = .pd$cfg, dat = NULL, tree = NULL, traits = NULL, save = TRUE) {
  dat <- dat %||% pd_load_data(cfg)
  pd_msg("")
  pd_msg("### 32 系统发育信号 ###")

  tree <- tree %||% dat$tree
  traits <- traits %||% dat$traits
  if (is.null(tree) || is.null(traits)) {
    pd_msg("[32] 需要树 + 性状表。")
    pd_msg("[32] 纪律：缺数据只报告不动手。已跳过。")
    return(invisible(NULL))
  }
  p <- pd_prep_p4d(tree, traits, cfg$key$species)
  pd_msg(sprintf("[32] 对齐后物种 = %d（树 tips = %d，性状行 = %d）",
                 p$n, length(tree$tip.label), nrow(as.data.frame(traits))))
  if (p$n < 8) { pd_warn("可用物种 < 8，系统发育信号不可靠，已跳过"); return(invisible(NULL)) }

  if (!pd_require(c("phylosignal", "phylobase"), "32_phylo_signal")) {
    if (save) {
      pd_write_table(list(traits_aligned = cbind(species = rownames(p$traits), p$traits)),
                     stem = "traits_aligned", module = "32")
      writeLines(ape::write.tree(p$tree), file.path(cfg$paths$results, "32_tree_aligned.tre"))
    }
    pd_msg("[32] 已输出对齐后的性状表与树（results/32_*），装好 phylosignal+phylobase 后可直接复跑。")
    return(invisible(NULL))
  }

  p4d <- tryCatch(phylobase::phylo4d(p$tree, p$traits), error = function(e) {
    pd_warn("phylo4d 构造失败: ", conditionMessage(e)); NULL })
  if (is.null(p4d)) return(invisible(NULL))

  # 性状数可能很多（封丘 37 个）→ 出图默认只取前若干个，避免刷出几十张 pdf
  n_plot <- as.integer(cfg$opts$phylo_signal_plot_traits %||% 5)
  plot_traits <- head(colnames(p$traits), max(1, n_plot))

  # ---- 1. 全局信号统计 ----
  # phyloSignal(method="all") 返回 list(stat = data.frame, pvalue = data.frame)
  #   行 = 性状，列 = 统计量（Cmean / I / K / K.star / Lambda）
  #   （早先误当成"每个统计量一个数值向量"，会报 'list' object cannot be coerced to type 'double'）
  # ★★ 显式传参（2026-09-25，pitfalls I24）
  #   形参名是 methods（复数），旧写法 method="1" 靠部分匹配才生效；reps 是置换次数，默认 999，
  #   旧写法没显式传、吃默认。现在都显式写。★ λ 的 p 是【置换 p】，不是 phytools 的似然比检验。
  sig_reps <- cfg$opts$signal_reps %||% 999
  sig <- tryCatch(phylosignal::phyloSignal(p4d = p4d, methods = "all", reps = sig_reps),
                  error = function(e) { pd_warn("phyloSignal 失败: ", conditionMessage(e)); NULL })
  sig_tab <- NULL; sig_wide <- NULL
  if (!is.null(sig) && !is.null(sig$stat) && !is.null(sig$pvalue)) {
    st <- as.data.frame(sig$stat); pv <- as.data.frame(sig$pvalue)
    sig_tab <- data.frame(
      trait     = rep(rownames(st), times = ncol(st)),
      statistic = rep(colnames(st), each = nrow(st)),
      value     = round(as.vector(as.matrix(st)), 4),
      p         = signif(as.vector(as.matrix(pv)), 4),
      stringsAsFactors = FALSE)
    sig_tab$sig <- pd_sig(sig_tab$p)
    # ★★ 多重比较校正（2026-09-25，pitfalls I19）
    #   5 统计量 × N 性状 = 几十个检验，旧写法原始 p 直接判显著。
    #   opts$signal_p_adjust = "BH"（默认）→ 按【每个统计量一族】校正（K/λ 各自一族）；
    #   "none" = 旧口径。
    padj <- cfg$opts$signal_p_adjust %||% "BH"
    if (!identical(padj, "none")) {
      sig_tab$p_adj <- ave(sig_tab$p, sig_tab$statistic,
                           FUN = function(z) p.adjust(z, method = padj))
      sig_tab$sig <- pd_sig(sig_tab$p_adj)
      pd_msg(sprintf("[32] 系统发育信号 p 按 %s 校正（每个统计量一族）；显著性看 p_adj 列", padj))
    } else sig_tab$p_adj <- sig_tab$p
    # 宽表（性状 × 统计量）便于直接对照原文
    sig_wide <- cbind(trait = rownames(st), round(st, 4))
    cat("\n--- 系统发育信号统计（前 8 行）---\n"); print(utils::head(sig_wide, 8))
    pd_msg(sprintf("[32] 统计量 %d 个 × 性状 %d 个 = %d 条（Cmean/I/K/K.star/Lambda，p 值见结果表）",
                   ncol(st), nrow(st), nrow(sig_tab)))
  } else if (!is.null(sig)) {
    pd_warn("phyloSignal 返回结构非预期（names = ", paste(names(sig), collapse = ","), "）")
  }

  # ---- 2. 系统发育相关图（耗时） ----
  # [第 3 轮] 绘图已删除（用户决定删 32_phylo4d_panel 组成图）；计算保留，结果在 correlogram 对象里。
  #   ★ 图不需要它 → FIGURE_ONLY 时直接跳过（每个性状数分钟 × N，是最慢的一步）
  #   ★ 计算本身也包缓存，避免下次重算
  crlg <- list()
  if (isTRUE(cfg$opts$FIGURE_ONLY %||% FALSE)) {
    pd_msg("[32] FIGURE_ONLY=TRUE → 跳过 phyloCorrelogram（不出图，且最慢）")
  } else if (isTRUE(cfg$opts$phylo_correlogram %||% FALSE)) {
    pd_msg("[32] phyloCorrelogram 为耗时步骤（每个性状数分钟）")
    crlg <- pd_cached("32_correlogram", NULL, {
      cl <- list()
      for (v in plot_traits) {
        cc <- tryCatch(phylosignal::phyloCorrelogram(p4d, trait = v),
                       error = function(e) { pd_warn("Correlogram 失败: ", v); NULL })
        if (!is.null(cc)) cl[[v]] <- cc
      }
      cl
    }, cfg = cfg)
  } else {
    pd_msg("[32] phyloCorrelogram 未开启（opts$phylo_correlogram = FALSE）")
  }

  # ---- 3. 局部信号 lipaMoran（p.value 是 物种 × 性状 矩阵）----
  lipa_reps <- as.integer(cfg$opts$lipa_reps %||% 999)
  pd_msg(sprintf("[32] lipaMoran 置换次数 = %d（opts$lipa_reps 可调；%d 物种 × %d 性状，耗时随此增长）",
                 lipa_reps, p$n, ncol(p$traits)))
  t0 <- Sys.time()
  # lipaMoran 置换是本模块耗时点 → 包缓存
  lipa <- pd_cached("32_lipaMoran", NULL, {
    tryCatch(phylosignal::lipaMoran(p4d, reps = lipa_reps),
             error = function(e) tryCatch(phylosignal::lipaMoran(p4d),
                                          error = function(e2) NULL))
  }, cfg = cfg)
  lipa_min <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
  lipa_tab <- NULL
  if (!is.null(lipa) && !is.null(lipa$p.value)) {
    pv <- as.matrix(lipa$p.value)
    lipa_tab <- data.frame(
      species = rep(rownames(pv), times = ncol(pv)),
      trait   = rep(colnames(pv), each = nrow(pv)),
      p       = round(as.vector(pv), 4), stringsAsFactors = FALSE)
    lipa_tab$p_adj <- lipa_tab$p
    if (!identical(padj <- cfg$opts$signal_p_adjust %||% "BH", "none"))
      lipa_tab$p_adj <- p.adjust(lipa_tab$p, method = padj)
    lipa_tab$significant <- lipa_tab$p_adj < cfg$opts$alpha
    pd_msg(sprintf("[32] lipaMoran 完成（用时 %.2f 分钟）：%d 个「物种 × 性状」组合，显著 %d 个（p_adj < %.3f，校正=%s，置换 %s 次）",
                   lipa_min, nrow(lipa_tab), sum(lipa_tab$significant, na.rm = TRUE),
                   cfg$opts$alpha, cfg$opts$signal_p_adjust %||% "BH", lipa$reps %||% lipa_reps))
  }

  # ---- 4. 性状-树联合可视化（phylo4d 套图）----
  # [第 3 轮删除] 用户决定删除 32_phylo4d_panel 及其绘图代码（barplot/dotplot/gridplot.phylo4d
  #   + 逐性状 barplot + correlogram 图）。phyloSignal 统计表、lipaMoran 表、phyloSim 图（Fig S2）保留。
  p4d_figs <- list()

  # ---- 5. phyloSim 模拟（耗时，默认关闭；开启前给预估）----
  sim <- NULL; sim_figs <- list(); sim_min <- NA_real_
  if (isTRUE(cfg$opts$phylo_sim %||% FALSE)) {
    nsim <- as.integer(cfg$opts$phylo_sim_nsim %||% 100)
    reps <- as.integer(cfg$opts$phylo_sim_reps %||% 99)
    pd_msg(sprintf("[32] phyloSim 开始：nsim = %d, reps = %d（原文注释标为「耗时，慎用」）", nsim, reps))
    pd_msg("[32] 若首次运行建议先降到 nsim=10, reps=9 测时间，再决定正式参数。")
    t0 <- Sys.time()
    sim <- pd_cached("32_phyloSim", NULL, {
      tryCatch(phylosignal::phyloSim(tree = p$tree, method = "all", nsim = nsim, reps = reps),
               error = function(e) { pd_warn("phyloSim 失败: ", conditionMessage(e)); NULL })
    }, cfg = cfg)
    sim_min <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
    if (!is.null(sim)) {
      pd_msg(sprintf("[32] phyloSim 完成，用时 %.2f 分钟", sim_min))
      sim_files <- character(0)
      if (nsim < 50 || reps < 20)
        pd_warn(sprintf("[32] phyloSim 参数偏低（nsim=%d, reps=%d）→ p 值离散，堆叠图可能看不到连续曲线。原文 nsim=100, reps=99。", nsim, reps))
      fp <- pd_capture_plot(
        graphics::plot(sim, stacked.methods = FALSE, quantiles = c(0.05, 0.95)),
        "phylosim_separate", "32", width_mm = 190, height_mm = 157)   # 论文 Fig S2 尺寸
      if (!is.null(fp)) sim_files <- c(sim_files, fp)
      # 第 2 页：堆叠图。
      #  ★ 第 3 轮修正：论文写 what="pval"，但实测 what="pval" 出 22KB（内容稀疏、看不到曲线），
      #    what="stat" 出 30KB（统计量曲线完整）。Fig S2 caption 说的是
      #    "Blomberg's K and Pagel's λ tests" = 统计量本身 → 用 what="stat"。
      #    另：what 只认 "stat"/"pval"，"quantile"/"pvalue" 会报错。
      fp <- tryCatch(pd_capture_plot({
        tryCatch(graphics::plot(sim, what = "stat", stacked.methods = TRUE,
                                quantiles = c(0.05, 0.95)),
                 error = function(e) graphics::plot(sim, what = "pval", stacked.methods = TRUE,
                                                    quantiles = c(0.05, 0.95)))
      }, "phylosim_stacked_stat", "32", width_mm = 190, height_mm = 157),
      error = function(e) { pd_warn("phyloSim 堆叠图失败: ", conditionMessage(e)); NULL })
      if (!is.null(fp)) sim_files <- c(sim_files, fp)
      # Fig S2 等价图：phyloSim 分开图 + 堆叠图 合成一张
      sim_figs$panel <- pd_combine_pdfs(sim_files, "phylosignal_panel", "32", cfg = cfg)
    }
  } else {
    pd_msg("[32] phyloSim 未开启（opts$phylo_sim = FALSE）。")
    pd_msg("[32] 开启前请注意：nsim × reps 是长任务（原文 nsim=100, reps=99），建议先小参数测时间。")
  }

  out <- list(phyloSignal = sig_tab, correlogram = crlg, lipaMoran = lipa_tab,
              phyloSim = sim, sim_minutes = sim_min, p4d = p4d,
              traits = p$traits, tree = p$tree,
              figures = sim_figs)   # [第 3 轮] 只保留 phyloSim 图（Fig S2）
  if (save) {
    tabs <- list(
      phylo_signal = if (is.null(sig_tab)) data.frame() else sig_tab,
      phylo_signal_wide = if (is.null(sig_wide)) data.frame() else sig_wide,
      lipa_moran = if (is.null(lipa_tab)) data.frame() else lipa_tab,
      traits_aligned = cbind(species = rownames(p$traits), p$traits))
    if (!is.null(sim)) {
      # 复刻原文 phylosim_data.xlsx 的三个 sheet
      tabs$sim_stat <- pd_obj_to_df(sim$sim.stat, "sim.stat")
      tabs$sim_pvalue <- pd_obj_to_df(sim$sim.pvalue, "sim.pvalue")
      tabs$stat_names <- data.frame(stat_name = as.character(sim$stat.names), stringsAsFactors = FALSE)
    }
    tabs$run_info <- data.frame(
      item = c("对齐物种数", "树 tips", "性状数", "出图性状数", "phyloSim", "nsim", "reps", "phyloSim耗时(分)"),
      value = c(p$n, length(p$tree$tip.label), ncol(p$traits), length(plot_traits),
                !is.null(sim), cfg$opts$phylo_sim_nsim %||% NA, cfg$opts$phylo_sim_reps %||% NA,
                ifelse(is.na(sim_min), NA, sim_min)), stringsAsFactors = FALSE)
    pd_write_table(tabs, stem = "signal", module = "32")
  }
  invisible(out)
}
