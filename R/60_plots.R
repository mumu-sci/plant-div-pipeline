# ============================================================
# 60_plots.R · 箱线图族 + 统计标注 + 交互效应图 + 拼图 + pdf 导出
# 依赖：ggplot2 ；ggbeeswarm / ggpubr（可选）
# 规格：pt 绝对字号 + 物理尺寸（默认双栏 190mm，见 pitfalls E1）
# 标注科学性：括号里的 p 值必须与主检验同源，绝不对非正态数据默认用 t 检验
# ============================================================

# 60.0 字母标注的纵向偏移量
# 不能用 y_max * 常数：当组合内最大值为负（如 mntd/mpd 的 obs.z）时，
# 乘 1.08 会把字母推向更负、标到箱体下方；y_max≈0 时又会压在数据上。
pd_letter_offset <- function(y, frac = 0.05) {
  r <- diff(range(y, na.rm = TRUE))
  if (!is.finite(r) || r == 0) r <- max(abs(y), na.rm = TRUE)
  if (!is.finite(r) || r == 0) r <- 1
  frac * r
}

# 60.1b 图层分发（图型可选 —— 勾选时问用户，见 SKILL.md 第 3 步）
#   box_type : "box"      = 箱体 + 散点（箱线图；SCI Fig3/4/5 风格）
#              "beeswarm" = 无箱体，只有蜂群点
#              "both"     = 由调用方出两张，这里只出 "box" 那一半
#   points   : "jitter" | "beeswarm" | "none"  —— 箱体内的散点层
#   jitter   : 旧签名参数（TRUE/"point"/"beeswarm"/FALSE）；给了就覆盖 points，向后兼容
pd_box_layers <- function(box_type = NULL, points = NULL, jitter = NULL,
                          fill, border, point_col, cfg = .pd$cfg) {
  box_type <- box_type %||% (cfg$plot$box_type %||% "box")
  if (!is.null(jitter))                     # 旧签名兼容
    points <- if (isTRUE(jitter) || identical(jitter, "point")) "jitter"
              else if (identical(jitter, "beeswarm")) "beeswarm"
              else "none"
  points <- points %||% (cfg$plot$points %||% "jitter")
  out <- list()
  if (identical(box_type, "beeswarm")) {
    # 无箱体，只有蜂群点
    if (pd_has("ggbeeswarm"))
      out <- list(ggbeeswarm::geom_beeswarm(size = 1.5, alpha = 0.7, colour = point_col))
    else
      out <- list(ggplot2::geom_jitter(width = 0.15, size = 1.5, alpha = 0.7, colour = point_col))
    return(out)
  }
  # box_type == "box"（"both" 也先出这一半）
  out <- list(ggplot2::geom_boxplot(width = 0.5, outlier.shape = NA, fill = fill,
                                    colour = border, alpha = 0.7, linewidth = 0.3))
  if (identical(points, "jitter"))
    out <- c(out, list(ggplot2::geom_jitter(width = 0.15, size = 1.5, alpha = 0.7, colour = point_col)))
  else if (identical(points, "beeswarm") && pd_has("ggbeeswarm"))
    out <- c(out, list(ggbeeswarm::geom_beeswarm(size = 1.5, alpha = 0.7, colour = point_col)))
  out
}

