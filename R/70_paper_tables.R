# ============================================================
# 70_paper_tables.R · 论文表格导出（tables.docx）
# 范围铁律：只做论文里实际存在的 5 个表 —— T1/T2/T3（正文）+ S1/S2（附录）。
#           不是每个分析都做一张三线表。新分析只换因子名/响应变量（config$table）。
# 数据口径：只从 results/*.xlsx 现有结果表搬运，不重算、不发明；
#           缺源 → 跳过该表并在 tables_register 标 skipped。
# 格式基准：三线表（无竖线/无网格/无底纹）、Times New Roman 8pt、表居中。
# 详见 references/04-paper-tables.md
# 依赖：flextable + officer（缺则降级跳过并给安装命令）
# ============================================================

# ------------------------------------------------------------
# 70.1 格式化（纯字符串拼接，不改数值本身）
# ------------------------------------------------------------

#' p 值格式化
#' @param p        数值向量
#' @param stars    TRUE = 尾随显著性星号（T3/S1 论文有）；FALSE = 纯数值（T1/T2 论文无）
#' @param style    "lt001" = "<0.001 ***"（用户选定的规范写法）；"paper" = "0***"（仅供对照）
pd_fmt_p <- function(p, stars = TRUE, style = NULL, digits = NULL, cfg = .pd$cfg) {
  if (is.null(p) || !length(p)) return("-")   # 缺列/空 → 占位符，不返回 character(0)
  style  <- style  %||% (cfg$table$p_fmt %||% "lt001")
  digits <- digits %||% (cfg$table$digits$p %||% 3)
  thr <- 10^(-digits)
  vapply(p, function(pi) {
    if (is.na(pi)) return("-")
    sg <- pd_sig(pi)
    star <- if (isTRUE(stars) && !identical(sg, "ns") && !identical(sg, "NA")) paste0(" ", sg) else ""
    if (pi < thr) {
      small <- if (identical(style, "paper")) "0" else
        paste0("<", formatC(thr, format = "f", digits = digits))
      paste0(small, star)
    } else {
      paste0(formatC(pi, format = "f", digits = digits), star)
    }
  }, character(1))
}

#' 数值格式化（三位小数；NA → "-"）
pd_fmt_num <- function(x, digits = NULL, cfg = .pd$cfg) {
  if (is.null(x) || !length(x)) return("-")
  digits <- digits %||% (cfg$table$digits$num %||% 3)
  ifelse(is.na(x), "-", formatC(x, format = "f", digits = digits))
}

#' mean±SD 组合单元（S2；两位小数）
pd_fmt_mean_sd <- function(m, s, d = NULL, cfg = .pd$cfg) {
  if (is.null(m) || is.null(s) || !length(m) || !length(s)) return("-")
  d <- d %||% (cfg$table$digits$mean_sd %||% 2)
  ifelse(is.na(m) | is.na(s), "-",
         paste0(formatC(m, format = "f", digits = d), "\u00b1",
                formatC(s, format = "f", digits = d)))
}

#' 论文变量名 → 实际列名（别名解析，同 60_plots 的 pd_match_var）
#'   config$table$vars 写的是论文名（FRic / SES.MNTD），结果表与 meta 里是
#'   F.Ric / mntd —— 不解析就取不到值，表里出 "-"。见 04-paper-tables.md
pd_table_vars <- function(cfg, cols) {
  disp <- cfg$table$vars %||% character(0)
  if (!length(disp)) return(list(disp = character(0), act = character(0)))
  act <- vapply(disp, function(v) {
    if (v %in% cols) return(v)
    hit <- tryCatch(pd_match_var(v, cols), error = function(e) "")
    if (is.null(hit) || !nzchar(hit[1])) v else hit[1]
  }, character(1), USE.NAMES = FALSE)
  list(disp = disp, act = act)
}

# ------------------------------------------------------------
# 70.2 三线表渲染（论文样式「三线表2」：无竖线、无网格、无底纹）
#   顶线 1.5pt ｜ 表头下 0.5pt ｜ 底线 1.5pt
# ------------------------------------------------------------
pd_three_line <- function(ft, font = NULL, size_pt = NULL, cfg = .pd$cfg) {
  if (!pd_has("flextable") || !pd_has("officer")) return(ft)
  font    <- font    %||% (cfg$table$font %||% "Times New Roman")
  size_pt <- size_pt %||% (cfg$table$size_pt %||% 8)
  b_top <- officer::fp_border(width = 1.5, color = "black")
  b_mid <- officer::fp_border(width = 0.5, color = "black")
  b_bot <- officer::fp_border(width = 1.5, color = "black")
  ft <- flextable::border_remove(ft)
  ft <- flextable::hline_top(ft, border = b_top, part = "header")
  ft <- flextable::hline_bottom(ft, border = b_mid, part = "header")   # 表头/表体分界
  ft <- flextable::hline_bottom(ft, border = b_bot, part = "body")
  ft <- flextable::font(ft, fontname = font, part = "all")
  ft <- flextable::fontsize(ft, size = size_pt, part = "all")
  ft <- flextable::bold(ft, part = "header")
  ft <- flextable::align(ft, align = "center", part = "header")
  ft <- flextable::align(ft, align = "center", part = "body")
  ft <- flextable::padding(ft, padding = 2, part = "all")
  ft
}

# 把 data.frame 变 flextable 并套三线（正文首列左对齐，数值列居中）
#   labels：显示用列头（允许重复/空串）；内部 col_keys 强制唯一（flextable 硬要求）
pd_as_table <- function(df, labels = names(df), cfg = .pd$cfg) {
  if (!pd_has("flextable")) return(NULL)
  keys <- paste0("c", seq_len(ncol(df)))
  names(df) <- keys
  ft <- flextable::flextable(df)
  ft <- flextable::set_header_labels(ft, values = stats::setNames(as.list(as.character(labels)), keys))
  ft <- pd_three_line(ft, cfg = cfg)
  ft <- flextable::align(ft, j = 1, align = "left", part = "body")
  ft
}

# ------------------------------------------------------------
# 70.3 五个 builder（各自返回 flextable；输入是已解析好的 data.frame）
# ------------------------------------------------------------

