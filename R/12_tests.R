# ============================================================
# 12_tests.R · 组间比较（参数族 / 非参族）
# 参数族：单/双因素 ANOVA + Tukey HSD + 字母标记
# 非参族：Kruskal-Wallis + Dunn(校正) ；Scheirer-Ray-Hare + Nemenyi
# 依赖：car(诊断) multcomp(Tukey) dunn.test rcompanion(可选)
# ============================================================

# ------------------------------------------------------------
# 12.1 Tukey 字母标记（紧凑字母显示）
# ------------------------------------------------------------
# ★ adjust 形参【从不生效】：multcomp::glht(mcp(cell="Tukey")) + cld 走的是
#   Tukey 单步校正（与 TukeyHSD()[,"p adj"] 一致），不是 BH。
#   config$opts$multiple_adj="BH" 只影响 Dunn/Wilcoxon 路线，不影响 Tukey 字母。
#   保留形参只为向后兼容调用签名。
pd_tukey_letters <- function(df, y, cell_col, alpha = 0.05, adjust = "BH") {
  dat <- data.frame(y = df[[y]], cell = factor(df[[cell_col]]))
  dat <- dat[stats::complete.cases(dat), , drop = FALSE]
  dat$cell <- droplevels(dat$cell)
  cells <- levels(dat$cell); k <- length(cells)
  mx <- tapply(dat$y, dat$cell, max, na.rm = TRUE)
  nn <- as.integer(table(dat$cell))
  base <- data.frame(cell = cells, n = nn[cells], y_max = round(as.numeric(mx[cells]), 4),
                     stringsAsFactors = FALSE)
  if (k < 2) { base$letter <- "a"; return(base) }

  fit <- stats::aov(y ~ cell, data = dat)
  tk <- multcomp::glht(fit, linfct = multcomp::mcp(cell = "Tukey"))
  # ★★ level 是【显著性水平】，不是置信水平！（pitfalls I1，2026-09-25 实测修复）
  #   multcomp 源码：signif <- (object$test$pvalues < level)，默认 level = 0.05
  #   旧写法传 level = 1 - alpha = 0.95 → 几乎所有两两比较都"显著"→ 字母过度拆分，
  #   凭空造出不存在的显著差异。实测：p = 0.93/0.98/0.98 的三组，
  #   level=0.05 得 "a a a"（对），level=0.95 得 "c b a"（错）。
  cl <- tryCatch(multcomp::cld(tk, level = alpha, Letters = letters, decreasing = TRUE),
                 error = function(e) NULL)
  if (is.null(cl)) {
    pd_warn("multcomp::cld 失败，改用内置字母算法")
    return(pd_letters_builtin(dat, cells, alpha, base))
  }
  lt <- data.frame(cell = names(cl$mcletters$Letters),
                   letter = trimws(as.character(cl$mcletters$Letters)),
                   stringsAsFactors = FALSE)
  out <- merge(base, lt, by = "cell", all.x = TRUE, sort = FALSE)
  out$letter[is.na(out$letter)] <- ""
  out
}

# 内置 CLD：把每个组归入所有"与其不显著"的已有字母列（Piepho 思路的简化可靠版）
pd_letters_builtin <- function(dat, cells, alpha, base) {
  k <- length(cells)
  fit <- stats::aov(y ~ cell, data = dat)
  th <- stats::TukeyHSD(fit)$cell
  pmat <- matrix(1, k, k, dimnames = list(cells, cells))
  cb <- utils::combn(cells, 2)
  for (i in seq_len(ncol(cb)))
    pmat[cb[2, i], cb[1, i]] <- pmat[cb[1, i], cb[2, i]] <- th[i, "p adj"]
  ord <- order(tapply(dat$y, dat$cell, mean, na.rm = TRUE)[cells], decreasing = TRUE)
  cols <- list()
  for (ci in ord) {
    compat <- which(vapply(cols, function(g) all(pmat[ci, g] > alpha), logical(1)))
    if (!length(compat)) {
      cols[[length(cols) + 1]] <- ci
    } else {
      cols[[compat[1]]] <- c(cols[[compat[1]]], ci)
      for (extra in compat[-1]) cols[[extra]] <- c(cols[[extra]], ci)
    }
  }
  lab <- character(k); names(lab) <- cells
  for (j in seq_along(cols))
    for (ci in cols[[j]]) lab[ci] <- paste0(lab[ci], letters[j])
  base$letter <- lab[base$cell]
  base
}