# 60.1 单个箱线图
# 仅为对齐论文图外观：Revise 色板（PDF 实测 Fig 3/4/5）
#   箱体统一 #00AFBB + 黑边 + alpha=0.7 + width=0.5；散点统一 #FC4E07 + size=1.5
#   图型走 pd_box_layers（config$plot$box_type / $points）；jitter 形参为旧签名兼容
#   论文 scale_y_continuous(expand=c(0,0)) 会切掉本包在 R 内加的 Tukey 字母，故用 expansion 多留头
pd_boxplot <- function(df, y, x, fill = NULL, letters = NULL,
                       ylab = NULL, xlab = NULL, ylim = NULL, jitter = NULL,
                       palette = NULL, facet = NULL, family = NULL,
                       box_type = NULL, points = NULL) {
  if (!pd_has("ggplot2")) return(NULL)
  cfg <- .pd$cfg
  d <- df
  d[[x]] <- factor(d[[x]])
  box_fill   <- if (!is.null(palette)) palette[1] else pd_pal("box_fill",   cfg = cfg)[1]
  box_border <- pd_pal("box_border", cfg = cfg)[1]
  box_point  <- pd_pal("box_point",  cfg = cfg)[1]
  # ★ 色板是单色 token，不映射成 aes —— 否则会生成一堆同样色的图例键（用户报「图例改坏了」）
  layers <- pd_box_layers(box_type = box_type, points = points, jitter = jitter,
                          fill = box_fill, border = box_border, point_col = box_point, cfg = cfg)
  p <- ggplot2::ggplot(d, ggplot2::aes(x = .data[[x]], y = .data[[y]]))
  for (ly in layers) p <- p + ly
  if (!is.null(letters) && nrow(letters)) {
    lt <- letters
    names(lt)[names(lt) == "cell"] <- x
    lt$.letter_y <- lt$y_max + pd_letter_offset(d[[y]])
    p <- p + ggplot2::geom_text(data = lt,
      ggplot2::aes(x = .data[[x]], y = .data$.letter_y, label = .data$letter),
      inherit.aes = FALSE, size = cfg$plot$base_pt * 0.32, vjust = 0)
  }
  if (!is.null(facet) && facet %in% names(d)) {
    p <- p + ggplot2::facet_wrap(stats::as.formula(paste("~", facet)), scales = "free_y")
  }
  if (!is.null(ylim)) p <- p + ggplot2::coord_cartesian(ylim = ylim)
  p + pd_theme(family = family) +
    ggplot2::labs(x = xlab %||% x, y = ylab %||% y) +
    # 仅为对齐论文图外观：R 内加的 Tukey 字母需顶部空间（勿用 expand = c(0, 0)，会切掉字母）
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.05, 0.12)))
}

# 60.2 双因子组合箱线图（横轴 = 因子1×因子2 组合）
# 仅为对齐论文图外观：论文 Fig 3/4/5 的 9 组合横轴版（Season×Habitat）
#   fill 统一 #00AFBB、点色统一 #FC4E07（分组仍映射，但色板是单色 token）
pd_boxplot_combo <- function(df, y, f1, f2, letters = NULL, ylim = NULL, family = NULL,
                             box_type = NULL, points = NULL, jitter = NULL) {
  if (!pd_has("ggplot2")) return(NULL)
  cfg <- .pd$cfg
  d <- df
  d$.cell <- factor(paste(d[[f1]], d[[f2]], sep = " | "))
  box_fill   <- pd_pal("box_fill",   cfg = cfg)[1]
  box_border <- pd_pal("box_border", cfg = cfg)[1]
  box_point  <- pd_pal("box_point",  cfg = cfg)[1]
  # ★ 色板是单色 token，不映射成 aes —— 否则生成 N 个同样色的图例键（用户报「图例改坏了」）
  #   图型走 pd_box_layers（此前硬编码「箱体+jitter」，论文图反而拿不到蜜蜂图）
  layers <- pd_box_layers(box_type = box_type, points = points, jitter = jitter,
                          fill = box_fill, border = box_border, point_col = box_point, cfg = cfg)
  p <- ggplot2::ggplot(d, ggplot2::aes(x = .data$.cell, y = .data[[y]]))
  for (ly in layers) p <- p + ly
  p <- p +
    pd_theme(family = family) +
    ggplot2::labs(x = paste(f1, "×", f2), y = y) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.05, 0.12))) +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
  if (!is.null(letters) && nrow(letters)) {
    lt <- letters; names(lt)[names(lt) == "cell"] <- ".cell"
    lt$.letter_y <- lt$y_max + pd_letter_offset(d[[y]])
    p <- p + ggplot2::geom_text(data = lt,
      ggplot2::aes(x = .data$.cell, y = .data$.letter_y, label = .data$letter),
      inherit.aes = FALSE, size = cfg$plot$base_pt * 0.32, vjust = 0)
  }
  if (!is.null(ylim)) p <- p + ggplot2::coord_cartesian(ylim = ylim)
  p
}