#' T1 · ANOSIM + PERMANOVA 两两比较（正文 Table 1）
#'   ano : pairwise_anosim（direction, stratum, group1, group2, R, p）
#'   perm: 分层两两 PERMANOVA（stratum, group1, group2, F, R2, p）
#'   分组顺序 = 先在 factors[1] 每水平内比 factors[2]，再反过来（同论文）
pd_table_t1 <- function(ano, perm, cfg = .pd$cfg) {
  if (is.null(ano) || !nrow(ano)) { pd_warn("T1 跳过：缺 pairwise_anosim"); return(NULL) }
  fac <- pd_design_factors(cfg, source = "table")   # 单/双因素一个来源
  f1 <- fac[1]                       # 主因子（双因素 = Habitat）
  f2 <- if (length(fac) > 1) fac[2] else NA   # 副因子（双因素 = Season）；单因素 = NA

  # ---------- 单因素分支（factor_mode="single"）----------
  # 只有一个因子 → 两两比较无「分层」概念，出 overall 两两，ANOSIM + PERMANOVA 仍并排
  if (is.na(f2)) {
    d0 <- if ("direction" %in% names(ano)) ano[ano$direction %in% c("overall", NA), , drop = FALSE] else ano
    if (!nrow(d0)) d0 <- ano
    f1_lv <- cfg$design$ordered_levels[[f1]] %||% unique(c(as.character(d0$group1), as.character(d0$group2)))
    cmb <- utils::combn(as.character(f1_lv), 2)
    pick <- function(dat, a, b) {
      if (is.null(dat) || !nrow(dat) || !all(c("group1", "group2") %in% names(dat))) return(NULL)
      hit <- dat[((dat$group1 == a & dat$group2 == b) | (dat$group1 == b & dat$group2 == a)), , drop = FALSE]
      if (!nrow(hit)) NULL else hit[1, , drop = FALSE]
    }
    rows <- list()
    for (i in seq_len(ncol(cmb))) {
      a <- cmb[1, i]; b <- cmb[2, i]
      ar <- pick(d0, a, b); pr <- pick(perm, a, b)
      rows[[i]] <- data.frame(
        contrast = paste(a, b, sep = " / "),
        R  = pd_fmt_num(if (!is.null(ar)) ar$R else NA_real_, cfg = cfg),
        pA = pd_fmt_p(if (!is.null(ar)) ar$p else NA_real_, stars = FALSE, cfg = cfg),
        F  = pd_fmt_num(if (!is.null(pr)) pr$F else NA_real_, cfg = cfg),
        R2 = pd_fmt_num(if (!is.null(pr)) pr$R2 else NA_real_, cfg = cfg),
        pP = pd_fmt_p(if (!is.null(pr)) pr$p else NA_real_, stars = FALSE, cfg = cfg),
        stringsAsFactors = FALSE)
    }
    body <- do.call(rbind, rows)
    names(body) <- c("", "R", "p", "F", "R2", "p")
    if (!pd_has("flextable")) return(NULL)
    keys <- paste0("c", seq_len(ncol(body)))
    names(body) <- keys
    ft <- flextable::flextable(body)
    ft <- flextable::set_header_labels(ft, values = stats::setNames(
      as.list(c("", "R", "p", "F", "R2", "p")), keys))
    ft <- flextable::add_header_row(ft, top = TRUE,
                                    values = c("", "ANOSIM", "PERMANOVA"),
                                    colwidths = c(1, 2, 3))
    ft <- pd_three_line(ft, cfg = cfg)
    ft <- flextable::align(ft, j = 1, align = "left", part = "body")
    return(ft)
  }

  # 两方向：within_f1_compare_f2 = 在 f1 每水平内比 f2；within_f2_compare_f1 = 反过来
  d1 <- ano[ano$direction == "within_f1_compare_f2", , drop = FALSE]
  d2 <- ano[ano$direction == "within_f2_compare_f1", , drop = FALSE]

  # 论文顺序：f1 的水平按 config 顺序，每个下面 f2 的 3 个对比
  f1_lv <- cfg$design$ordered_levels[[f1]] %||% unique(as.character(ano$stratum))
  f2_lv <- cfg$design$ordered_levels[[f2]] %||% unique(as.character(ano$group1))

  pick_pair <- function(dat, stratum, a, b, dir = NULL) {
    if (is.null(dat) || !nrow(dat)) return(NULL)
    d <- dat
    if (!is.null(dir) && "direction" %in% names(d)) d <- d[d$direction == dir, , drop = FALSE]
    hit <- d[as.character(d$stratum) == stratum &
               ((as.character(d$group1) == a & as.character(d$group2) == b) |
                  (as.character(d$group1) == b & as.character(d$group2) == a)), , drop = FALSE]
    if (!nrow(hit)) return(NULL)
    hit[1, , drop = FALSE]
  }
  cmb_f2 <- utils::combn(as.character(f2_lv), 2)   # 论文上半：在 f1 内比 f2
  cmb_f1 <- utils::combn(as.character(f1_lv), 2)   # 论文下半：在 f2 内比 f1

  rows <- list()
  push <- function(dat, dir, stratum, a, b) {
    ar <- pick_pair(dat, stratum, a, b, dir = dir)
    # 分层 PERMANOVA 用同样的 stratum/group1/group2；有 direction 列则同向筛
    pr <- pick_pair(perm, stratum, a, b, dir = dir)
    rows[[length(rows) + 1]] <<- data.frame(
      grp = stratum,
      contrast = paste(a, b, sep = " / "),
      R  = pd_fmt_num(if (!is.null(ar)) ar$R else NA_real_, cfg = cfg),
      pA = pd_fmt_p(if (!is.null(ar)) ar$p else NA_real_, stars = FALSE, cfg = cfg),
      F  = pd_fmt_num(if (!is.null(pr)) pr$F else NA_real_, cfg = cfg),
      R2 = pd_fmt_num(if (!is.null(pr)) pr$R2 else NA_real_, cfg = cfg),
      pP = pd_fmt_p(if (!is.null(pr)) pr$p else NA_real_, stars = FALSE, cfg = cfg),
      stringsAsFactors = FALSE)
  }
  # 上半：在 f1（生境）每个水平内比 f2（季节）—— 用 d1
  for (s in as.character(f1_lv))
    for (i in seq_len(ncol(cmb_f2)))
      push(d1, "within_f1_compare_f2", s, cmb_f2[1, i], cmb_f2[2, i])
  # 下半：在 f2（季节）每个水平内比 f1（生境）—— 用 d2
  for (s in as.character(f2_lv))
    for (i in seq_len(ncol(cmb_f1)))
      push(d2, "within_f2_compare_f1", s, cmb_f1[1, i], cmb_f1[2, i])
  body <- do.call(rbind, rows)

  # 首列只在分组首行写名字（供 merge_v 合并）
  g <- body$grp
  newg <- c(TRUE, g[-1] != g[-length(g)])
  body$grp[!newg] <- ""
  names(body) <- c("", "", "R", "p", "F", "R2", "p")

  if (!pd_has("flextable")) return(NULL)
  keys <- paste0("c", seq_len(ncol(body)))
  names(body) <- keys
  ft <- flextable::flextable(body)
  ft <- flextable::set_header_labels(ft, values = stats::setNames(
    as.list(c("", "", "R", "p", "F", "R2", "p")), keys))
  ft <- flextable::add_header_row(ft, top = TRUE,
                                  values = c("", "ANOSIM", "PERMANOVA"),
                                  colwidths = c(2, 2, 3))
  ft <- flextable::merge_v(ft, j = 1)
  ft <- pd_three_line(ft, cfg = cfg)
  ft <- flextable::align(ft, j = 1, align = "left", part = "body")
  ft <- flextable::width(ft, width = c(1.1, 1.5, 0.7, 1.0, 0.8, 0.7, 1.0))
  ft
}