# ------------------------------------------------------------
# 12.2 参数族：ANOVA (+ Tukey)
# ------------------------------------------------------------
pd_test_anova_tukey <- function(df, y, factors, alpha = 0.05,
                                include_interaction = TRUE, adjust = "BH") {
  f1 <- factors[1]; f2 <- if (length(factors) > 1) factors[2] else NULL
  dd <- df[stats::complete.cases(df[, c(y, factors)]), , drop = FALSE]
  for (f in factors) dd[[f]] <- droplevels(factor(dd[[f]]))

  form <- if (is.null(f2)) stats::as.formula(sprintf("`%s` ~ `%s`", y, f1))
          else if (include_interaction) stats::as.formula(sprintf("`%s` ~ `%s` * `%s`", y, f1, f2))
          else stats::as.formula(sprintf("`%s` ~ `%s` + `%s`", y, f1, f2))
  fit <- stats::aov(form, data = dd)
  # ★★ 平方和类型（2026-09-25，pitfalls I20）
  #   stats::anova(aov) 是【Type I 顺序平方和】——不平衡设计（本数据各水平 n≈57–63）下
  #   各 term 的 F/p/eta2 随公式项序变化。
  #   opts$anova_type = "III"（默认）→ car::Anova(type=3) + sum-to-zero 对比，顺序无关；
  #   "I" = 旧口径（stats::anova），可复现。
  atype <- (tryCatch(.pd$cfg$opts$anova_type, error = function(e) NULL)) %||% "III"
  if (identical(atype, "III") && pd_has("car")) {
    old_contr <- options(contrasts = c("contr.sum", "contr.poly"))
    on.exit(options(old_contr), add = TRUE)
    fit3 <- stats::aov(form, data = dd)
    a <- tryCatch(car::Anova(fit3, type = 3), error = function(e) NULL)
    options(old_contr); on.exit(NULL, add = FALSE)
    if (is.null(a)) { pd_warn("car::Anova(type=3) 失败 → 退回 Type I"); a <- stats::anova(fit) }
    else {
      a <- as.data.frame(a)
      names(a)[names(a) == "Df"] <- "Df"
      if (!"Sum Sq" %in% names(a)) names(a)[names(a) == "Sum Sq"] <- "Sum Sq"
      # Type III 表含 Residuals 行（car 会给），term 名保持
    }
  } else {
    if (identical(atype, "III")) pd_msg("[12] opts$anova_type=\"III\" 但缺 car 包 → 退回 Type I")
    a <- stats::anova(fit)
  }
  a <- as.data.frame(a)
  if (!"term" %in% names(a)) a$term <- rownames(a)
  ss_tot <- sum(a[, "Sum Sq"], na.rm = TRUE)
  terms <- as.character(a$term)   # 已含 "Residuals"，不可再补（曾导致 1/5/4 行数不匹配）
  anova_tab <- data.frame(
    variable = y,
    term = terms,
    df = a[, "Df"],
    SS = round(a[, "Sum Sq"], 4),
    F = round(a[, "F value"], 4),
    p = signif(a[, "Pr(>F)"], 4),
    sig = pd_sig(a[, "Pr(>F)"]),
    # η² = SS/SS_total（含残差，是真正的 eta²）；atype 记录平方和类型
    eta2 = round(a[, "Sum Sq"] / ss_tot, 4),
    ss_type = atype,
    stringsAsFactors = FALSE, row.names = NULL)

  # 交互组合的 Tukey 字母
  if (is.null(f2)) {
    cellv <- as.character(dd[[f1]])
  } else {
    cellv <- paste(dd[[f1]], dd[[f2]], sep = " | ")
  }
  dd$.cell <- factor(cellv)
  lt <- tryCatch(pd_tukey_letters(dd, y, ".cell", alpha = alpha, adjust = adjust),
                 error = function(e) { pd_warn("字母标记失败: ", conditionMessage(e)); NULL })
  tab <- stats::aggregate(dd[[y]], list(cell = dd$.cell), function(z)
    c(n = length(z), mean = mean(z, na.rm = TRUE), sd = stats::sd(z, na.rm = TRUE)))
  cell_tab <- data.frame(cell = tab$cell, n = tab$x[, "n"],
                         mean = round(tab$x[, "mean"], 4), sd = round(tab$x[, "sd"], 4),
                         stringsAsFactors = FALSE)
  if (!is.null(lt)) {
    cell_tab <- merge(cell_tab, lt[, c("cell", "letter", "y_max")],
                      by = "cell", all.x = TRUE, sort = FALSE)
  } else {
    cell_tab$letter <- NA_character_
    cell_tab$y_max <- NA_real_
  }
  cell_tab$variable <- y
  cell_tab <- cell_tab[, c("variable", "cell", "n", "mean", "sd", "letter", "y_max")]

  list(anova = anova_tab, cells = cell_tab, letters = lt, model = fit)
}

