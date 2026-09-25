# ============================================================
# 15_temporal.R · 时间自相关检验 + 差分
# 依赖：lmtest
# 对应原代码：lm(y ~ Season) + dwtest；对显著者做一阶差分
# ============================================================

pd_run_temporal <- function(cfg = .pd$cfg, dat = NULL, vars = NULL, save = TRUE) {
  if (!pd_require("lmtest", "15_temporal")) return(invisible(NULL))
  dat <- dat %||% pd_load_data(cfg)
  pd_msg("")
  pd_msg("### 15 时间自相关 ###")

  # ★★★ 设计门槛（2026-09-25）：只有【固定样方跟踪】才有时间自相关可测。
  #   "fixed_site"（站固定、样方每季重选）下，同站春/夏/秋是【不同物理样方】，
  #   按时间排序后跑 Durbin-Watson 是在测一个不存在的东西，输出无意义 p 值。
  #   用户 2026-09-25：「已有的多余代码也可以保留，因为这个 skill 是为以后的论文服务的」
  #   → 代码一行不删，只按 design$sampling 启用/跳过。
  samp <- if (exists("pd_design_sampling", mode = "function")) pd_design_sampling(cfg) else "fixed_site"
  if (!identical(samp, "fixed_plot")) {
    pd_warn("15 跳过：design$sampling = \"", samp,
            "\" 不是固定样方跟踪（fixed_plot），无时间自相关可测。",
            "若确为固定样地跨时间重复采样，请把 design$sampling 设为 \"fixed_plot\"。")
    return(invisible(NULL))
  }

  tv <- cfg$design$time
  if (is.null(tv) || is.na(tv) || !nzchar(tv) || !(tv %in% names(dat$meta))) {
    pd_warn("config$design$time 未指定或不在元数据中 → 15 模块跳过")
    return(invisible(NULL))
  }
  vars <- vars %||% c(cfg$response$alpha, cfg$response$func, cfg$response$phylo)
  vars <- vars[vars %in% names(dat$meta)]
  order_col <- cfg$design$ordered_levels[[tv]]
  # 记录表（需要按时间顺序排列样本）
  ord_id <- cfg$key$sample_id
  mt <- dat$meta
  if (!is.null(order_col)) mt[[tv]] <- factor(mt[[tv]], levels = order_col)
  rv <- cfg$design$random
  rv <- if (is.null(rv) || length(rv) == 0 || is.na(rv) || !nzchar(rv) || !(rv %in% names(mt))) NULL else rv
  key_df <- data.frame(sample_id = as.character(mt[[ord_id]]),
                       time_fac = as.character(mt[[tv]]),
                       site = if (is.null(rv)) "all" else as.character(mt[[rv]]),
                       stringsAsFactors = FALSE)
  key_df$time_num <- as.numeric(factor(key_df$time_fac, levels = order_col %||% unique(key_df$time_fac)))
  # 排序：先按 site，再按时间（同一 site 内构成时间序列）
  o <- order(key_df$site, key_df$time_num)
  key_df <- key_df[o, , drop = FALSE]

  rows <- list(); diff_tabs <- list()
  for (y in vars) {
    v <- dat$meta[[y]][match(key_df$sample_id, as.character(dat$meta[[ord_id]]))]
    d <- data.frame(y = v, t = key_df$time_num, site = key_df$site)
    d <- d[stats::complete.cases(d), , drop = FALSE]
    if (nrow(d) < 6) next

    # (a) 数值时间轴（原口径，残差含 site 效应 → DW 有偏）
    m_num <- stats::lm(y ~ t, data = d)
    dw_num <- tryCatch(lmtest::dwtest(m_num, alternative = "two.sided"), error = function(e) NULL)
    # (b) 数值时间轴 + site（推荐：残差不再混入样点效应）
    d$site <- factor(d$site)
    dw_site <- NULL
    if (nlevels(d$site) > 1 && nlevels(d$site) < nrow(d)) {
      m_site <- stats::lm(y ~ t + site, data = d)
      dw_site <- tryCatch(lmtest::dwtest(m_site, alternative = "two.sided"), error = function(e) NULL)
    }
    # (c) 与原代码一致的"因子时间轴"
    d$tf <- factor(d$t)
    m_fac <- stats::lm(y ~ tf, data = d)
    dw_fac <- tryCatch(lmtest::dwtest(m_fac, alternative = "two.sided"), error = function(e) NULL)

    rows[[y]] <- data.frame(
      variable = y, n = nrow(d),
      DW_noSite  = if (is.null(dw_num)) NA else round(unname(dw_num$statistic), 4),
      p_noSite   = if (is.null(dw_num)) NA else signif(dw_num$p.value, 4),
      DW_siteAdj = if (is.null(dw_site)) NA else round(unname(dw_site$statistic), 4),
      p_siteAdj  = if (is.null(dw_site)) NA else signif(dw_site$p.value, 4),
      DW_factor  = if (is.null(dw_fac)) NA else round(unname(dw_fac$statistic), 4),
      p_factor   = if (is.null(dw_fac)) NA else signif(dw_fac$p.value, 4),
      # 两个口径都给，但不要把任一当成定论（见下方警告）
      autocorrelated         = if (is.null(dw_num))  NA else dw_num$p.value  < cfg$opts$alpha,
      autocorrelated_siteAdj = if (is.null(dw_site)) NA else dw_site$p.value < cfg$opts$alpha,
      stringsAsFactors = FALSE)

    if (isTRUE(rows[[y]]$autocorrelated) || isTRUE(rows[[y]]$autocorrelated_siteAdj)) {
      # 一阶差分（按 site 分组，避免跨样点差分）
      dd <- d[order(d$site, d$t), , drop = FALSE]
      dd$diff_y <- ave(dd$y, dd$site, FUN = function(z) c(NA, diff(z)))
      diff_tabs[[y]] <- dd[, c("t", "site", "diff_y")]
      pd_msg(sprintf("[15] %s 存在自相关（DW=%.3f, p=%.4f）→ 已输出一阶差分列",
                     y, rows[[y]]$DW_noSite, rows[[y]]$p_noSite))
    }
  }
  if (!length(rows)) { pd_warn("15 模块无可用因变量"); return(invisible(NULL)) }
  summ <- do.call(rbind, rows)
  rownames(summ) <- NULL
  pd_warn("DW 检验在这种设计下只能作参考，不能当定论：")
  pd_warn("  ① 每个样点只有 3 个时间点，且序列是把各样点首尾拼起来的（样点边界不是真实的时间相邻）；")
  pd_warn("  ② 不调整 site 时残差里含样点效应 → 相邻点被样点效应拉近，偏向「正自相关」；")
  pd_warn("  ③ 把 site 当固定效应又会强制组内残差和为 0（3 个点）→ 机械地偏向「负自相关」；")
  pd_warn("  ④ 检验结果还依赖季节的排列顺序，结论会变。")
  pd_warn("  → 两列（autocorrelated / autocorrelated_siteAdj）都看；若要正式处理自相关，")
  pd_warn("    建议改用 nlme::lme(..., correlation = corAR1())，或按样点聚合后再检验。")
  cat("\n--- 时间自相关（Durbin-Watson）---\n"); print(summ)

  out <- list(summary = summ, diff = diff_tabs)

  # ★★ 检出结果要被下游消费（2026-09-25，pitfalls I7）
  #   旧写法只落盘一阶差分列，12/14/43/52 无一使用、也没有 corAR1 路径 →
  #   检测结果【不影响任何推断】。现在对检出变量补一条 corAR1 混合模型作对照。
  #   ★ 保留原有输出不动（用户：冗余能力保留），corAR1 是【新增对照】。
  flagged <- summ$variable[which(summ$autocorrelated %in% TRUE |
                                   summ$autocorrelated_siteAdj %in% TRUE)]
  ar1_tab <- NULL
  if (length(flagged)) {
    if (!pd_has("nlme")) {
      pd_warn("检出时间自相关，但缺 nlme 无法拟合 corAR1 对照",
              "（install.packages(\"nlme\")）；本次只给一阶差分列")
    } else {
      f1 <- pd_design_factors(cfg)[1]
      rs <- cfg$design$random %||% cfg$key$sample_id
      ar1_tab <- tryCatch({
        do.call(rbind, lapply(flagged, function(y) {
          dd <- dat$meta[stats::complete.cases(dat$meta[, c(y, tv, f1)]), , drop = FALSE]
          dd[[tv]] <- factor(dd[[tv]], levels = order_col %||% unique(dd[[tv]]))
          dd$.tn <- as.numeric(dd[[tv]])
          dd$.site <- factor(if (rs %in% names(dat$meta)) dat$meta[[rs]] else "all")
          dd <- dd[order(dd$.site, dd$.tn), , drop = FALSE]
          fm <- stats::as.formula(sprintf("`%s` ~ `%s`", y, f1))
          m0 <- tryCatch(nlme::lme(fm, data = dd, random = ~ 1 | .site), error = function(e) NULL)
          m1 <- tryCatch(nlme::lme(fm, data = dd, random = ~ 1 | .site,
                                   correlation = nlme::corAR1(form = ~ .tn | .site)),
                         error = function(e) NULL)
          if (is.null(m1)) return(NULL)
          s1 <- summary(m1)$tTable
          s0 <- if (!is.null(m0)) summary(m0)$tTable else NULL
          data.frame(variable = y,
                     term = rownames(s1),
                     p_corAR1 = signif(s1[, "p-value"], 4),
                     p_noAR1  = if (is.null(s0)) NA_real_ else signif(s0[rownames(s1), "p-value"], 4),
                     AIC_corAR1 = round(AIC(m1), 2),
                     AIC_noAR1  = if (is.null(m0)) NA_real_ else round(AIC(m0), 2),
                     stringsAsFactors = FALSE)
        }))
      }, error = function(e) { pd_warn("corAR1 对照失败: ", conditionMessage(e)); NULL })
      if (!is.null(ar1_tab))
        pd_msg(sprintf("[15] 已对 %d 个检出变量拟合 corAR1 对照（看 p_corAR1 vs p_noAR1）",
                       length(unique(ar1_tab$variable))))
    }
    if (is.null(ar1_tab))
      pd_warn("检出的时间自相关【尚未被下游模型消费】——如需正式处理请改用 nlme::lme(..., corAR1())，",
              "或用差分数据重跑 12/14/43/52")
  }
  out$ar1 <- ar1_tab

  if (save) {
    tabs <- list("dw_test" = summ)
    if (length(diff_tabs)) tabs$diff_values <- do.call(rbind, lapply(names(diff_tabs), function(n) {
      z <- diff_tabs[[n]]; z$variable <- n; z }))
    if (!is.null(ar1_tab)) tabs$corAR1_contrast <- ar1_tab
    pd_write_table(tabs, stem = "dw_autocorr", module = "15")
  }
  ac <- summ$variable[which(summ$autocorrelated %in% TRUE)]
  acs <- summ$variable[which(summ$autocorrelated_siteAdj %in% TRUE)]
  pd_msg(sprintf("[15] 未调整 site 时检出（DW p < %.3f）：%s", cfg$opts$alpha,
                 if (length(ac)) paste(ac, collapse = ", ") else "无"))
  pd_msg(sprintf("[15] 调整 site 后检出（DW p < %.3f）：%s", cfg$opts$alpha,
                 if (length(acs)) paste(acs, collapse = ", ") else "无"))
  pd_msg("[15] 两列不一致是正常的（机制见上面的警告）。差异大的指数建议用 corAR1 模型复核。")
  invisible(out)
}