#' T2 · PERMANOVA 主效应（正文 Table 2）
#'   permanova: term, R2, F, p
pd_table_t2 <- function(permanova, cfg = .pd$cfg) {
  if (is.null(permanova) || !nrow(permanova)) { pd_warn("T2 跳过：缺 permanova"); return(NULL) }
  fac <- pd_design_factors(cfg, source = "table")
  f1 <- fac[1]; f2 <- if (length(fac) > 1) fac[2] else NA   # 单因素时 f2=NA → idx 自动只剩 f1+Residual
  trm <- trimws(as.character(permanova$term))
  # 论文行序：Season(=f2) / Habitat(=f1) / 交互 / Residual
  #   ★ 交互项名是 R 的 `:` 形式（Habitat:Season），不是 `*` —— 见 pitfalls H10
  idx <- c(match(f2, trm), match(f1, trm),
           grep("[*:]", trm)[1],
           grep("^Residual", trm, ignore.case = TRUE)[1])
  idx <- idx[!is.na(idx)]
  if (!length(idx)) { pd_warn("T2 跳过：permanova 的 term 与 config$table$factors 对不上"); return(NULL) }
  d <- permanova[idx, , drop = FALSE]

  rn <- trimws(as.character(d$term))
  rn[grepl("^Residual", rn, ignore.case = TRUE)] <- "Residual"
  is_res <- rn == "Residual"
  # 交互项：R 内部形 `Habitat:Season` → 论文显示形 `Season * Habitat`（按 f2, f1 顺序）
  is_inter <- !is_res & grepl("[:*]", rn)
  if (any(is_inter)) rn[is_inter] <- paste(f2, "*", f1)

  body <- data.frame(
    term = rn,
    R2 = pd_fmt_num(d$R2, cfg = cfg),
    # 论文 T2 的 F 是 2 位（31.04），T1/T3 的 F 是 3 位 —— 按论文分别保留
    F  = ifelse(is_res, "-", pd_fmt_num(d$F, digits = cfg$table$digits$f %||% 2, cfg = cfg)),
    P  = ifelse(is_res, "-", pd_fmt_p(d$p, stars = FALSE, cfg = cfg)),
    stringsAsFactors = FALSE)
  pd_as_table(body, labels = c("", "R2", "F", "P"), cfg = cfg)
}

#' T3 · 双因素 ANOVA F、p（正文 Table 3）
#'   summary: variable, term, df, SS, F, p, sig, eta2
pd_table_t3 <- function(summary_df, cfg = .pd$cfg) {
  if (is.null(summary_df) || !nrow(summary_df)) { pd_warn("T3 跳过：缺 12_* summary"); return(NULL) }
  vt <- pd_table_vars(cfg, unique(as.character(summary_df$variable)))
  vars <- vt$act; vars_disp <- vt$disp          # act=结果表列名，disp=论文显示名
  if (!length(vars)) { pd_warn("T3 跳过：table$vars 都取不到值"); return(NULL) }
  # ★ 12 的 pd_run_tests 默认只测 cfg$response$alpha（Shannon/Pielou/S），
  #   func/phylo 组不在 summary 里 → 这些列会全 "-"。给出可操作提示。
  miss <- vars_disp[!(vars %in% unique(as.character(summary_df$variable)))]
  if (length(miss))
    pd_warn("T3 的 ", paste(miss, collapse = ", "),
            " 在 12_*:summary 里没有 —— 请先用 vars = config$table$vars 跑 pd_run_tests() 再出表")
  fac <- pd_design_factors(cfg, source = "table")
  f1 <- fac[1]
  f2 <- if (length(fac) > 1) fac[2] else NA
  # 行序：双因素 = f2 / f1 / f2*f1；单因素 = 只有 f1（无交互行）
  row_terms <- if (is.na(f2)) c(f1) else c(f2, f1, paste(f2, "*", f1))

  pick <- function(var, term) {
    hit <- summary_df[summary_df$variable == var & as.character(summary_df$term) == term, , drop = FALSE]
    if (!nrow(hit)) return(c(NA_real_, NA_real_))
    c(hit$F[1], hit$p[1])
  }
  inter_terms <- if (is.na(f2)) character(0) else
    c(paste(f2, "*", f1), paste(f1, "*", f2),          # 显示名形
      paste(f2, ":", f1), paste(f1, ":", f2),          # ★ R 的 aov/adonis2 实际形（Habitat:Season）
      paste(f2, f1, sep = ":"), paste(f1, f2, sep = ":"))

  cols <- list()
  for (v in vars) {
    Fv <- numeric(0); pv <- numeric(0)
    for (t in row_terms) {
      r <- c(NA_real_, NA_real_)
      if (grepl("\\*", t)) {
        for (it in inter_terms) { r <- pick(v, it); if (!anyNA(r)) break }
      } else r <- pick(v, t)
      Fv <- c(Fv, r[1]); pv <- c(pv, r[2])
    }
    cols[[length(cols) + 1]] <- pd_fmt_num(Fv, cfg = cfg)
    cols[[length(cols) + 1]] <- pd_fmt_p(pv, stars = TRUE, cfg = cfg)
  }
  vars <- vars_disp                              # 表头用论文显示名
  body <- data.frame(term = row_terms, stringsAsFactors = FALSE)
  for (i in seq_along(cols)) body[[paste0("c", i)]] <- cols[[i]]

  if (!pd_has("flextable")) return(NULL)
  keys <- paste0("c", seq_len(ncol(body)))
  names(body) <- keys
  ft <- flextable::flextable(body)
  ft <- flextable::set_header_labels(ft, values = stats::setNames(
    as.list(c("", rep(c("F", "p"), length(vars)))), keys))
  ft <- flextable::add_header_row(ft, top = TRUE,
                                  values = c("", vars),
                                  colwidths = c(1, rep(2, length(vars))))
  ft <- pd_three_line(ft, cfg = cfg)
  ft <- flextable::align(ft, j = 1, align = "left", part = "body")
  ft <- flextable::width(ft, width = c(1.3, rep(c(0.8, 1.0), length(vars))))
  ft
}

#' S1 · 性状 + 谱系信号（附录 Table S1）
#'   sig_long : 32_signal phylo_signal 长表（trait, statistic, value, p, sig）
#'   trait_df : 性状矩阵（物种 × 性状），用来算 Mean value = 列均值
#'   label_map / unit_map 取自 config$table$trait_labels / trait_units
pd_table_s1 <- function(sig_long, trait_df, cfg = .pd$cfg) {
  if (is.null(sig_long) || !nrow(sig_long)) { pd_warn("S1 跳过：缺 phylo_signal"); return(NULL) }
  lab  <- cfg$table$trait_labels %||% list()
  unit <- cfg$table$trait_units  %||% list()

  get_stat <- function(tr, st, col = "value") {
    hit <- sig_long[sig_long$trait == tr & sig_long$statistic == st, , drop = FALSE]
    if (!nrow(hit)) return(NA_real_)
    hit[[col]][1]
  }
  traits <- as.character(unique(sig_long$trait))
  rows <- lapply(traits, function(tr) {
    display <- if (tr %in% names(lab)) as.character(unlist(lab[tr])) else
      gsub("\\s*\\([^)]*\\)\\s*$", "", tr)     # TRY 长名去括号
    u <- if (tr %in% names(unit)) as.character(unlist(unit[[tr]])) else "-"
    if (!length(u) || is.na(u)) u <- "-"
    # Mean value = 性状列均值（口径已实测与论文一致，见 04-paper-tables.md）
    mv <- NA_real_
    if (!is.null(trait_df) && tr %in% names(trait_df)) {
      x <- suppressWarnings(as.numeric(trait_df[[tr]]))
      if (any(!is.na(x))) mv <- mean(x, na.rm = TRUE)
    }
    data.frame(
      trait = display, unit = u,
      mean = pd_fmt_num(mv, cfg = cfg),
      K    = pd_fmt_num(get_stat(tr, "K", "value"), cfg = cfg),
      pK   = pd_fmt_p(get_stat(tr, "K", "p"), stars = TRUE, cfg = cfg),
      lam  = pd_fmt_num(get_stat(tr, "Lambda", "value"), cfg = cfg),
      pLam = pd_fmt_p(get_stat(tr, "Lambda", "p"), stars = TRUE, cfg = cfg),
      stringsAsFactors = FALSE)
  })
  body <- do.call(rbind, rows)
  pd_as_table(body, labels = c("", "Unit", "Mean value", "K", "p.K", "\u03bb", "p.\u03bb"), cfg = cfg)
}