# ------------------------------------------------------------
# 12.3 非参族：单因子 Kruskal-Wallis + Dunn
# ------------------------------------------------------------
pd_test_kruskal_dunn <- function(df, y, factor, alpha = 0.05, adjust = "BH") {
  if (!pd_require("dunn.test", "12_tests/kruskal")) return(NULL)
  dd <- df[stats::complete.cases(df[, c(y, factor)]), , drop = FALSE]
  dd[[factor]] <- droplevels(factor(dd[[factor]]))
  kt <- stats::kruskal.test(dd[[y]], dd[[factor]])
  n <- nrow(dd); k <- nlevels(dd[[factor]])
  eps2 <- (kt$statistic - k + 1) / (n - k)          # epsilon squared
  kw <- data.frame(variable = y, factor = factor, chi2 = round(unname(kt$statistic), 4),
                   df = unname(kt$parameter), p = signif(kt$p.value, 4),
                   sig = pd_sig(kt$p.value), epsilon2 = round(eps2, 4),
                   stringsAsFactors = FALSE)
  # ★★ altp = TRUE 必须传（pitfalls I2，2026-09-25 实测修复）
  #   dunn.test 默认 altp=FALSE 返回 p = Pr(Z >= |z|)【单侧半 p】，
  #   包自己打印 "Reject Ho if p <= FDR/2"。拿它跟 alpha=0.05 判星 = 双侧 alpha=0.10，显著性虚高。
  #   实测同数据：altp=FALSE 得 0.0009，altp=TRUE 得 0.0018（正好 2 倍）。
  #   ⚠️ altp=TRUE 时返回槽位【改名】：altP / altP.adjusted（不是 P / P.adjusted）。
  d <- dunn.test::dunn.test(dd[[y]], dd[[factor]], method = adjust, kw = FALSE,
                            list = TRUE, altp = TRUE)
  p_raw <- d$altP          %||% d$P
  p_adj <- d$altP.adjusted %||% d$P.adjusted
  post <- data.frame(variable = y, comparison = d$comparisons,
                     Z = round(d$Z, 4), p = signif(as.numeric(p_raw), 4),
                     p_adj = signif(as.numeric(p_adj), 4),
                     sig = pd_sig(as.numeric(p_adj)), stringsAsFactors = FALSE)
  tab <- stats::aggregate(dd[[y]], list(cell = dd[[factor]]), function(z)
    c(n = length(z), median = stats::median(z, na.rm = TRUE), mean = mean(z, na.rm = TRUE)))
  cells <- data.frame(variable = y, cell = tab$cell, n = tab$x[, "n"],
                      median = round(tab$x[, "median"], 4), mean = round(tab$x[, "mean"], 4),
                      stringsAsFactors = FALSE)
  list(kruskal = kw, posthoc = post, cells = cells)
}