# 60.3 成对 p 值 —— 与主检验同源（科学性要求）
#   anova_tukey             → Tukey HSD 校正 p（multcomp）
#   lmm                     → emmeans::pairs on lmer（★ 含随机效应，与主检验同源）
#   kruskal_dunn            → Dunn + 多重校正（dunn.test，altp=TRUE 双侧）
#   nonparam_srh / 其它     → Wilcoxon 成对 + 多重校正
#   原文对非正态数据用 t.test 标显著性，与主检验口径矛盾，固不作为默认。
pd_pairwise_p <- function(df, y, factor, method = "auto", cfg = .pd$cfg) {
  d <- data.frame(y = df[[y]], g = droplevels(factor(df[[factor]])))
  d <- d[stats::complete.cases(d), , drop = FALSE]
  lv <- levels(d$g)
  if (length(lv) < 2) return(data.frame())
  cmb <- utils::combn(lv, 2)
  m <- cfg$opts$alpha_test %||% "anova_tukey"
  if (identical(method, "auto"))
    method <- if (identical(m, "lmm")) "lmm"
              else if (identical(m, "anova_tukey")) "tukey"
              else if (identical(m, "kruskal_dunn")) "dunn" else "wilcox"
  rows <- list()

  # ★★ lmm 路线（2026-09-25，pitfalls I13）
  #   旧写法 lmm 也走 aov(y ~ g) + glht —— 忽略随机结构，与主检验【不同源】，
  #   违反本文件「括号 p 必须与主检验同源」。改用 emmeans::pairs 拟合同一混合模型。
  if (identical(method, "lmm")) {
    rs <- cfg$opts$random_structure %||% {
      if (exists("pd_suggest_random", mode = "function")) pd_suggest_random(cfg) else "(1|Site)"
    }
    if (pd_has("lmerTest") && pd_has("emmeans")) {
      rv <- gsub(".*\\|\\s*([^)\\s]+)\\s*\\).*", "\\1", rs)
      if (!(rv %in% names(df))) {
        pd_warn("lmm 括号 p：随机效应变量 '", rv, "' 不在数据中 → 退回 Tukey(aov)")
        method <- "tukey"
      } else {
        d[[rv]] <- factor(df[[rv]][match(rownames(d), rownames(df))])
        if (all(is.na(d[[rv]]))) d[[rv]] <- factor(df[[rv]][stats::complete.cases(df[, c(y, factor)])])
        form <- stats::as.formula(sprintf("y ~ g %s", rs))
        fit <- tryCatch(lmerTest::lmer(form, data = d), error = function(e) NULL)
        if (!is.null(fit)) {
          em <- tryCatch(emmeans::emmeans(fit, specs = "g"), error = function(e) NULL)
          pr <- tryCatch(as.data.frame(emmeans::pairs(em, adjust = "tukey")), error = function(e) NULL)
          if (!is.null(pr)) {
            nm1 <- sub(" - .*", "", pr$contrast); nm2 <- sub(".* - ", "", pr$contrast)
            for (i in seq_len(nrow(pr)))
              rows[[i]] <- data.frame(group1 = trimws(nm1[i]), group2 = trimws(nm2[i]),
                                      p = pr$p.value[i], method = "emmeans(lmer)",
                                      stringsAsFactors = FALSE)
            return(do.call(rbind, rows))
          }
        }
        method <- "tukey"
      }
    } else {
      pd_warn("lmm 括号 p 需要 lmerTest + emmeans → 退回 Tukey(aov)，与主检验不同源")
      method <- "tukey"
    }
  }

  if (identical(method, "tukey") && pd_has("multcomp")) {
    fit <- stats::aov(y ~ g, data = d)
    tk <- multcomp::glht(fit, linfct = multcomp::mcp(g = "Tukey"))
    ps <- summary(tk)$test$pvalues
    for (i in seq_len(ncol(cmb)))
      rows[[i]] <- data.frame(group1 = cmb[1, i], group2 = cmb[2, i],
                              p = ps[i], method = "Tukey HSD", stringsAsFactors = FALSE)
  } else if (identical(method, "dunn") && pd_has("dunn.test")) {
    adj <- cfg$opts$multiple_adj %||% "BH"
    # ★★ altp=TRUE —— 默认 altp=FALSE 给的是单侧半 p（pitfalls I2），
    #   直接拿它判星等于双侧 alpha=0.10，括号星号会虚高。与 12_tests 同口径。
    #   ⚠️ altp=TRUE 时槽位改名 altP / altP.adjusted。
    dt <- dunn.test::dunn.test(d$y, d$g, method = adj, kw = FALSE, list = TRUE, altp = TRUE)
    p_adj <- dt$altP.adjusted %||% dt$P.adjusted
    for (i in seq_along(dt$comparisons)) {
      pr <- trimws(strsplit(dt$comparisons[i], "\\s+-\\s+")[[1]])
      if (length(pr) == 2)
        rows[[length(rows) + 1]] <- data.frame(group1 = pr[1], group2 = pr[2],
                                               p = as.numeric(p_adj[i]),
                                               method = paste0("Dunn(", adj, ")"),
                                               stringsAsFactors = FALSE)
    }
  } else {
    for (i in seq_len(ncol(cmb))) {
      a <- d$y[d$g == cmb[1, i]]; b <- d$y[d$g == cmb[2, i]]
      pv <- tryCatch(stats::wilcox.test(a, b)$p.value, error = function(e) NA_real_)
      rows[[i]] <- data.frame(group1 = cmb[1, i], group2 = cmb[2, i], p = pv,
                              method = "Wilcoxon", stringsAsFactors = FALSE)
    }
    if (length(rows)) {
      z <- do.call(rbind, rows)
      z$p <- stats::p.adjust(z$p, method = cfg$opts$multiple_adj %||% "BH")
      z$method <- paste0("Wilcoxon(", cfg$opts$multiple_adj %||% "BH", ")")
      rows <- list(z)
    }
  }
  if (!length(rows)) return(data.frame())
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

# 60.4 带显著性括号的箱线图（对应原文 ggpubr::stat_compare_means 的括号）
pd_boxplot_bracket <- function(df, y, x, fill = NULL, pw = NULL, cfg = .pd$cfg) {
  p <- pd_boxplot(df, y, x, fill = fill)
  if (is.null(p) || is.null(pw) || !nrow(pw)) return(p)
  lv <- levels(droplevels(factor(df[[x]])))
  yv <- df[[y]]; rng <- diff(range(yv, na.rm = TRUE))
  if (!is.finite(rng) || rng == 0) rng <- 1
  step <- 0.075 * rng
  lay <- data.frame(g1 = pw$group1, g2 = pw$group2, p = pw$p,
                    xi = match(pw$group1, lv), xj = match(pw$group2, lv))
  lay <- lay[!is.na(lay$xi) & !is.na(lay$xj), , drop = FALSE]
  if (!nrow(lay)) return(p)
  base <- max(yv, na.rm = TRUE)
  lay$yb <- base + step * seq_len(nrow(lay))
  al <- cfg$opts$alpha %||% 0.05
  lay$lab <- ifelse(is.na(lay$p), "NA",
             ifelse(lay$p < 0.001, "***", ifelse(lay$p < 0.01, "**",
             ifelse(lay$p < al, "*", "ns"))))
  tsz <- (cfg$plot$base_pt %||% 9) * 0.30
  p +
    ggplot2::geom_segment(data = lay, ggplot2::aes(x = .data$xi, xend = .data$xj,
                                                   y = .data$yb, yend = .data$yb),
                          inherit.aes = FALSE, linewidth = 0.3, colour = "grey20") +
    ggplot2::geom_segment(data = lay, ggplot2::aes(x = .data$xi, xend = .data$xi,
                                                   y = .data$yb, yend = .data$yb - step * 0.3),
                          inherit.aes = FALSE, linewidth = 0.3, colour = "grey20") +
    ggplot2::geom_segment(data = lay, ggplot2::aes(x = .data$xj, xend = .data$xj,
                                                   y = .data$yb, yend = .data$yb - step * 0.3),
                          inherit.aes = FALSE, linewidth = 0.3, colour = "grey20") +
    ggplot2::geom_text(data = lay, ggplot2::aes(x = (.data$xi + .data$xj) / 2,
                                                y = .data$yb + step * 0.15, label = .data$lab),
                       inherit.aes = FALSE, size = tsz) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.02, 0.18))) +
    ggplot2::labs(caption = sprintf("括号 p 值来源：%s", pw$method[1])) +
    ggplot2::theme(plot.caption = ggplot2::element_text(size = (cfg$plot$base_pt %||% 9) - 1.5,
                                                        colour = "grey35"))
}