#' S2 · 多样性指数 mean±SD（附录 Table S2）—— 论文无 Tukey 字母，此处也不加
#'   group_means: variable, cell("Season | Habitat"), n, mean, sd, letter, y_max
pd_table_s2 <- function(group_means, cfg = .pd$cfg) {
  if (is.null(group_means) || !nrow(group_means)) { pd_warn("S2 跳过：缺 group_means"); return(NULL) }
  vt <- pd_table_vars(cfg, unique(as.character(group_means$variable)))
  vars <- vt$act; vars_disp <- vt$disp          # act=结果表列名，disp=论文显示名
  if (!length(vars)) { pd_warn("S2 跳过：table$vars 都取不到值"); return(NULL) }
  fac <- pd_design_factors(cfg, source = "table")
  f1 <- fac[1]
  f2 <- if (length(fac) > 1) fac[2] else NA
  single <- is.na(f2)
  f1_lv <- cfg$design$ordered_levels[[f1]] %||%
    if (single) unique(sub("\\s*\\|.*$", "", group_means$cell)) else
      unique(sub("^[^|]*\\|\\s*", "", group_means$cell))
  f2_lv <- if (single) character(0) else
    cfg$design$ordered_levels[[f2]] %||% unique(sub("\\s*\\|.*$", "", group_means$cell))

  # cell 格式：双因素 = "f1_level | f2_level"（12_tests: paste(dd[[f1]], dd[[f2]], sep = " | ")）
  #            单因素 = 只有水平名（12_tests: cellv <- as.character(dd[[f1]])）
  split_cell <- function(cell) {
    parts <- strsplit(as.character(cell), "\\s*\\|\\s*")[[1]]
    if (length(parts) < 2) return(c(parts[1], NA_character_))
    parts[1:2]
  }
  get_ms <- function(var, h, s = NULL) {
    hit <- group_means[group_means$variable == var, , drop = FALSE]
    if (single) {
      j <- which(as.character(hit$cell) == h)
      if (length(j)) return(pd_fmt_mean_sd(hit$mean[j[1]], hit$sd[j[1]], cfg = cfg))
      return("-")
    }
    for (i in seq_len(nrow(hit))) {
      p <- split_cell(hit$cell[i])
      if ((p[1] == h && p[2] == s) || (p[1] == s && p[2] == h))
        return(pd_fmt_mean_sd(hit$mean[i], hit$sd[i], cfg = cfg))
    }
    "-"
  }

  rows <- list()
  if (single) {
    for (h in as.character(f1_lv)) {
      r <- data.frame(grp = h, stringsAsFactors = FALSE)
      for (v in vars) r[[v]] <- get_ms(v, h)
      rows[[length(rows) + 1]] <- r
    }
  } else {
    for (h in as.character(f1_lv)) for (s in as.character(f2_lv)) {
      r <- data.frame(grp = h, season = s, stringsAsFactors = FALSE)
      for (v in vars) r[[v]] <- get_ms(v, h, s)
      rows[[length(rows) + 1]] <- r
    }
  }
  body <- do.call(rbind, rows)
  if (!single) {                       # 首列只在分组首行写名字（供 merge_v 合并）
    g <- body$grp
    newg <- c(TRUE, g[-1] != g[-length(g)])
    body$grp[!newg] <- ""
  }

  if (!pd_has("flextable")) return(NULL)
  hdr <- if (single) c("", vars_disp) else c("", f2, vars_disp)
  keys <- paste0("c", seq_len(ncol(body)))
  names(body) <- keys
  ft <- flextable::flextable(body)
  ft <- flextable::set_header_labels(ft, values = stats::setNames(as.list(hdr), keys))
  if (!single) ft <- flextable::merge_v(ft, j = 1)
  ft <- pd_three_line(ft, cfg = cfg)
  ft <- flextable::align(ft, j = 1, align = "left", part = "body")
  ft
}

# ------------------------------------------------------------
# 70.4 读 results/*.xlsx 的某个 sheet（只读，不写、不重算）
# ------------------------------------------------------------
pd_read_result_sheet <- function(module, stem, sheet, cfg = .pd$cfg) {
  pth <- file.path(cfg$paths$results, sprintf("%s_%s.xlsx", module, stem))
  if (!file.exists(pth)) {
    pd_warn("T 表缺源：", basename(pth), "（先跑模块 ", module, "）")
    return(NULL)
  }
  if (!pd_has("readxl")) { pd_warn("需要 readxl 才能读 xlsx: ", basename(pth)); return(NULL) }
  d <- tryCatch(as.data.frame(readxl::read_excel(pth, sheet = sheet)),
                error = function(e) { pd_warn("读 sheet '", sheet, "' 失败: ", basename(pth)); NULL })
  d
}

# 性状矩阵（S1 的 Mean value 来源）：优先 results/20_traits_used.csv，回退 config$files$traits
pd_read_trait_matrix <- function(cfg = .pd$cfg) {
  p1 <- file.path(cfg$paths$results, "20_traits_used.csv")
  p2 <- cfg$files$traits
  p <- if (!is.na(p1) && file.exists(p1)) p1 else p2
  if (is.null(p) || is.na(p) || !file.exists(p)) { pd_warn("S1 Mean value 缺性状矩阵"); return(NULL) }
  pd_read_table(p)
}

# ------------------------------------------------------------
# 70.3b 第二批 builder（Diversity 2023 Table 1 / 3 / 4）
#   只补 skill 缺的表；格式与 T1/T2/T3/S1/S2 一致（Times 8pt 三线表 + lt001）
# ------------------------------------------------------------