# ------------------------------------------------------------
# 12.4 非参族：双因子 Scheirer-Ray-Hare + Nemenyi
# ------------------------------------------------------------
pd_test_srh <- function(df, y, factors, alpha = 0.05) {
  if (!pd_require("rcompanion", "12_tests/SRH")) return(NULL)
  f1 <- factors[1]; f2 <- factors[2]
  dd <- df[stats::complete.cases(df[, c(y, factors)]), , drop = FALSE]
  dd[[f1]] <- droplevels(factor(dd[[f1]])); dd[[f2]] <- droplevels(factor(dd[[f2]]))
  form <- stats::as.formula(sprintf("`%s` ~ `%s` * `%s`", y, f1, f2))
  s <- rcompanion::scheirerRayHare(form, data = dd, tie.correct = TRUE, verbose = FALSE)
  s <- as.data.frame(s)
  s$term <- rownames(s)
  s <- s[!(s$term %in% c("Residuals", "Total")), , drop = FALSE]
  out <- data.frame(variable = y,
                    term = s$term,
                    Df = s$Df,
                    H = round(s$H, 4),
                    p = signif(s$p.value, 4),
                    sig = pd_sig(s$p.value),
                    stringsAsFactors = FALSE, row.names = NULL)
  # 各组中位数
  dd$.cell <- factor(paste(dd[[f1]], dd[[f2]], sep = " | "))
  tab <- stats::aggregate(dd[[y]], list(cell = dd$.cell), function(z)
    c(n = length(z), median = stats::median(z, na.rm = TRUE), mean = mean(z, na.rm = TRUE)))
  cells <- data.frame(variable = y, cell = tab$cell, n = tab$x[, "n"],
                      median = round(tab$x[, "median"], 4), mean = round(tab$x[, "mean"], 4),
                      stringsAsFactors = FALSE)
  # ★★ Nemenyi 事后比较（pitfalls I5，2026-09-25 实测修复）
  #   旧写法调 rcompanion::nemenyiTest —— 该函数【不在 rcompanion 导出表里】（实测导出表无、
  #   含 nemenyi 的导出为空）→ 必报错被 tryCatch 吞掉，"SRH+Nemenyi" 实际【永远没有事后比较】。
  #   改：优先 PMCMRplus::kwAllPairsNemenyiTest；都没有就【明确降级并警告】，不再静默。
  nm <- NULL
  nm_fun <- NULL
  if (pd_has("PMCMRplus") && exists("kwAllPairsNemenyiTest", where = asNamespace("PMCMRplus")))
    nm_fun <- PMCMRplus::kwAllPairsNemenyiTest
  else if (pd_has("rcompanion") && "nemenyiTest" %in% getNamespaceExports("rcompanion"))
    nm_fun <- rcompanion::nemenyiTest

  if (is.null(nm_fun)) {
    pd_warn("SRH 无事后比较：需要 PMCMRplus::kwAllPairsNemenyiTest（install.packages(\"PMCMRplus\")）",
            "；当前只出 SRH 主效应，Nemenyi 已跳过（不再静默失败）")
  } else {
    grab <- function(fac) {
      r <- tryCatch(nm_fun(stats::as.formula(sprintf("`%s` ~ `%s`", y, fac)), data = dd),
                    error = function(e) NULL)
      if (is.null(r)) return(NULL)
      st <- if (!is.null(r$statistics)) as.data.frame(r$statistics) else as.data.frame(r$p.value)
      pc <- grep("^p", names(st), value = TRUE)[1]
      if (is.na(pc)) pc <- names(st)[1]
      data.frame(variable = y, factor = fac, comparison = rownames(st),
                 p = signif(as.numeric(st[[pc]]), 4), stringsAsFactors = FALSE)
    }
    nm <- tryCatch(rbind(grab(f1), grab(f2)),
                   error = function(e) { pd_warn("Nemenyi 失败: ", conditionMessage(e)); NULL })
  }
  list(srh = out, cells = cells, nemenyi = nm)
}

pd_sig <- function(p, alpha = NULL) {
  # alpha 默认取 config$opts$alpha（曾硬编码 0.05，改 alpha 后星号会与 p 值自相矛盾）
  if (is.null(alpha)) alpha <- (tryCatch(.pd$cfg$opts$alpha, error = function(e) NULL) %||% 0.05)
  ifelse(is.na(p), "NA",
    ifelse(p < 0.001, "***", ifelse(p < 0.01, "**", ifelse(p < alpha, "*", "ns"))))
}