# 60.5 交互效应图（对应原文 HH::interaction2wt）
pd_interaction_plot <- function(df, y, f1, f2, cfg = .pd$cfg) {
  if (!pd_has("ggplot2")) return(NULL)
  d <- df[stats::complete.cases(df[, c(y, f1, f2)]), c(y, f1, f2), drop = FALSE]
  d[[f1]] <- factor(d[[f1]]); d[[f2]] <- factor(d[[f2]])
  ag <- stats::aggregate(d[[y]], list(a = d[[f1]], b = d[[f2]]), function(z)
    c(mean = mean(z, na.rm = TRUE), se = stats::sd(z, na.rm = TRUE) / sqrt(length(z))))
  g <- data.frame(f1 = ag$a, f2 = ag$b, mean = ag$x[, "mean"], se = ag$x[, "se"])
  pal <- pd_palette(cfg = cfg)
  ggplot2::ggplot(g, ggplot2::aes(x = .data$f1, y = .data$mean,
                                  colour = .data$f2, group = .data$f2)) +
    ggplot2::geom_line(linewidth = 0.6) +
    ggplot2::geom_errorbar(ggplot2::aes(ymin = .data$mean - .data$se,
                                        ymax = .data$mean + .data$se),
                           width = 0.12, linewidth = 0.4) +
    ggplot2::geom_point(size = 1.8) +
    ggplot2::scale_colour_manual(values = rep(pal, length.out = nlevels(g$f2))) +
    ggplot2::labs(x = f1, y = y, colour = f2, subtitle = "Group mean ± SE") +   # 英文：Arial 无 CJK，中文会变方框
    pd_theme() +
    ggplot2::theme(legend.position = "bottom", legend.direction = "horizontal",
                   legend.key.size = grid::unit(0.5, "lines"),
                   axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
}

# 60.5b 变量名解析：config$plot$paper_figs 写的名字 → meta 实际列名
#   先精确匹配，再去掉 . _ 空格后小写匹配，最后查常见别名（FRic/F.Ric、SES.MNTD/mntd）
pd_match_var <- function(v, cols) {
  if (is.null(v) || !nzchar(v)) return("")
  if (v %in% cols) return(v)
  nrm <- function(z) gsub("[._\\s]", "", tolower(z))
  hit <- cols[nrm(cols) == nrm(v)]
  if (length(hit)) return(hit[[1]])
  alias <- list(
    FRic       = c("F.Ric", "fd.FRic", "FRic", "F_Ric", "fric"),
    `SES.MNTD` = c("mntd", "mntd.obs.z", "SES.MNTD", "ses.mntd", "sesmntd"),
    Shannon    = c("Shannon", "shannon"),
    PD         = c("PD", "pd", "Faith"),
    Simpson    = c("Simpson", "simpson"),
    Pielou     = c("Pielou", "pielou"),
    # ★ 系统发育结构指数（2026-09-25 并入默认响应集）
    NTI        = c("NTI", "nti", "SES.MNTD.neg"),
    NRI        = c("NRI", "nri", "SES.MPD.neg"),
    # ★ 群落结构变量（硕士论文 height/coverage/density 或 HT/COV/DEN）
    Height     = c("Height", "height", "HT", "H", "株高"),
    Coverage   = c("Coverage", "coverage", "COV", "C", "盖度"),
    Density    = c("Density", "density", "DEN", "D", "密度")
  )
  i <- match(nrm(v), nrm(names(alias)))
  if (!is.na(i)) {
    for (cand in alias[[i]]) if (cand %in% cols) return(cand)
    hit <- cols[nrm(cols) %in% nrm(alias[[i]])]
    if (length(hit)) return(hit[[1]])
  }
  hit <- cols[grepl(nrm(v), nrm(cols), fixed = TRUE)]
  if (length(hit) == 1) return(hit[[1]])
  ""
}

# 60.6 主入口
# 60.6 出图总入口 —— 图型可选（config$plot$box_type）
#   "both" 时把 box / beeswarm 各跑一遍，文件名加 _box / _swarm 后缀
pd_run_plots <- function(cfg = .pd$cfg, dat = NULL, tests = NULL, save = TRUE) {
  bt <- cfg$plot$box_type %||% "box"
  if (identical(bt, "both")) {
    out <- list()
    for (k in c("box", "beeswarm")) {
      cfg2 <- cfg
      cfg2$plot$box_type <- k
      out[[k]] <- pd_run_plots_one(cfg = cfg2, dat = dat, tests = tests,
                                   save = save, suffix = if (k == "box") "_box" else "_swarm")
    }
    return(invisible(out))
  }
  pd_run_plots_one(cfg = cfg, dat = dat, tests = tests, save = save, suffix = "")
}

pd_run_plots_one <- function(cfg = .pd$cfg, dat = NULL, tests = NULL, save = TRUE, suffix = "") {
  if (!pd_require("ggplot2", "60_plots")) return(invisible(NULL))
  dat <- dat %||% pd_load_data(cfg)
  pd_msg("")
  pd_msg("### 60 箱线图 / 交互图 / 拼图 ###")

  mt <- dat$meta
  fac <- pd_design_factors(cfg)            # 单/双因素由 config$design$factor_mode 决定
  f1 <- fac[1]
  f2 <- if (length(fac) > 1) fac[2] else NA
  if (!is.na(f2) && !(f2 %in% names(mt))) f2 <- NA
  groups <- list(alpha = cfg$response$alpha, func = cfg$response$func,
                 phylo = cfg$response$phylo, community = cfg$response$community)
  # ★ 第 3 轮修正：tests$letters 没有 `variable` 列（只有 cell/n/y_max/letter），
  #   而 tests$cells 有（variable/cell/n/mean/sd/letter/y_max）。
  #   旧写法用 tests$letters + "variable" %in% names(...) 判断 → 恒 FALSE → 所有面板没字母。
  #   改用 tests$cells 作为字母查找表。
  letters_all <- if (!is.null(tests)) {
    if (!is.null(tests$cells) && nrow(tests$cells) && "variable" %in% names(tests$cells)) tests$cells
    else if (!is.null(tests$letters) && nrow(tests$letters)) tests$letters
    else data.frame()
  } else data.frame()
  # ★ 显著性标注按【分组数】自动选（用户 2026-09-25）
  #   「大于 4 个分组的统一标注显著性字母，而不是括号；4 个以内的可以考虑用括号」
  #   分组数 = 括号实际要比较的组数 = f1 水平数（pd_boxplot_bracket 只在 f1 水平间画）
  #   ★ 双因素一律 letters：x 轴是 f1×f2 组合（pd_boxplot_combo），
  #     括号模式只在 f1 间比较、会把 combo 横轴降级成 f1 横轴 —— 版式不能因标注而变。
  #   ★ 显式写了 opts$sig_label 就不再自动（保留 override）。
  n_f1 <- length(unique(stats::na.omit(as.character(mt[[f1]]))))
  auto_label <- if (!is.na(f2) || n_f1 > 4) "letters" else "bracket"
  sig_label  <- cfg$opts$sig_label %||% auto_label   # letters | bracket | none
  if (is.null(cfg$opts$sig_label)) {
    why <- if (!is.na(f2)) sprintf("双因素 %s×%s，combo 横轴没有对应括号画法", f1, f2)
           else if (n_f1 > 4) sprintf(">4 组（%d 个），括号会挤成一团", n_f1)
           else sprintf("≤4 组（%d 个），括号可读", n_f1)
    pd_msg(sprintf("[60] 分组 %d 个（%s）→ 标注方式自动定为 %s —— %s", n_f1, f1, sig_label, why))
  }

  made <- list(); pw_used <- list()
  for (gname in names(groups)) {
    vars <- groups[[gname]][groups[[gname]] %in% names(mt)]
    if (!length(vars)) next
    pls <- list()
    for (y in vars) {
      lt <- if (nrow(letters_all) && "variable" %in% names(letters_all))
        letters_all[letters_all$variable == y, , drop = FALSE] else NULL
      if (!is.null(lt) && !nrow(lt)) lt <- NULL
      p <- NULL
      if (identical(sig_label, "bracket")) {
        pw <- pd_pairwise_p(mt, y, f1, cfg = cfg)
        pw_used[[y]] <- pw
        p <- pd_boxplot_bracket(mt, y, f1, fill = if (!is.na(f2)) f2 else NULL, pw = pw, cfg = cfg)
      } else if (identical(sig_label, "letters")) {
        # ★ 只看 f2 是否存在（旧写法 && !is.null(lt) 会在缺字母时把双因素静默降级成单因子横轴）
        p <- if (!is.na(f2)) pd_boxplot_combo(mt, y, f1, f2, letters = lt)
             else pd_boxplot(mt, y, f1, fill = if (!is.na(f2)) f2 else NULL, letters = lt)
      } else {
        p <- pd_boxplot(mt, y, f1, fill = if (!is.na(f2)) f2 else NULL)
      }
      if (!is.null(p)) pls[[y]] <- p
    }
    if (!length(pls)) next
    n <- length(pls); ncol <- if (n <= 2) n else if (n <= 4) 2 else 3
    # 与 Fig3/4/5 重复的分组复合图，默认不再单独出（用户：只留论文风格）
    #   save_singles=TRUE 时仍出，便于逐图检查
    if (isTRUE(cfg$plot$save_singles)) {
      if (pd_has("patchwork")) {
        pkg <- pd_compose(pls, ncol = ncol, tags = if (n > 1) "a" else NULL)
        made[[gname]] <- pd_save_pdf(pkg, paste0("box_", gname, suffix), "60",
                                     height_mm = ceiling(n / ncol) * 70 + 25)
      } else {
        for (nm in names(pls)) made[[paste0(gname, "_", nm, suffix)]] <-
          pd_save_pdf(pls[[nm]], paste0("box_", gname, "_", nm, suffix), "60", height_mm = 85)
      }
    }
    pd_msg(sprintf("[60] %s 组：%d 个图（%s），标注方式 = %s", gname, n,
                   paste(vars, collapse = ", "), sig_label))
  }

  # ---- 论文等价图：Fig 3+4+5 合成一张 4 面板 `60_box_panel` ----
  #  仅为对齐论文图外观：Shannon / FRic / PD / SES.MNTD 同风格 9 组合横轴箱线 + Tukey 字母
  #   ★ 四面板美化全统一（用户第 3 轮）：同 Arial 字体、同字号、同箱体、同散点、同字母样式
  #   ★ 确保所有面板都有 Tukey 字母：pd_run_tests 默认只测 alpha 组时，
  #     会漏掉 F.Ric/PD/mntd 的 letters → (b)(c)(d) 没字母。这里按需补跑。
  pf <- cfg$plot$paper_figs %||% list()
  need_vars <- unique(unlist(lapply(pf, function(s) s$vars)))
  got_vars  <- unique(vapply(need_vars, pd_match_var, character(1), cols = names(mt), USE.NAMES = FALSE))
  got_vars  <- got_vars[nzchar(got_vars)]
  # ★★ have_lt 必须从 tests$cells 取（tests$letters 没有 variable 列，旧写法恒得空 →
  #    补跑每次都触发、白跑一遍）。同上面 letters_all 的口径。
  have_lt <- if (!is.null(letters_all) && nrow(letters_all) && "variable" %in% names(letters_all))
               unique(as.character(letters_all$variable)) else character(0)
  if (!all(got_vars %in% have_lt)) {
    miss <- setdiff(got_vars, have_lt)
    pd_msg(sprintf("[60] 补跑 Tukey 字母（缺：%s）—— 用 stem='_letters' 落盘，不覆盖 12_<method>.xlsx",
                   paste(miss, collapse = ", ")))
    # ★★ save=FALSE + 不同 stem（pitfalls H13）：旧写法直接 save=TRUE 写 12_<method>.xlsx，
    #   会把规范结果表覆盖成【只有这几个变量】的子集 → 70 的 T3/S2/t8 全报「无源」。踩过两次。
    tests2 <- tryCatch(pd_run_tests(cfg = cfg, dat = dat, vars = got_vars,
                                    save = TRUE, stem = paste0(cfg$opts$alpha_test %||% "anova_tukey", "_letters")),
                       error = function(e) { pd_warn("补跑 tests 失败: ", conditionMessage(e)); NULL })
    if (!is.null(tests2) && !is.null(tests2$cells) && nrow(tests2$cells))
      letters_all <- tests2$cells   # ★ 必须是 cells（含 variable 列），不是 letters（无 variable）
  }
  box_pls <- list()
  for (fn in names(pf)) {
    spec <- pf[[fn]]
    if (is.null(spec$vars)) next          # fig2 等非箱线图条目由别的模块出
    want <- spec$vars %||% character(0)
    got  <- vapply(want, pd_match_var, character(1), cols = names(mt), USE.NAMES = FALSE)
    ok   <- nzchar(got) & got %in% names(mt)
    if (!any(ok)) {
      pd_msg(sprintf("[60] 论文图 %s 的变量（%s）未在 meta 中找到，跳过；请改 config$plot$paper_figs$%s$vars",
                     fn, paste(want, collapse = ", "), fn))
      next
    }
    want <- want[ok]; got <- got[ok]
    fam <- if (identical(spec$font, "serif")) "serif" else NULL
    for (i in seq_along(got)) {
      y <- got[i]
      lt <- if (nrow(letters_all) && "variable" %in% names(letters_all)) {
        z <- letters_all[letters_all$variable %in% c(y, want[i]), , drop = FALSE]
        if (nrow(z)) z else NULL
      } else NULL
      p <- if (!is.na(f2))
             pd_boxplot_combo(mt, y, f1, f2, letters = lt, family = fam)   # ★ 一律 9 组合横轴（旧写法按 layout 分支导致 4 面板两种图型）
           else
             pd_boxplot(mt, y, f1, fill = NULL, letters = lt, family = fam)
      if (!is.null(p)) box_pls[[y]] <- p
    }
    # save_singles=TRUE 时同时出单张（便于逐图检查 / 直接裁用）
    if (isTRUE(cfg$plot$save_singles)) {
      one <- if (length(got) == 1) box_pls[[got[1]]] else pd_compose(as.list(box_pls[got]), ncol = 1, tags = "a")
      if (!is.null(one))
        made[[paste0(fn, suffix)]] <- pd_save_pdf(one, paste0(fn, suffix), "60",
                                                  size = spec$size %||% "default_double")
    }
    pd_msg(sprintf("[60] 论文图 %s ← %s（%s, %s）", fn, paste(got, collapse = "+"),
                   spec$layout %||% "combo", spec$size %||% "default_double"))
  }
  if (length(box_pls)) {
    # 同类多图合成一张（用户：Fig3/4/5 拼一张 4 面板，写论文裁）
    n <- length(box_pls)
    out <- if (n == 1) box_pls[[1]] else pd_compose(box_pls, ncol = min(2L, n), tags = "a")
    made[[paste0("box_panel", suffix)]] <- pd_save_pdf(out, paste0("box_panel", suffix),
                                                       "60", size = "box_panel")
    pd_msg(sprintf("[60] 箱线总成 60_box_panel%s.pdf（%d 面板合成一张）", suffix, n))
  }

  # 交互效应图（对应原文 HH::interaction2wt）—— 同类多图合成一张
  if (!is.na(f2) && isTRUE(cfg$opts$interaction_plot %||% TRUE)) {
    ip <- list()
    for (y in unique(unlist(groups))) {
      if (!y %in% names(mt)) next
      pk <- pd_interaction_plot(mt, y, f1, f2, cfg)
      if (is.null(pk)) next
      ip[[y]] <- pk
      if (isTRUE(cfg$plot$save_singles))
        made[[paste0("interaction_", y)]] <- pd_save_pdf(pk, paste0("interaction_", y), "60", height_mm = 95)
    }
    if (length(ip)) {
      # ★ 第 3 轮修正：旧写法 pd_compose 直接给 pd_save_pdf，失败时 ggsave 建出 **0 字节空 PDF**
      #   （用户报「60_interaction_panel 损坏」）。加 tryCatch，失败则回退逐张落盘再文件级合并。
      comp <- NULL
      if (pd_has("patchwork")) {
        comp <- tryCatch({
          np <- length(ip)
          pd_compose(ip, ncol = min(2L, np), tags = "a", guides = "collect")
        }, error = function(e) { pd_warn("交互图合成失败: ", conditionMessage(e)); NULL })
      }
      if (!is.null(comp)) {
        f <- tryCatch(pd_save_pdf(comp, "interaction_panel", "60", size = "interaction_panel"),
                      error = function(e) { pd_warn("交互图保存失败: ", conditionMessage(e)); NULL })
        if (!is.null(f) && file.exists(f) && file.info(f)$size > 0) made$interaction_panel <- f
        else comp <- NULL
      }
      if (is.null(comp)) {
        # 回退：逐张落盘 → 文件级合并（pd_combine_pdfs 会删散件）
        sc <- character(0)
        for (nm in names(ip)) {
          f <- pd_save_pdf(ip[[nm]], paste0("interaction_", nm), "60", height_mm = 95)
          if (!is.null(f)) sc <- c(sc, f)
        }
        made$interaction_panel <- pd_combine_pdfs(sc, "interaction_panel", "60")
      }
      pd_msg(sprintf("[60] 交互效应图：%d 面板合成一张 60_interaction_panel.pdf（%s × %s）",
                     length(ip), f1, f2))
    }
  }

  if (save && length(pw_used)) {
    pw_all <- do.call(rbind, lapply(names(pw_used), function(n) {
      z <- pw_used[[n]]; if (is.null(z) || !nrow(z)) return(NULL)
      cbind(variable = n, z)
    }))
    if (!is.null(pw_all) && nrow(pw_all))
      utils::write.csv(pw_all, file.path(cfg$paths$results, "60_pairwise_p_for_brackets.csv"),
                       row.names = FALSE, fileEncoding = "UTF-8")
  }
  pd_msg(sprintf("[60] 完成。图尺寸 = %s，基准字号 %s pt", cfg$plot$size %||% "double",
                 cfg$plot$base_pt %||% 9))
  invisible(made)
}

# 60.7 单图快速调用（交互式用）
pd_quick_box <- function(cfg = .pd$cfg, y, x = NULL) {
  dat <- pd_load_data(cfg)
  x <- x %||% cfg$design$factors[1]
  print(pd_boxplot(dat$meta, y, x, fill = cfg$design$factors[2]))
}