#' t4 · 优势种重要值（← Diversity Table 1）
#'   ab: 样方 × 物种 重要值/多度矩阵（dat$abundance）；mt: 样方元数据（dat$meta）
#'   分组列 = config$table$t4_group（默认 "Season"）；入选阈值 = config$table$iv_threshold（%）
#'   口径：每组的种 IV = 该组样方该种的均值，再按组内合计归一成 %；
#'         入选 = 全数据平均 IV(%) > iv_threshold。见 04-paper-tables.md
pd_table_t4 <- function(ab, mt, cfg = .pd$cfg) {
  if (is.null(ab) || is.null(mt) || !nrow(ab)) { pd_warn("t4 跳过：缺多度/元数据"); return(NULL) }
  id <- cfg$key$sample_id %||% "sample_id"
  gcol <- cfg$table$t4_group %||% "Season"
  if (!(gcol %in% names(mt))) { pd_warn("t4 跳过：meta 缺分组列 ", gcol); return(NULL) }
  # 样方对齐
  common <- intersect(rownames(ab), as.character(mt[[id]]))
  if (!length(common)) { pd_warn("t4 跳过：多度行名与 meta 的 ", id, " 对不上"); return(NULL) }
  ab <- ab[common, , drop = FALSE]
  mt <- mt[match(common, as.character(mt[[id]])), , drop = FALSE]

  g <- as.character(mt[[gcol]])
  g_lv <- cfg$design$ordered_levels[[gcol]] %||% unique(g[!is.na(g)])
  g_lv <- as.character(g_lv)
  thr <- cfg$table$iv_threshold %||% 1

  # 每组的种 IV 均值 → 归一成 %
  iv_pct <- sapply(g_lv, function(s) {
    idx <- which(g == s)
    if (!length(idx)) return(rep(NA_real_, ncol(ab)))
    colMeans(ab[idx, , drop = FALSE], na.rm = TRUE)
  })
  if (is.null(dim(iv_pct))) iv_pct <- matrix(iv_pct, ncol = 1,
                                             dimnames = list(colnames(ab), g_lv))
  iv_pct <- t(t(iv_pct) / colSums(iv_pct, na.rm = TRUE)) * 100

  # 入选：全数据平均 IV% > 阈值（论文口径同）
  overall <- rowMeans(iv_pct, na.rm = TRUE)
  keep <- which(!is.na(overall) & overall > thr)
  if (!length(keep)) { pd_warn("t4 跳过：无物种 IV 超过阈值 ", thr, "%"); return(NULL) }
  keep <- keep[order(-overall[keep])]

  # Family 列（缺则 "-"，不发明）
  fam <- rep("-", length(keep))
  sp_f <- pd_read_table(cfg$files$species)
  if (!is.null(sp_f) && "species" %in% names(sp_f) && "family" %in% names(sp_f)) {
    j <- match(colnames(ab)[keep], as.character(sp_f$species))
    if (any(!is.na(j))) fam[!is.na(j)] <- as.character(sp_f$family)[j[!is.na(j)]]
  }

  body <- data.frame(
    species = colnames(ab)[keep],
    family  = fam,
    stringsAsFactors = FALSE)
  for (s in g_lv) body[[s]] <- ifelse(is.na(iv_pct[keep, s]), "-",
                                      sprintf("%.2f%%", iv_pct[keep, s]))

  if (!pd_has("flextable")) return(NULL)
  keys <- paste0("c", seq_len(ncol(body)))
  names(body) <- keys
  ft <- flextable::flextable(body)
  ft <- flextable::set_header_labels(ft, values = stats::setNames(
    as.list(c("Species", "Family", g_lv)), keys))
  ft <- flextable::add_header_row(ft, top = TRUE,
                                  values = c("", "Importance Values"),
                                  colwidths = c(2, length(g_lv)))
  ft <- pd_three_line(ft, cfg = cfg)
  ft <- flextable::align(ft, j = c(1, 2), align = "left", part = "body")
  ft
}

#' t5 · Spearman 相关 p 矩阵（← Diversity Table 3）—— 对角留空，p + 星号
pd_table_t5 <- function(pmat, cfg = .pd$cfg) {
  if (is.null(pmat) || !nrow(pmat)) { pd_warn("t5 跳过：缺 52 的 p_matrix"); return(NULL) }
  vt <- pd_table_vars(cfg, colnames(pmat))
  vars <- vt$act; vars_disp <- vt$disp
  if (!length(vars)) { vars <- colnames(pmat); vars_disp <- vars }
  keep <- vars %in% colnames(pmat)
  vars <- vars[keep]; vars_disp <- vars_disp[keep]
  if (length(vars) < 2) { vars <- colnames(pmat); vars_disp <- vars }
  p <- as.matrix(pmat[vars, vars, drop = FALSE])

  body <- data.frame(matrix("", nrow = length(vars), ncol = length(vars) + 1),
                     stringsAsFactors = FALSE)
  names(body) <- c("var", vars)
  body$var <- vars_disp                       # 行名列用论文显示名
  for (i in seq_along(vars)) for (j in seq_along(vars)) {
    if (i == j) next                        # 对角留空（论文口径）
    body[i, vars[j]] <- pd_fmt_p(p[i, j], stars = TRUE, cfg = cfg)
  }
  pd_as_table(body, labels = c("", vars_disp), cfg = cfg)
}

#' t6 · 环境因子解释力（← Diversity Table 4，无土层分组 → 5 列）
#'   envfit_tab: 42 的 envfit 表（env, r, R2, p, sig）；env_df: 环境表（算 M±SD）
pd_table_t6 <- function(envfit_tab, env_df, cfg = .pd$cfg) {
  if (is.null(envfit_tab) || !nrow(envfit_tab)) { pd_warn("t6 跳过：缺 42 的 envfit"); return(NULL) }
  unit <- cfg$table$env_units %||% list()
  rows <- lapply(seq_len(nrow(envfit_tab)), function(i) {
    e <- as.character(envfit_tab$env[i])
    u <- if (e %in% names(unit)) as.character(unlist(unit[[e]])) else "-"
    if (!length(u) || is.na(u)) u <- "-"
    mv <- sd <- NA_real_
    if (!is.null(env_df) && e %in% names(env_df)) {
      x <- suppressWarnings(as.numeric(env_df[[e]]))
      if (any(!is.na(x))) { mv <- mean(x, na.rm = TRUE); sd <- stats::sd(x, na.rm = TRUE) }
    }
    data.frame(
      env = e, unit = u,
      msd = pd_fmt_mean_sd(mv, sd, d = 2, cfg = cfg),
      R2  = pd_fmt_num(envfit_tab$R2[i], cfg = cfg),
      p   = pd_fmt_p(envfit_tab$p[i], stars = TRUE, cfg = cfg),
      stringsAsFactors = FALSE)
  })
  body <- do.call(rbind, rows)
  pd_as_table(body, labels = c("Env Factor", "Unit", "M ± SD", "R²", "p"), cfg = cfg)
}

#' t7 · RDA Monte-Carlo 置换（← 硕士论文表 7-1）
#'   列：Env Factor / RDA1 / RDA2 / R² / p
#'   RDA1/RDA2 = summary(mod)$biplot 方向余弦（单位长度，RDA1²+RDA2²=1），5 位小数
#'   R²        = envfit r²，4 位小数
#'   p         = envfit 置换 p（走 pd_fmt_p("lt001")，出 <0.001 ***）
#'   envfit_tab 必须含 RDA1/RDA2 列（42_rda 已写入 results/42_rda.xlsx:envfit）
pd_table_t7 <- function(envfit_tab, cfg = .pd$cfg) {
  if (is.null(envfit_tab) || !nrow(envfit_tab)) { pd_warn("t7 跳过：缺 42 的 envfit"); return(NULL) }
  need <- c("env", "RDA1", "RDA2", "R2", "p")
  miss <- setdiff(need, names(envfit_tab))
  if (length(miss)) {
    pd_warn("t7 跳过：envfit 表缺列 ", paste(miss, collapse = ", "),
            "（需重跑 42 以写入 RDA1/RDA2）")
    return(NULL)
  }
  body <- data.frame(
    env  = as.character(envfit_tab$env),
    RDA1 = pd_fmt_num(envfit_tab$RDA1, digits = 5, cfg = cfg),   # ★ 论文 -0.07964（5 位）
    RDA2 = pd_fmt_num(envfit_tab$RDA2, digits = 5, cfg = cfg),
    R2   = pd_fmt_num(envfit_tab$R2,   digits = 4, cfg = cfg),   # ★ 论文 0.5795（4 位）
    p    = pd_fmt_p(envfit_tab$p, stars = TRUE, cfg = cfg),
    stringsAsFactors = FALSE)
  # ★★ 轴名要跟着模型走（2026-09-25）：DCA 梯度 >4 时走的是 CCA，列名不能还写 RDA1/RDA2。
  #   从 42_rda.xlsx:run_info 读「选用方法」；读不到就默认 RDA（旧口径）。
  ax <- "RDA"
  ri <- tryCatch(pd_read_result_sheet("42", "rda", "run_info", cfg), error = function(e) NULL)
  if (!is.null(ri) && all(c("item", "value") %in% names(ri))) {
    j <- which(ri$item == "选用方法")
    if (length(j) && identical(tolower(as.character(ri$value[j[1]])), "cca")) ax <- "CCA"
  }
  if (identical(ax, "CCA"))
    pd_msg("[t7] 本次约束排序是 CCA（DCA 梯度 > 4）→ 轴列名用 CCA1/CCA2")
  pd_as_table(body, labels = c("Env Factor", paste0(ax, 1), paste0(ax, 2), "R²", "p"), cfg = cfg)
}