# ------------------------------------------------------------
# 12.4b 前提检查 → 自动选参/非参法（2026-09-25）
# ------------------------------------------------------------
#' 规则（保守）：任一响应变量违反【残差正态】或【方差齐】就整批走非参族。
#' health 提供了 01 的诊断结论就直接消费；否则就地跑 Shapiro + Levene。
#' 返回： "anova_tukey" | "kruskal_dunn"（单因素）| "nonparam_srh"（双因素）
pd_pick_test_method <- function(mt, vars, factors, health = NULL, cfg = .pd$cfg) {
  al <- cfg$opts$alpha %||% 0.05
  n_fac <- length(factors)
  default <- if (n_fac >= 2) "nonparam_srh" else "kruskal_dunn"

  # 1) 消费 01 的诊断结论（若有）
  if (!is.null(health)) {
    rec <- tryCatch({
      if (is.list(health) && !is.null(health$recommendation)) health$recommendation else NULL
    }, error = function(e) NULL)
    if (!is.null(rec) && any(grepl("非参|kruskal|scheirer|不满足|nonparam", rec, ignore.case = TRUE))) {
      pd_msg("[12] 01 体检建议非参法 → ", default)
      return(default)
    }
  }

  # 2) 就地做前提检查（每个变量：残差正态 + 组间方差齐）
  viol <- character(0)
  f1 <- factors[1]
  for (y in vars) {
    d <- mt[stats::complete.cases(mt[, c(y, factors)]), , drop = FALSE]
    if (nrow(d) < 8) next
    # 正态：对主因子残差做 Shapiro
    resid <- tryCatch(stats::residuals(stats::lm(as.formula(sprintf("`%s` ~ `%s`", y, f1)), data = d)),
                      error = function(e) NULL)
    if (!is.null(resid) && length(resid) >= 3 && length(resid) <= 5000) {
      sp <- tryCatch(stats::shapiro.test(resid)$p.value, error = function(e) NA_real_)
      if (is.finite(sp) && sp < al) viol <- c(viol, paste0(y, "(非正态)"))
    }
    # 方差齐：Levene（car）或 Bartlett
    lv <- tryCatch({
      if (pd_has("car")) car::leveneTest(as.formula(sprintf("`%s` ~ `%s`", y, f1)), data = d)$`Pr(>F)`[1]
      else stats::bartlett.test(as.formula(sprintf("`%s` ~ `%s`", y, f1)), data = d)$p.value
    }, error = function(e) NA_real_)
    if (is.finite(lv) && lv < al) viol <- c(viol, paste0(y, "(方差不齐)"))
  }
  if (length(viol)) {
    pd_msg(sprintf("[12] 前提不满足 %d 项 → 走非参族：%s", length(viol), paste(head(viol, 6), collapse = ", ")))
    return(default)
  }
  if (n_fac >= 2) "anova_tukey" else "anova_tukey"
}

