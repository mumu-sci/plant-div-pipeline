# ============================================================
# 01_data_health.R · 数据体检与判定
# 输出：results/01_data_health_*.xlsx  +  logs
# 作用：为"方法推荐"提供依据（见 references/01-method-menu.md §2）
# ============================================================

# ------------------------------------------------------------
# 1.1 变量分布诊断
# ------------------------------------------------------------
pd_diag_vars <- function(df, vars, factors = character(0), alpha = 0.05) {
  rows <- list()
  for (v in vars) {
    if (!v %in% names(df)) next
    x <- df[[v]]
    if (!is.numeric(x)) next
    p_sw <- tryCatch(stats::shapiro.test(x)$p.value, error = function(e) NA_real_)
    p_bar <- NA_real_; p_lev <- NA_real_
    if (length(factors)) {
      f1 <- factors[1]
      if (f1 %in% names(df) && nlevels(factor(df[[f1]])) > 1) {
        p_bar <- tryCatch(stats::bartlett.test(x ~ factor(df[[f1]]))$p.value, error = function(e) NA_real_)
        if (pd_has("car"))
          p_lev <- tryCatch(car::leveneTest(x ~ factor(df[[f1]]))$`Pr(>F)`[1], error = function(e) NA_real_)
      }
    }
    z <- as.numeric(scale(x))
    rows[[v]] <- data.frame(
      variable = v, n = sum(!is.na(x)), missing = sum(is.na(x)),
      mean = round(mean(x, na.rm = TRUE), 4), sd = round(stats::sd(x, na.rm = TRUE), 4),
      min = round(min(x, na.rm = TRUE), 4), max = round(max(x, na.rm = TRUE), 4),
      skew = round(mean(z^3, na.rm = TRUE), 3),
      shapiro_W = round(tryCatch(stats::shapiro.test(x)$statistic, error = function(e) NA_real_), 4),
      shapiro_p = round(p_sw, 4),
      normal_ok = ifelse(is.na(p_sw), NA, p_sw > alpha),      # 注意：p > alpha 才算正态（pitfalls D4）
      bartlett_p = round(p_bar, 4),
      var_hom_ok = ifelse(is.na(p_bar), NA, p_bar > alpha),
      levene_p = round(p_lev, 4),
      outliers_3sd = sum(abs(z) > 3, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  }
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}

# ------------------------------------------------------------
# 1.2 设计结构（因子水平 × 样本量）
# ------------------------------------------------------------
pd_diag_design <- function(df, factors) {
  factors <- factors[factors %in% names(df)]
  if (!length(factors)) return(list(cells = data.frame(), factors = data.frame()))
  fac_tab <- do.call(rbind, lapply(factors, function(f) {
    tb <- table(df[[f]])
    data.frame(factor = f, level = names(tb), n = as.integer(tb),
               ordered = !is.null(.pd$cfg$design$ordered_levels[[f]]),
               stringsAsFactors = FALSE)
  }))
  cells <- as.data.frame(table(df[factors]), stringsAsFactors = FALSE)
  names(cells)[seq_along(factors)] <- factors
  names(cells)[ncol(cells)] <- "n"
  list(cells = cells, factors = fac_tab,
       balanced = length(unique(cells$n)) == 1,
       min_cell = min(cells$n), max_cell = max(cells$n))
}

# ------------------------------------------------------------
# 1.3 方法推荐（决策树，见 01-method-menu.md §2.12）
# ------------------------------------------------------------
pd_recommend <- function(diag, design_info, cfg = .pd$cfg) {
  nfac <- length(cfg$design$factors)
  has_rand <- !is.null(cfg$design$random) && !is.na(cfg$design$random) && nzchar(cfg$design$random)
  n_rand_lv <- if (has_rand && cfg$design$random %in% names(diag)) length(unique(diag[[cfg$design$random]])) else 0
  nrm <- diag$normal_ok; if (is.null(nrm) || !length(nrm)) nrm <- NA
  vhom <- diag$var_hom_ok; if (is.null(vhom) || !length(vhom)) vhom <- NA
  ok_norm <- all(nrm %in% TRUE); ok_vhom <- all(vhom %in% TRUE)
  min_cell <- design_info$min_cell %||% 0

  rec <- list()
  # 主推荐
  if (has_rand && n_rand_lv >= 3 && nfac >= 1) {
    rec$primary <- "lmm"
    rec$reason <- sprintf("存在随机因子 %s（%d 个水平），且因变量可能非独立；推荐线性混合模型，并报传统检验作对照。",
                          cfg$design$random, n_rand_lv)
  } else if (nfac == 1) {
    if (isTRUE(ok_norm) && isTRUE(ok_vhom)) {
      rec$primary <- "anova_tukey"
      rec$reason <- "单因子：Shapiro p>α 且 Bartlett p>α → 单因素 ANOVA + Tukey HSD。"
    } else {
      rec$primary <- "kruskal_dunn"
      rec$reason <- sprintf("单因子：正态性%s、方差齐性%s 未全部满足 → Kruskal-Wallis + Dunn（校正）。",
                            ifelse(ok_norm, "满足", "不满足"), ifelse(ok_vhom, "满足", "不满足"))
    }
  } else if (nfac == 2) {
    can_inter <- min_cell >= 3
    if (isTRUE(ok_norm) && isTRUE(ok_vhom) && can_inter) {
      rec$primary <- "anova_tukey"
      rec$reason <- sprintf("两因子：正态性与方差齐性均满足，最小组合样本量 %d ≥ 3，可估交互 → 双因素 ANOVA（含交互）+ Tukey 字母标记。", min_cell)
    } else {
      rec$primary <- "nonparam_srh"
      rec$reason <- sprintf("两因子：正态性%s、方差齐性%s、最小组合样本量 %d → Scheirer-Ray-Hare + Nemenyi。",
                            ifelse(ok_norm, "满足", "不满足"), ifelse(ok_vhom, "满足", "不满足"), min_cell)
    }
  } else {
    rec$primary <- "lmm"
    rec$reason <- sprintf("因子数 %d ≥ 3，直接做多因素检验功效不足，推荐混合模型或先降维。", nfac)
  }
  rec$alternatives <- setdiff(c("anova_tukey", "nonparam_srh", "kruskal_dunn", "lmm"), rec$primary)
  rec$diagnostics_summary <- list(
    n_factors = nfac, factor_names = cfg$design$factors,
    has_random = has_rand, random = cfg$design$random, random_levels = n_rand_lv,
    all_normal = ok_norm, all_var_hom = ok_vhom,
    balanced = design_info$balanced, min_cell = min_cell, max_cell = design_info$max_cell
  )
  rec
}

# ------------------------------------------------------------
# 1.4 主入口
# ------------------------------------------------------------
pd_run_data_health <- function(cfg = .pd$cfg, dat = NULL, save = TRUE) {
  dat <- dat %||% pd_load_data(cfg)
  pd_msg("")
  pd_msg("### 01 数据体检 ###")

  # (a) 输入指纹
  fp <- data.frame(
    item = c("项目", "多度矩阵", "样方数", "物种数(原始列)", "物种数(清洗后)",
             "学名被规范化数", "NA->0 格子数", "元数据样方数", "性状表物种数",
             "物种对照表条目", "树 tips", "树有枝长", "sample_id 匹配数"),
    value = c(cfg$project,
              basename(cfg$files$abundance),
              dat$info$abundance$rows, dat$info$abundance$species_raw,
              dat$info$abundance$species,
              dat$info$abundance$name_changed, dat$info$abundance$na_to_zero,
              dat$info$meta$rows,
              dat$info$traits$rows %||% NA, dat$info$species$rows %||% NA,
              dat$info$tree$tips %||% NA,
              ifelse(is.null(dat$info$tree), NA, dat$info$tree$has_branch_length),
              dat$info$id_check$matched),
    stringsAsFactors = FALSE)

  # (a2) 多度数据类型：整数计数 vs 连续重要值
  # 这一条决定了 α 指数的解释口径，必须在 Methods 里写明（见代码审查 C1）
  ab0 <- dat$abundance
  int_like <- all(abs(ab0 - round(ab0)) < 1e-8, na.rm = TRUE)
  fp <- rbind(fp, data.frame(item = "多度数据类型",
                             value = if (int_like) "整数计数（个体数）" else "连续值（重要值/盖度等）",
                             stringsAsFactors = FALSE))
  if (!int_like) {
    pd_warn("多度矩阵是【连续值（重要值/盖度等）】而非个体计数。")
    pd_warn("       → Shannon / Simpson / Pielou 是「重要值基础上的多样性」，与「个体基础多样性」不等价；")
    pd_warn("       → vegan::rarefy 不可用（已自动跳过）；")
    pd_warn("       → 写 Methods 时必须写明这一点，否则会被审稿人质疑（见代码审查 C1）。")
  } else {
    pd_msg("[01] 多度矩阵为整数计数，α 指数可按个体基础解释。")
  }

  # (a3) 不可见字符扫描
  # trimws() 只认 [ \t\r\n]，不认 NBSP(U+00A0)/零宽字符 → 会让物种名静默匹配失败，
  # 也会让 V.PhyloMaker2 的 phylo.maker 误报「分类不一致」（实测 Erysimum 案例）
  inv_list <- list(
    pd_scan_invisible(colnames(dat$abundance), "多度矩阵列名(物种)"),
    pd_scan_invisible(if (!is.null(dat$traits)) dat$traits[[cfg$key$species]] else character(0),
                      "性状表物种"),
    pd_scan_invisible(if (!is.null(dat$tree)) dat$tree$tip.label else character(0),
                      "树 tip"),
    pd_scan_invisible(if (!is.null(dat$species)) dat$species[[cfg$key$species]] else character(0),
                      "物种对照表 species")
  )
  if (!is.null(dat$species)) {
    low2 <- tolower(names(dat$species))
    for (cc in c("genus", "family", "属", "科")) {
      i <- which(low2 == cc)
      if (length(i)) inv_list[[length(inv_list) + 1]] <-
        pd_scan_invisible(dat$species[[i[1]]], paste0("物种对照表 ", cc))
    }
  }
  inv <- do.call(rbind, Filter(Negate(is.null), inv_list))
  if (!is.null(inv) && nrow(inv)) {
    pd_warn(sprintf("检出不可见字符 %d 处（%d 类）——规范化函数已自动清理，但请修数据源",
                    sum(inv$n_hits), length(unique(inv$char_name))))
    for (i in seq_len(min(8, nrow(inv))))
      pd_warn(sprintf("       %s 含 %s（%s）× %d：%s",
                      inv$label[i], inv$char_name[i], inv$code[i], inv$n_hits[i], inv$examples[i]))
  } else {
    pd_msg("[01] 未检出不可见字符（NBSP / 零宽 / BOM / 制表符）。")
  }

  # (b) 物种名四方对齐
  al <- pd_species_align(dat, cfg)
  pd_msg(sprintf("[对齐] 各区物种数: %s | 四表交集 core = %d",
                 paste(sprintf("%s=%d", names(al$counts), al$counts), collapse = ", "), al$n_core))
  for (nm in names(al$only)) {
    if (length(al$only[[nm]]))
      pd_msg(sprintf("       仅在 %s 中（不在交集） %d 个: %s", nm, length(al$only[[nm]]),
                     paste(head(al$only[[nm]], 8), collapse = ", ")))
  }

  # (b2) 疑似同物异名
  syn <- pd_suspect_synonyms(al)
  if (nrow(syn)) {
    pd_msg(sprintf("[对齐] 疑似同物异名 %d 组（同属、种加词不同）——需人工/TPL 核对，本包不自动改名：", nrow(syn)))
    for (i in seq_len(min(8, nrow(syn))))
      pd_msg(sprintf("       %s: %s[%s] vs %s[%s]",
                     syn$genus[i], syn$set_A[i], syn$epithets_A[i], syn$set_B[i], syn$epithets_B[i]))
  }

  # (c) 设计结构
  dsign <- pd_diag_design(dat$meta, cfg$design$factors)

  # (d) 因变量诊断
  allvars <- unique(c(cfg$response$alpha, cfg$response$func, cfg$response$phylo))
  allvars <- allvars[allvars %in% names(dat$meta)]
  vdiag <- pd_diag_vars(dat$meta, allvars, cfg$design$factors, cfg$opts$alpha)
  if (nrow(vdiag)) {
    bad <- vdiag$variable[!(vdiag$normal_ok %in% TRUE)]
    if (length(bad)) pd_msg(sprintf("[诊断] 正态性未通过（Shapiro p<=%.2f）: %s",
                                    cfg$opts$alpha, paste(bad, collapse = ", ")))
    badv <- vdiag$variable[!(vdiag$var_hom_ok %in% TRUE)]
    if (length(badv)) pd_msg(sprintf("[诊断] 方差齐性未通过（Bartlett p<=%.2f）: %s",
                                     cfg$opts$alpha, paste(badv, collapse = ", ")))
  }

  # (d2) QQ 图（对应原文 qqPlot(lm(y ~ factor))，改为按变量 × 因子分面的出版图）
  qq_fig <- tryCatch(pd_qq_diagnostics(cfg, dat, allvars),
                     error = function(e) { pd_warn("QQ 图生成失败: ", conditionMessage(e)); NULL })

  # (e) 方法推荐
  rec <- pd_recommend(dat$meta, dsign, cfg)
  pd_msg(sprintf("[推荐] %s  —— %s", rec$primary, rec$reason))

  # (f) 运行日志（本次体检产生的全部警告）
  health <- list(fingerprint = fp, species_align = al$table, align_summary = al,
                 suspect_synonyms = syn, invisible_chars = inv,
                 design_cells = dsign$cells, design_levels = dsign$factors,
                 var_diag = vdiag, recommend = rec,
                 qq_figure = qq_fig,
                 warnings = data.frame(warning = .pd$warn, stringsAsFactors = FALSE))

  if (save) {
    pd_write_table(list(
      "input_fingerprint" = fp,
      "species_alignment" = al$table,
      "suspect_synonyms"  = if (nrow(syn)) syn else data.frame(),
      "invisible_chars"   = if (is.null(inv) || !nrow(inv)) data.frame() else inv,
      "design_cells"      = dsign$cells,
      "design_levels"     = dsign$factors,
      "var_diagnostics"   = vdiag,
      "method_recommend"  = data.frame(
        item = c("推荐方法", "推荐依据", "备选方法", "因子数", "因子", "随机因子",
                 "随机水平数", "全部正态", "全部方差齐", "设计平衡", "最小组合n", "最大组合n"),
        value = c(rec$primary, rec$reason, paste(rec$alternatives, collapse = ", "),
                  rec$diagnostics_summary$n_factors,
                  paste(rec$diagnostics_summary$factor_names, collapse = ", "),
                  rec$diagnostics_summary$random %||% "无",
                  rec$diagnostics_summary$random_levels,
                  rec$diagnostics_summary$all_normal, rec$diagnostics_summary$all_var_hom,
                  rec$diagnostics_summary$balanced,
                  rec$diagnostics_summary$min_cell, rec$diagnostics_summary$max_cell),
        stringsAsFactors = FALSE),
      "warnings"          = data.frame(warning = .pd$warn, stringsAsFactors = FALSE)
    ), stem = "health", module = "01")
  }
  invisible(health)
}

# ------------------------------------------------------------
# 1.5 QQ 图（正态性诊断可视化）
# 对应原文 `qqPlot(lm(y ~ Season))` / `qqPlot(lm(y ~ Habitat))`：
# 这里对每个因变量 × 每个分组因子拟合 lm(y ~ factor)，取残差画 QQ，
# 并在面板角上标 Shapiro p —— 与 var_diagnostics sheet 的数值同一来源。
# ------------------------------------------------------------
pd_qq_diagnostics <- function(cfg = .pd$cfg, dat = NULL, vars = NULL, save = TRUE) {
  if (!pd_require("ggplot2", "01_data_health/qq")) return(invisible(NULL))
  dat <- dat %||% pd_load_data(cfg)
  vars <- vars %||% unique(c(cfg$response$alpha, cfg$response$func, cfg$response$phylo))
  vars <- vars[vars %in% names(dat$meta)]
  factors <- cfg$design$factors[cfg$design$factors %in% names(dat$meta)]
  if (!length(vars) || !length(factors)) {
    pd_msg("[01/QQ] 因变量或分组因子为空，跳过 QQ 图")
    return(invisible(NULL))
  }

  rows <- list(); ann <- list()
  for (v in vars) for (f in factors) {
    d <- dat$meta[stats::complete.cases(dat$meta[, c(v, f)]), c(v, f), drop = FALSE]
    if (nrow(d) < 5) next
    fit <- tryCatch(stats::lm(stats::as.formula(sprintf("`%s` ~ `%s`", v, f)), data = d),
                    error = function(e) NULL)
    if (is.null(fit)) next
    r <- stats::residuals(fit)
    q <- stats::qqnorm(r, plot.it = FALSE)
    p_sw <- tryCatch(stats::shapiro.test(r)$p.value, error = function(e) NA_real_)
    ql <- stats::quantile(r, c(0.25, 0.75), names = FALSE)
    th <- stats::qnorm(c(0.25, 0.75))
    slope <- if (diff(th) == 0) 1 else diff(ql) / diff(th)
    rows[[length(rows) + 1]] <- data.frame(variable = v, factor = f,
                                           theoretical = q$x, sample = q$y, stringsAsFactors = FALSE)
    ann[[length(ann) + 1]] <- data.frame(
      variable = v, factor = f, intercept = ql[1] - slope * th[1], slope = slope, shapiro_p = p_sw,
      label = ifelse(is.na(p_sw), "Shapiro p = NA", sprintf("Shapiro p = %.3f", p_sw)),
      normal = ifelse(is.na(p_sw), NA, p_sw > (cfg$opts$alpha %||% 0.05)), stringsAsFactors = FALSE)
  }
  if (!length(rows)) { pd_msg("[01/QQ] 无可用组合，跳过"); return(invisible(NULL)) }
  d <- do.call(rbind, rows); a <- do.call(rbind, ann)
  a$lab_y <- Inf

  p <- ggplot2::ggplot(d, ggplot2::aes(x = .data$theoretical, y = .data$sample)) +
    ggplot2::geom_point(size = 0.55, alpha = 0.7, colour = "grey25") +
    ggplot2::geom_abline(data = a, ggplot2::aes(intercept = .data$intercept, slope = .data$slope),
                         colour = pd_pal("qq")[1], linewidth = 0.4, inherit.aes = FALSE) +
    ggplot2::geom_text(data = a, ggplot2::aes(x = -Inf, y = Inf, label = .data$label,
                                              colour = .data$normal),
                       hjust = -0.08, vjust = 1.6, size = (cfg$plot$base_pt %||% 9) * 0.30,
                       inherit.aes = FALSE) +
    ggplot2::scale_colour_manual(values = c(`TRUE` = "grey30", `FALSE` = pd_pal("qq")[2]), na.value = "grey30") +
    ggplot2::facet_grid(variable ~ factor, scales = "free") +
    pd_theme(compact = TRUE) +   # 多分面诊断图，用紧凑字号防溢出
    ggplot2::labs(x = "Theoretical quantiles", y = "Sample quantiles") +
    ggplot2::theme(legend.position = "none")

  f_h <- max(45, 32 * length(vars) + 30)
  # QQ 单件仅 save_singles=TRUE 时出；否则由 pd_run_diagnostics() 合成 01_data_diagnostics
  if (isTRUE(cfg$plot$save_singles))
    pd_save_pdf(p, "qq_normality", "01", height_mm = f_h)
  .pd$last_qq <- p   # 供 pd_run_diagnostics() 合成 01_data_diagnostics
  pd_msg(sprintf("[01/QQ] 已出 %d 个面板（%d 变量 × %d 因子）；红色标注 = 该组合残差非正态",
                 nrow(a), length(vars), length(factors)))
  if (save) utils::write.csv(a[, c("variable", "factor", "slope", "intercept", "shapiro_p", "normal")],
                             file.path(cfg$paths$results, "01_qq_shapiro.csv"),
                             row.names = FALSE, fileEncoding = "UTF-8")
  invisible(list(plot = p, table = a, file = pth))
}