# ------------------------------------------------------------
# 70.3b 三个版式补充表（2026-09-25，吸收 Plant and Soil 投稿版 S1–S6）
#   t8 = 时间 × 分组 mean±SD（论文 S3–S6 版式，多指标纵向堆叠）
#   s3 = 并排双栏基线描述（论文 S1）
#   s4 = 物种名录 Latin name/Genus/Family/Order（论文 S2）
#   ★ 三个都是【纯版式】，不改任何统计口径、不动现有 9 张表
#   ★ 时间维用 design$time（Season），不搬论文的 Month —— 例子统一 Season/Habitat
# ------------------------------------------------------------

#' T8 · 「时间 × 分组」mean±SD 表（对应论文 S3–S6 版式）
#'   行 = 时间维水平（cfg$design$time，缺则 factors[2]）
#'   列 = 另一因子的水平
#'   多个指标纵向堆叠，指标名只写首行（同 pd_table_s2 的 merge_v 思路）
#'   数值与 s2 同源：results/12_<method>.xlsx:group_means —— 只重排，不重算
#'   gm 必含列：variable / cell / mean / sd（cell = "f1_level | f2_level"）
pd_table_t8 <- function(group_means, cfg = .pd$cfg) {
  if (is.null(group_means) || !nrow(group_means)) { pd_warn("t8 跳过：缺 group_means"); return(NULL) }
  need <- c("variable", "cell", "mean", "sd")
  miss <- setdiff(need, names(group_means))
  if (length(miss)) { pd_warn("t8 跳过：group_means 缺列 ", paste(miss, collapse = ", ")); return(NULL) }

  fac <- pd_design_factors(cfg, source = "table")
  if (length(fac) < 2) {
    pd_warn("t8 跳过：需双因素（行=时间、列=分组）；单因素设计请改用 s2")
    return(NULL)
  }
  f1 <- fac[1]; f2 <- fac[2]
  # 行 = 时间维；design$time 优先，缺/不在因子集里则退 factors[2]
  row_var <- cfg$design$time %||% f2
  if (!row_var %in% fac) row_var <- f2
  col_var <- setdiff(fac, row_var)[1]

  sp <- strsplit(as.character(group_means$cell), "\\s*\\|\\s*")
  if (!all(lengths(sp) >= 2)) {
    pd_warn("t8 跳过：cell 不是 \"f1 | f2\" 格式（与 12_tests 的 cell 口径不符）")
    return(NULL)
  }
  gm <- group_means
  gm$lv1 <- vapply(sp, `[`, character(1), 1)     # f1 水平
  gm$lv2 <- vapply(sp, `[`, character(1), 2)     # f2 水平
  gm$row_lv <- if (identical(row_var, f1)) gm$lv1 else gm$lv2
  gm$col_lv <- if (identical(col_var, f1)) gm$lv1 else gm$lv2

  row_lv <- cfg$design$ordered_levels[[row_var]] %||% unique(as.character(gm$row_lv))
  col_lv <- cfg$design$ordered_levels[[col_var]] %||% unique(as.character(gm$col_lv))
  row_lv <- as.character(row_lv); col_lv <- as.character(col_lv)

  # 要堆叠哪几个指标（table$t8_vars）→ 解析到 gm$variable 的实际名
  vars_want <- cfg$table$t8_vars %||% character(0)
  if (!length(vars_want)) { pd_warn("t8 跳过：table$t8_vars 为空"); return(NULL) }
  have <- unique(as.character(gm$variable))
  vars_act <- vapply(vars_want, function(v) {
    if (v %in% have) return(v)
    alt <- tryCatch(pd_match_var(v, have), error = function(e) "")
    if (is.null(alt) || !nzchar(alt[1])) NA_character_ else alt[1]
  }, character(1), USE.NAMES = FALSE)
  keep <- !is.na(vars_act)
  if (!any(keep)) {
    pd_warn("t8 跳过：t8_vars 都不在 group_means 里（", paste(vars_want, collapse = ", "),
            "；group_means 有 ", paste(have, collapse = ", "), "）")
    return(NULL)
  }
  vars_want <- vars_want[keep]; vars_act <- vars_act[keep]

  get_ms <- function(var, r, cc) {
    hit <- gm[gm$variable == var & gm$row_lv == r & gm$col_lv == cc, , drop = FALSE]
    if (!nrow(hit)) return("-")
    pd_fmt_mean_sd(hit$mean[1], hit$sd[1], cfg = cfg)
  }

  rows <- list()
  for (i in seq_along(vars_act)) {
    first <- TRUE
    for (r in row_lv) {
      rr <- data.frame(ind = if (first) vars_want[i] else "",
                       tm  = r, stringsAsFactors = FALSE)
      for (cc in col_lv) rr[[cc]] <- get_ms(vars_act[i], r, cc)
      rows[[length(rows) + 1]] <- rr
      first <- FALSE
    }
  }
  body <- do.call(rbind, rows)
  names(body) <- c("ind", row_var, col_lv)

  if (!pd_has("flextable")) return(NULL)
  keys <- paste0("c", seq_len(ncol(body)))
  names(body) <- keys
  hdr <- c("Indicator", row_var, col_lv)
  ft <- flextable::flextable(body)
  ft <- flextable::set_header_labels(ft, values = stats::setNames(as.list(hdr), keys))
  ft <- flextable::merge_v(ft, j = 1)          # 指标名只写首行
  ft <- pd_three_line(ft, cfg = cfg)
  ft <- flextable::align(ft, j = 1, align = "left", part = "body")
  ft
}

#' S3 · 并排双栏基线描述表（对应论文 S1）
#'   base 长表：indicator / unit / value（value 已是 "mean±SD" 字符串）
#'   拆成左右两栏并排省版面；unit 为空或 "-" 时指标名不带括号
pd_table_s3 <- function(base, cfg = .pd$cfg) {
  if (is.null(base) || !nrow(base)) { pd_warn("s3 跳过：缺基线描述统计"); return(NULL) }
  need <- c("indicator", "value")
  miss <- setdiff(need, names(base))
  if (length(miss)) { pd_warn("s3 跳过：缺列 ", paste(miss, collapse = ", ")); return(NULL) }

  lab <- if ("unit" %in% names(base)) {
    u <- as.character(base$unit)
    ifelse(is.na(u) | !nzchar(u) | u == "-", as.character(base$indicator),
           paste0(base$indicator, " (", u, ")"))
  } else as.character(base$indicator)

  n <- length(lab); half <- ceiling(n / 2)
  left <- seq_len(half)
  right <- if (n > half) seq(half + 1, n) else integer(0)

  body <- data.frame(i1 = lab[left], v1 = as.character(base$value[left]),
                     stringsAsFactors = FALSE)
  if (length(right)) {
    i2 <- lab[right]; v2 <- as.character(base$value[right])
    pad <- length(left) - length(right)
    if (pad > 0) { i2 <- c(i2, rep("", pad)); v2 <- c(v2, rep("", pad)) }
    body$i2 <- i2; body$v2 <- v2
  }
  hdr <- c("Indicators (Unit)", "Values", "Indicators (Unit)", "Values")
  pd_as_table(body, labels = hdr[seq_len(ncol(body))], cfg = cfg)
}