# ------------------------------------------------------------
# 12.5 主入口
# ------------------------------------------------------------
pd_run_tests <- function(cfg = .pd$cfg, dat = NULL, method = NULL, vars = NULL,
                         health = NULL, save = TRUE, stem = NULL) {
  dat <- dat %||% pd_load_data(cfg)
  pd_msg("")
  pd_msg("### 12 组间比较 ###")
  # ★ 默认测【全部响应组】（2026-09-25）：旧写法只有 alpha+community，
  #   会漏掉 func/phylo（FRic/PD/mntd…）→ 70 的 T3/S2/t8 取不到源、报「无源」。
  #   现在与 60 的分组一致：alpha / func / phylo / community 全测。
  vars <- vars %||% unique(c(cfg$response$alpha, cfg$response$func,
                             cfg$response$phylo, cfg$response$community))
  vars <- vars[vars %in% names(dat$meta)]
  if (!length(vars)) { pd_warn("没有可用的因变量（config$response 与元数据列不匹配）"); return(invisible(NULL)) }

  # ★ 提示：本模块不纳入区组/随机效应（2026-09-25 实测 E1）
  #   同站样方距离相近 → 有空间/区组聚集。忽略它会让残差变大 → 【功效偏低】，
  #   不是「p 偏宽松出假显著」（实测 24 项 ANOVA vs LMM(1|Site) 对比 0 翻转，LMM 的 p 普遍更小）。
  #   要更稳健请 alpha_test = "lmm"（走 14_mixed_model）。
  rv <- cfg$design$random
  if (!is.null(rv) && !is.na(rv) && nzchar(rv) && rv %in% names(dat$meta) &&
      !identical(method, "lmm")) {
    pd_msg(sprintf("[12] 注意：本模块未纳入区组/随机效应 \"%s\"（%d 个水平）→ 功效偏低；",
                   rv, length(unique(dat$meta[[rv]]))))
    pd_msg("[12]   如需更稳健请设 opts$alpha_test = \"lmm\"（走 14_mixed_model + 随机效应）")
  }

  method <- method %||% cfg$opts$alpha_test %||% "anova_tukey"
  if (identical(method, "auto")) {
    # ★★ "auto" 真的自动选（2026-09-25，pitfalls I9）
    #   旧写法 "auto" 无条件落 anova_tukey，01 算出的 Shapiro/Bartlett/Levene 结论没人消费、
    #   health 形参全函数未用 → 前提不满足也不降级。
    #   现在：按【前提检查】决定参数族 / 非参族；health 提供了就优先用它。
    method <- pd_pick_test_method(dat$meta, vars, factors, health = health, cfg = cfg)
    pd_msg("[12] alpha_test=\"auto\" → 按前提检查选 ", method)
  }
  if (identical(method, "lmm")) {
    pd_msg("[12] 指定 lmm → 转交 14_mixed_model")
    return(pd_run_mixed(cfg = cfg, dat = dat, vars = vars, save = save))
  }
  factors <- pd_design_factors(cfg)        # 单/双因素由 config$design$factor_mode 决定
  factors <- factors[factors %in% names(dat$meta)]
  pd_msg(sprintf("[12] 方法 = %s | 因子 = %s | 因变量 = %s",
                 method, paste(factors, collapse = " × "), paste(vars, collapse = ", ")))

  anova_all <- list(); cells_all <- list(); post_all <- list(); lets_all <- list()
  for (y in vars) {
    r <- if (identical(method, "anova_tukey")) {
      pd_test_anova_tukey(dat$meta, y, factors, cfg$opts$alpha,
                          cfg$opts$include_interaction, cfg$opts$multiple_adj)
    } else if (identical(method, "nonparam_srh")) {
      if (length(factors) >= 2) pd_test_srh(dat$meta, y, factors[1:2], cfg$opts$alpha)
      else pd_test_kruskal_dunn(dat$meta, y, factors[1], cfg$opts$alpha, cfg$opts$multiple_adj)
    } else if (identical(method, "kruskal_dunn")) {
      # ★ 限制说明（2026-09-25）：双因子时 KW 被拆成【两个边际单因子检验】，无交互项。
      #   要交互请用 nonparam_srh（Scheirer-Ray-Hare）或 lmm。
      if (length(factors) >= 2 && !exists(".pd_kw_note", envir = .pd))
        pd_msg("[12] 注意：kruskal_dunn 对双因子是【两个边际单因子】检验，无交互项；",
               "要交互请 alpha_test=\"nonparam_srh\" 或 \"lmm\"")
      assign(".pd_kw_note", TRUE, envir = .pd)
      # 对每个因子分别做
      lapply(factors, function(f) pd_test_kruskal_dunn(dat$meta, y, f, cfg$opts$alpha, cfg$opts$multiple_adj))
    } else stop("未知方法: ", method, call. = FALSE)
    if (is.null(r)) next
    if (identical(method, "kruskal_dunn")) {
      for (rr in r) {
        if (is.null(rr)) next
        anova_all[[length(anova_all) + 1]] <- rr$kruskal
        post_all[[length(post_all) + 1]]  <- rr$posthoc
        cells_all[[length(cells_all) + 1]] <- rr$cells
      }
    } else {
      if (!is.null(r$anova)) anova_all[[length(anova_all) + 1]] <- r$anova
      if (!is.null(r$srh))   anova_all[[length(anova_all) + 1]] <- r$srh
      if (!is.null(r$kruskal)) anova_all[[length(anova_all) + 1]] <- r$kruskal
      if (!is.null(r$cells)) cells_all[[length(cells_all) + 1]] <- r$cells
      if (!is.null(r$posthoc)) post_all[[length(post_all) + 1]] <- r$posthoc
      if (!is.null(r$nemenyi)) post_all[[length(post_all) + 1]] <- r$nemenyi
      if (!is.null(r$letters)) lets_all[[length(lets_all) + 1]] <- r$letters
    }
  }
  bind <- function(l) if (length(l)) do.call(rbind, lapply(l, function(z) {
    z <- as.data.frame(z); z <- cbind(z, stringsAsFactors = FALSE); z })) else data.frame()
  out <- list(summary = bind(anova_all), cells = bind(cells_all),
              posthoc = bind(post_all), letters = bind(lets_all), method = method)

  if (nrow(out$summary)) {
    cat("\n--- 主检验结果 ---\n"); print(out$summary)
  }
  # ★ stem 可传 —— 60 的「补跑 Tukey 字母」用不同 stem，免得把 12_<method>.xlsx
  #   覆盖成子集（pitfalls H13：这坑踩过两次）
  if (save) pd_write_table(list("summary" = out$summary, "group_means" = out$cells,
                                "posthoc" = out$posthoc, "letters" = out$letters),
                           stem = stem %||% method, module = "12")
  pd_msg(sprintf("[12] 完成：%d 个因变量 × %d 个因子组合", length(vars), length(factors)))
  invisible(out)
}