#' S4 · 物种名录表（对应论文 S2）：Latin name / Genus / Family / Order
#'   sp_list = cfg$files$species 的表，需含 species 列；genus/family/order 缺则优雅降级
#'   ★ Order 缺失就【整列省略】—— 不造数（见 00-data-contract.md）
pd_table_s4 <- function(sp_list, cfg = .pd$cfg) {
  if (is.null(sp_list) || !nrow(sp_list)) { pd_warn("s4 跳过：缺物种名录 cfg$files$species"); return(NULL) }
  nm <- tolower(names(sp_list))
  pick <- function(want) {
    i <- match(want, nm)
    if (is.na(i)) i <- grep(paste0("^", want, "$"), nm)[1]
    if (is.na(i)) NA_integer_ else i
  }
  i_sp <- pick("species"); i_gn <- pick("genus"); i_fm <- pick("family"); i_od <- pick("order")
  if (is.na(i_sp)) {
    pd_warn("s4 跳过：物种名录缺 species 列（实际列：", paste(names(sp_list), collapse = ", "), "）")
    return(NULL)
  }
  body <- data.frame(
    v1 = as.character(sp_list[[i_sp]]),
    v2 = if (!is.na(i_gn)) as.character(sp_list[[i_gn]]) else "-",
    v3 = if (!is.na(i_fm)) as.character(sp_list[[i_fm]]) else "-",
    stringsAsFactors = FALSE)
  labs <- c("Latin name", "Genus", "Family")
  if (!is.na(i_od)) {
    body$v4 <- as.character(sp_list[[i_od]])
    labs <- c(labs, "Order")
  } else {
    pd_msg("[s4] 物种名录无 Order 列 → 该列省略（要出 Order 请在 ", cfg$files$species %||% "species_list", " 里加 order 列）")
  }
  pd_as_table(body, labels = labs, cfg = cfg)
}

#' s3 的数据准备：全部样地合并的 mean±SD（不分组，不重算统计量之外的东西）
#'   响应变量 ← dat$meta；环境变量 ← cfg$files$env
#'   指标集 = table$s3_vars，缺省 = response 全组 + opts$env
#'   缺列就跳过该指标 —— 不造数
pd_baseline_stats <- function(dat, cfg = .pd$cfg) {
  if (is.null(dat) || is.null(dat$meta)) return(NULL)
  mt  <- dat$meta
  env <- tryCatch(pd_read_table(cfg$files$env), error = function(e) NULL)
  want <- cfg$table$s3_vars %||% unique(c(
    unlist(cfg$response[c("alpha", "func", "phylo", "community")]),
    cfg$opts$env))
  want <- want[!is.na(want) & nzchar(want)]
  cu <- cfg$table$community_units %||% list()
  eu <- cfg$table$env_units        %||% list()

  out <- list()
  for (v in want) {
    src <- NULL
    if (v %in% names(mt)) src <- mt[[v]]
    else if (!is.null(env) && v %in% names(env)) src <- env[[v]]
    else {
      hit <- tryCatch(pd_match_var(v, names(mt)), error = function(e) "")
      if (!is.null(hit) && nzchar(hit[1]) && hit[1] %in% names(mt)) src <- mt[[hit[1]]]
      else if (!is.null(env)) {
        hit2 <- tryCatch(pd_match_var(v, names(env)), error = function(e) "")
        if (!is.null(hit2) && nzchar(hit2[1]) && hit2[1] %in% names(env)) src <- env[[hit2[1]]]
      }
    }
    if (is.null(src)) { pd_msg("[s3] 指标 ", v, " 未在 meta/env 找到，跳过"); next }
    src <- suppressWarnings(as.numeric(src))
    if (!any(is.finite(src))) { pd_msg("[s3] 指标 ", v, " 无有效数值，跳过"); next }
    uu <- cu[[v]] %||% eu[[v]] %||% "-"
    out[[length(out) + 1L]] <- data.frame(
      indicator = v, unit = uu,
      value = pd_fmt_mean_sd(mean(src, na.rm = TRUE), stats::sd(src, na.rm = TRUE), cfg = cfg),
      stringsAsFactors = FALSE)
  }
  if (!length(out)) { pd_warn("s3 跳过：一个指标都没取到数"); return(NULL) }
  do.call(rbind, out)
}


pd_tables_docx <- function(tables, cfg = .pd$cfg) {
  if (!pd_has("officer") || !pd_has("flextable")) {
    pd_warn("需要 flextable + officer 才能写 tables.docx；安装: install.packages(c(\"flextable\",\"officer\"))")
    return(invisible(NULL))
  }
  tabs <- tables[!vapply(tables, is.null, logical(1))]
  if (!length(tabs)) { pd_warn("没有可写的论文表，tables.docx 未生成"); return(invisible(NULL)) }

  font <- cfg$table$font %||% "Times New Roman"
  size_pt <- cfg$table$size_pt %||% 8
  # ★ 序号改单一序列（用户：两论文表格并成一套，不要 S 系列）
  #   编号按 tabs 的实际顺序生成 → 想重排只改 pd_run_paper_tables 的 which 顺序
  labels <- stats::setNames(paste0("Table ", seq_along(tabs)), names(tabs))
  caps <- cfg$table$captions %||% list()
  fots <- cfg$table$footnotes %||% list()

  doc <- officer::read_docx()
  for (nm in names(tabs)) {
    doc <- officer::body_add_par(doc, value = labels[[nm]] %||% toupper(nm), style = "Normal")
    doc <- officer::body_add_par(doc, value = caps[[nm]] %||% "", style = "Normal")
    doc <- flextable::body_add_flextable(doc, value = tabs[[nm]])
    ft_note <- fots[[nm]]
    if (!is.null(ft_note) && nzchar(ft_note))
      doc <- officer::body_add_par(doc, value = ft_note, style = "Normal")
    if (nm != names(tabs)[length(tabs)]) doc <- officer::body_add_break(doc)
  }

  # 全文字体
  doc <- officer::body_end_section_continuous(doc)

  outdir <- file.path(cfg$paths$root %||% ".", cfg$table$dir %||% "tables")
  if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)
  target <- file.path(outdir, cfg$table$file %||% "tables.docx")
  if (file.exists(target)) {                    # 不静默覆盖（pitfalls D2 / file-safety）
    bak <- sub("\\.docx$", paste0("_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".bak.docx"), target)
    file.copy(target, bak, overwrite = TRUE)
    pd_msg("[tab] 同名 tables.docx 已备份为 ", basename(bak))
  }
  tmp <- file.path(tempdir(), paste0("pd_tables_", format(Sys.time(), "%H%M%S"), ".docx"))
  print(doc, target = tmp)
  ok <- file.copy(tmp, target, overwrite = TRUE)
  if (!ok) { pd_warn("写入 tables.docx 失败: ", target); return(invisible(NULL)) }
  pd_msg("[tab] ", target, "  （", length(tabs), " 张表）")
  invisible(target)
}

# ------------------------------------------------------------
# 70.6 主入口
#   which: c("t1","t2","t3","s1","s2") 子集可选
#   数据全部从 results/*.xlsx 读 → 与缓存 / FIGURE_ONLY 完全解耦
# ------------------------------------------------------------
pd_run_paper_tables <- function(cfg = .pd$cfg,
                                which = NULL,
                                dat = NULL, save = TRUE) {
  # ★ 出哪些三线表必须提前和用户沟通，【不要默认全出】（用户 2026-09-25）
  #   优先级：调用时传 which > config$table$which > 全部 12 张（兜底）
  #   兜底只为演示/回归能跑；写新论文时 table$which 由用户勾选后填（SKILL.md 第 3 步）
  which <- which %||% cfg$table$which %||%
    c("t1", "t2", "t3", "s1", "s2", "t4", "t5", "t6", "t7", "t8", "s3", "s4")
  if (is.null(cfg$table$which) && is.null(match.call()$which))
    pd_msg("[tab] 提示：table$which 未填 → 全部 ", length(which),
           " 张都出。写新论文请先和用户确认要哪几张（SKILL.md 第 3 步）")
  if (!pd_require(c("flextable", "officer", "readxl"), "70_paper_tables")) return(invisible(NULL))
  pd_msg("")
  pd_msg("### 70 论文表格 tables.docx ###")

  out <- list()

  # ---- T1：两两 ANOSIM + 分层两两 PERMANOVA ----
  if ("t1" %in% which) {
    ano <- pd_read_result_sheet("40", "ordination", "pairwise_anosim", cfg)
    perm <- pd_read_result_sheet("40", "ordination", "pairwise_permanova_strat", cfg)
    if (is.null(perm))      # 回退：无分层版就用 combo 版（会缺行，见 04-paper-tables 问题1）
      perm <- pd_read_result_sheet("40", "ordination", "pairwise_permanova", cfg)
    out$t1 <- tryCatch(pd_table_t1(ano, perm, cfg), error = function(e) {
      pd_warn("T1 构建失败: ", conditionMessage(e)); NULL })
  }

  # ---- T2：PERMANOVA 主效应 ----
  if ("t2" %in% which) {
    pm <- pd_read_result_sheet("40", "ordination", "permanova", cfg)
    out$t2 <- tryCatch(pd_table_t2(pm, cfg), error = function(e) {
      pd_warn("T2 构建失败: ", conditionMessage(e)); NULL })
  }

  # ---- T3：双因素 ANOVA ----
  if ("t3" %in% which) {
    # 12 的结果表名带 method 后缀（12_anova_tukey.xlsx / 12_kruskal_dunn.xlsx …）
    sm <- pd_read_result_sheet("12", cfg$opts$alpha_test %||% "anova_tukey", "summary", cfg)
    out$t3 <- tryCatch(pd_table_t3(sm, cfg), error = function(e) {
      pd_warn("T3 构建失败: ", conditionMessage(e)); NULL })
  }

  # ---- S1：性状 + 谱系信号 ----
  if ("s1" %in% which) {
    sig <- pd_read_result_sheet("32", "signal", "phylo_signal", cfg)
    tr <- pd_read_trait_matrix(cfg)
    out$s1 <- tryCatch(pd_table_s1(sig, tr, cfg), error = function(e) {
      pd_warn("S1 构建失败: ", conditionMessage(e)); NULL })
  }

  # ---- S2：mean±SD ----
  if ("s2" %in% which) {
    gm <- pd_read_result_sheet("12", cfg$opts$alpha_test %||% "anova_tukey", "group_means", cfg)
    out$s2 <- tryCatch(pd_table_s2(gm, cfg), error = function(e) {
      pd_warn("S2 构建失败: ", conditionMessage(e)); NULL })
  }

  # ---- t4：优势种重要值（需 dat$abundance + dat$meta）----
  if ("t4" %in% which) {
    dat <- dat %||% tryCatch(pd_load_data(cfg), error = function(e) NULL)
    out$t4 <- if (is.null(dat)) NULL else
      tryCatch(pd_table_t4(dat$abundance, dat$meta, cfg), error = function(e) {
        pd_warn("t4 构建失败: ", conditionMessage(e)); NULL })
  }

  # ---- t5：Spearman p 矩阵（读 52 的 p_matrix）----
  if ("t5" %in% which) {
    pm <- pd_read_result_sheet("52", "spearman", "p_matrix", cfg)
    if (!is.null(pm)) {
      rn <- pm[[1]]              # 第一列是行名（pd_write_table 塞的 row_id）
      pmat <- as.matrix(pm[, -1, drop = FALSE])
      rownames(pmat) <- as.character(rn)
      storage.mode(pmat) <- "numeric"
      out$t5 <- tryCatch(pd_table_t5(pmat, cfg), error = function(e) {
        pd_warn("t5 构建失败: ", conditionMessage(e)); NULL })
    } else out$t5 <- NULL
  }

  # ---- t6：环境因子解释力（envfit + 环境表 M±SD）----
  if ("t6" %in% which) {
    ef <- pd_read_result_sheet("42", "rda", "envfit", cfg)
    ev <- pd_read_table(cfg$files$env)
    out$t6 <- tryCatch(pd_table_t6(ef, ev, cfg), error = function(e) {
      pd_warn("t6 构建失败: ", conditionMessage(e)); NULL })
  }

  # ---- t7：RDA Monte-Carlo（envfit 的 RDA1/RDA2/R²/p，← 硕士论文表 7-1）----
  if ("t7" %in% which) {
    ef <- pd_read_result_sheet("42", "rda", "envfit", cfg)
    out$t7 <- tryCatch(pd_table_t7(ef, cfg), error = function(e) {
      pd_warn("t7 构建失败: ", conditionMessage(e)); NULL })
  }

  # ---- t8：时间 × 分组 mean±SD（← Plant and Soil S3–S6 版式；与 s2 同源，只重排）----
  if ("t8" %in% which) {
    gm <- pd_read_result_sheet("12", cfg$opts$alpha_test %||% "anova_tukey", "group_means", cfg)
    out$t8 <- tryCatch(pd_table_t8(gm, cfg), error = function(e) {
      pd_warn("t8 构建失败: ", conditionMessage(e)); NULL })
  }

  # ---- s3：并排双栏基线描述（← Plant and Soil S1）----
  if ("s3" %in% which) {
    dat <- dat %||% tryCatch(pd_load_data(cfg), error = function(e) NULL)
    base <- tryCatch(pd_baseline_stats(dat, cfg), error = function(e) {
      pd_warn("s3 数据准备失败: ", conditionMessage(e)); NULL })
    out$s3 <- tryCatch(pd_table_s3(base, cfg), error = function(e) {
      pd_warn("s3 构建失败: ", conditionMessage(e)); NULL })
  }

  # ---- s4：物种名录（← Plant and Soil S2）----
  if ("s4" %in% which) {
    spl <- tryCatch(pd_read_table(cfg$files$species), error = function(e) NULL)
    out$s4 <- tryCatch(pd_table_s4(spl, cfg), error = function(e) {
      pd_warn("s4 构建失败: ", conditionMessage(e)); NULL })
  }

  # 跳过登记
  skipped <- names(out)[vapply(out, is.null, logical(1))]
  if (length(skipped)) pd_msg("[tab] 跳过: ", paste(skipped, collapse = ", "))

  # ★ 输出顺序 = which 顺序（用户可重排）；序号由 pd_tables_docx 按顺序编 Table 1..n
  out <- out[intersect(which, names(out))]

  if (isTRUE(save)) {
    pd_tables_docx(out, cfg)
    # ★ 交付附会话信息（2026-09-25）—— 可复现性
    tryCatch(pd_write_session_info(cfg), error = function(e) NULL)
  }
  invisible(out)
}
