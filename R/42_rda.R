# ============================================================
# 42_rda.R · 约束排序（DCA 选法 → RDA / CCA）+ envfit
#   对应硕士论文图 7-1（RDA biplot：样方形状分组 + 物种粉方块 + 青箭头 + 点线零轴）
#                              + 表 7-1（RDA1/RDA2 方向余弦 + R² + p）
#         （旧口径 Diversity 2023 Fig 7 的 MDPI 美化见 pitfalls H11）
#   输入：多度矩阵 dat$abundance（Hellinger 变换）
#         环境表 files$env 的解释变量（config$opts$env，z-score）
#   输出：results/42_rda.xlsx（dca_gradient / envfit / model_test / run_info）
#         figures/42_rda_biplot.pdf
# 依赖：vegan（decorana/rda/cca/envfit/permutest）；ggplot2 / ggrepel
#
# ★ 科学性口径（写进 run_info，勿混用）
#   · 多度必须 Hellinger 变换（decostand "hellinger"）—— 否则长尾物种主导 RDA
#   · 环境变量 z-score（scale）
#   · DCA 梯度长度 = 各轴 site scores 的 max-min（SD 单位）；>3 用 CCA，否则 RDA
#   · envfit 与 RDA 用同一套解释变量、同一套样方（口径一致才可比）
# ============================================================

# 42.1 读环境表并与 meta 按 sample_id 对齐
pd_env_join <- function(dat, cfg = .pd$cfg) {
  envs <- cfg$opts$env %||% character(0)
  env_df <- pd_read_table(cfg$files$env)
  if (is.null(env_df) || !nrow(env_df)) {
    pd_warn("42 跳过：缺环境表 files$env（", cfg$files$env %||% "NA", "）")
    return(NULL)
  }
  id <- cfg$key$sample_id %||% "sample_id"
  if (!(id %in% names(env_df))) { pd_warn("42 跳过：环境表缺列 ", id); return(NULL) }
  mt <- dat$meta
  if (!(id %in% names(mt)))  { pd_warn("42 跳过：meta 缺列 ", id);  return(NULL) }
  m <- merge(mt, env_df, by = id, suffixes = c("", ".env"))
  envs <- envs[envs %in% names(m)]
  if (!length(envs)) { pd_warn("42 跳过：opts$env 列都不在环境表里"); return(NULL) }
  list(df = m, envs = envs, id = id)
}

# 42.2 DCA 梯度长度（SD 单位）→ 选 RDA / CCA
#   ★★ 口径修正（2026-09-25，pitfalls I14）
#   业界标准（ter Braak；Lepš & Šmilauer；Canoco）：
#     梯度长度 = DCA 【第 1 轴】物种（或样方）得分的【极差 max−min】，单位 SD
#   旧写法逐条抄 MDPI《RDA代码.txt》：max(dca$rproj[, 1:4]) —— 取 4 轴最大值、不减 min。
#   得分不以 0 为下界时会【低估梯度长度】，可能把该用 CCA 的数据判成 RDA。
#   ★ 另：DCA 应跑在【未 Hellinger】的多度上（3/4 SD 阈值是按未变换标定的，
#     Hellinger 会压缩梯度）—— 由 pd_run_rda 传对矩阵。
#   ★ 判据本身（>4 CCA；3–4 皆可取 RDA；<3 RDA）是业界通行的，保留。
#   opts$dca_gradient = "range1"（默认，业界标准）| "legacy_max4"（旧口径，可复现）
pd_dca_gradient <- function(veg, cfg = .pd$cfg) {
  dca <- tryCatch(vegan::decorana(veg = veg), error = function(e) NULL)
  if (is.null(dca)) return(NULL)
  mode <- cfg$opts$dca_gradient %||% "range1"
  if (identical(mode, "legacy_max4")) {
    gl <- tryCatch(apply(dca$rproj[, 1:4, drop = FALSE], 2, max), error = function(e) NULL)
    if (is.null(gl)) return(NULL)
    return(data.frame(axis = paste0("DCA", seq_along(gl)),
                      gradient_length = round(as.numeric(gl), 4),
                      method = "legacy_max4 (max of rproj[,1:4], 旧口径)",
                      stringsAsFactors = FALSE))
  }
  # 业界标准：第 1 轴物种得分极差
  gl1 <- tryCatch({
    sc <- vegan::scores(dca, display = "species", choices = 1)
    diff(range(as.numeric(sc), na.rm = TRUE))
  }, error = function(e) NULL)
  if (is.null(gl1) || !is.finite(gl1)) {
    # 退化：试样方得分
    gl1 <- tryCatch({
      sc <- vegan::scores(dca, display = "sites", choices = 1)
      diff(range(as.numeric(sc), na.rm = TRUE))
    }, error = function(e) NULL)
  }
  if (is.null(gl1) || !is.finite(gl1)) return(NULL)
  # 顺带给前 4 轴极差作参考
  gl4 <- tryCatch({
    sc <- vegan::scores(dca, display = "species", choices = 1:4)
    apply(sc, 2, function(z) diff(range(as.numeric(z), na.rm = TRUE)))
  }, error = function(e) NULL)
  out <- data.frame(axis = "DCA1", gradient_length = round(as.numeric(gl1), 4),
                    method = "range1 (第1轴物种得分极差，业界标准)",
                    stringsAsFactors = FALSE)
  if (!is.null(gl4)) {
    out <- rbind(out, data.frame(axis = paste0("DCA", seq_along(gl4)),
                                 gradient_length = round(as.numeric(gl4), 4),
                                 method = "range (各轴极差，仅参考)",
                                 stringsAsFactors = FALSE))
  }
  out
}

pd_pick_ordination <- function(max_gradient) {
  if (!is.finite(max_gradient)) return("rda")
  if (max_gradient > 4) "cca" else "rda"     # 3–4 两者皆可 → 默认 RDA（同 MDPI 实际选择）
}

# 42.3 biplot —— ★ 美化逐条抄 Fig3b_dbRDA_rf_gam 面板 A
#   来源：`03-生态学数据分析/R代码/3_environmental_drivers.R` L939–967（Part A db-RDA）
#   关键参数（必须照抄，否则美化对不上）：
#     geom_hline/vline(0, linewidth=0.2, colour="grey90")        # 浅灰零轴（不是点线）
#     geom_point(aes(colour=grp), size=0.9, alpha=0.4, stroke=0) # 样方点按组着色
#     scale_colour_manual(values=cols, drop=FALSE)
#     箭头长度归一：arrow_mul = 0.78 * site_radius / bp_radius   # 最长箭头=样方云半径 0.78
#     geom_segment(colour="#3182BD", linewidth=0.45,
#                  arrow=arrow(length=unit(0.09,"cm"), type="closed"))
#     geom_text_repel(colour="black", size=pt2gg(7.5), bg.colour="white", bg.r=0.12,
#                     segment.colour="grey55", segment.size=0.2,
#                     box.padding=0.26, point.padding=0.16, min.segment.length=0)
#     labs(x=sprintf("RDA1 (%.1f%%)", pct), title=, subtitle=R²adj, p)
#     theme_isme() + coord_fixed() + legend_inside()
#   ★ 物种只画点不画箭头（用户 2026-09-25）；物种名仅 n<plot$rda_sp_label_max 才标
#   ★ 得分口径见 pitfalls H11：图箭头 = scores(display="bp")；
#     表 7-1 的 RDA1/RDA2 = ef$vectors$arrows（单位长度）—— 两者不同
pd_plot_rda_biplot <- function(mod, ef, grp, site_scores, cfg = .pd$cfg,
                               r2adj = NULL, pval = NULL) {
  if (!pd_has("ggplot2")) return(NULL)
  sp_scale <- cfg$plot$rda_sp_scale %||% 2       # 物种得分放大倍数

  # ---- 得分（vegan ≥2.6 的 summary() 不返回 sites/species/biplot，见 H11）----
  st <- tryCatch(as.data.frame(vegan::scores(mod, display = "sites", choices = 1:2)[, 1:2]),
                 error = function(e) NULL)
  if (is.null(st) || !nrow(st)) st <- as.data.frame(site_scores[, 1:2, drop = FALSE])
  names(st) <- c("RDA1", "RDA2")

  sp <- tryCatch(as.data.frame(vegan::scores(mod, display = "species", choices = 1:2)[, 1:2]) * sp_scale,
                 error = function(e) NULL)
  if (!is.null(sp) && nrow(sp)) names(sp) <- c("RDA1", "RDA2") else sp <- NULL

  ar <- tryCatch(as.data.frame(vegan::scores(mod, display = "bp", choices = 1:2)[, 1:2]),
                 error = function(e) NULL)
  if (is.null(ar) || !nrow(ar))
    ar <- tryCatch(as.data.frame(mod$CCA$biplot[, 1:2, drop = FALSE]), error = function(e) NULL)
  if (is.null(ar) || !nrow(ar))
    ar <- tryCatch(as.data.frame(ef$vectors$arrows[, 1:2, drop = FALSE]), error = function(e) NULL)
  if (is.null(ar) || !nrow(ar)) { pd_warn("42 biplot 跳过：取不到箭头坐标"); return(NULL) }
  names(ar) <- c("ax", "ay"); ar$name <- rownames(ar)

  # ---- 箭头长度归一（原文：最长箭头 = 样方云半径的 0.78）----
  site_radius <- max(sqrt(st$RDA1^2 + st$RDA2^2), na.rm = TRUE)
  bp_radius   <- max(sqrt(ar$ax^2 + ar$ay^2), na.rm = TRUE)
  arrow_mul   <- if (is.finite(bp_radius) && bp_radius > 0)
    0.78 * site_radius / bp_radius else 1
  ar$ax_s <- ar$ax * arrow_mul
  ar$ay_s <- ar$ay * arrow_mul

  # ---- 轴解释率：原文 var_exp <- round(eig[1:2] / tot.chi * 100, 1) ----
  #   ★ 占【总惯量】tot.chi，不是占约束部分 sum(eig) —— 两者差很多
  pct <- tryCatch({
    as.numeric(100 * mod$CCA$eig[1:2] / mod$tot.chi)
  }, error = function(e) c(NA_real_, NA_real_))
  axname <- if ("rda" %in% class(mod)) "RDA" else "CCA"
  xlab <- sprintf("%s1 (%.1f%%)", axname, pct[1])
  ylab <- sprintf("%s2 (%.1f%%)", axname, pct[2])

  # ---- 标题 / 副标题（原文 title + subtitle=R²adj, p）----
  ttl <- sprintf("%s (Hellinger)", axname)
  if (is.null(r2adj)) r2adj <- tryCatch(vegan::RsquareAdj(mod)$adj.r.squared,
                                        error = function(e) NA_real_)
  if (is.null(pval)) pval <- NA_real_
  sub_txt <- if (is.finite(r2adj)) {
    pstr <- if (!is.finite(pval)) "" else
      ifelse(pval < 0.001, ", p < 0.001", sprintf(", p = %.3f", pval))
    sprintf("R²adj = %.3f%s", r2adj, pstr)
  } else NULL

  # ★ 样方点 / 物种点 —— **二选一**（用户 2026-09-25）
  #   默认只出样方点；物种点多时再叠上去会糊成一团。
  #   两者都少（样方 < 40 且物种 < 30）才可考虑都出。
  #   ★ 用 skill 写新论文时，这一项要和别的分析问题一起问用户（SKILL.md 第 3 步）
  show <- cfg$plot$rda_biplot_show %||% "sites"   # sites | species | both
  n_sp <- if (is.null(sp)) 0L else nrow(sp)
  n_st <- nrow(st)
  if (identical(show, "both") && (n_st >= 40 || n_sp >= 30)) {
    pd_msg(sprintf("[42] 样方 %d / 物种 %d 有一边偏多 → 改只出样方点（rda_biplot_show=\"both\" 未采纳）",
                   n_st, n_sp))
    show <- "sites"
  }
  pd_msg(sprintf("[42] 双标图显示：%s（样方 %d，物种 %d）", show, n_st, n_sp))

  # ---- 分组与色板 ----
  grp <- rep_len(as.character(grp), nrow(st))
  st$grp <- factor(grp, levels = unique(grp))
  cols <- pd_pal("rda_site", n = length(unique(grp)), cfg = cfg)
  pt_size  <- cfg$plot$rda_pt_size  %||% 0.9     # 原文 PT_SIZE_STD
  pt_alpha <- cfg$plot$rda_pt_alpha %||% 0.4     # 原文 PT_ALPHA_STD

  p <- ggplot2::ggplot() +
    # ★ 浅灰零轴（原文 linewidth=0.2, colour="grey90"）
    ggplot2::geom_hline(yintercept = 0, linewidth = 0.2, colour = "grey90") +
    ggplot2::geom_vline(xintercept = 0, linewidth = 0.2, colour = "grey90")

  # ---- 样方点（只在 show 含 sites 时出）----
  if (show %in% c("sites", "both")) {
    p <- p +
      ggplot2::geom_point(data = st,
                          ggplot2::aes(x = .data$RDA1, y = .data$RDA2, colour = .data$grp),
                          size = pt_size, alpha = pt_alpha, stroke = 0) +
      ggplot2::scale_colour_manual(values = cols, name = NULL, drop = FALSE)
  }

  # ---- 物种点（只在 show 含 species 时出；**不画箭头**）----
  if ((show %in% c("species", "both")) && n_sp > 0) {
    p <- p + ggplot2::geom_point(
      data = sp, ggplot2::aes(x = .data$RDA1, y = .data$RDA2),
      inherit.aes = FALSE, shape = 15,
      size = pt_size, alpha = pt_alpha,
      colour = pd_pal("rda_sp_point", cfg = cfg)[1])
    # ★ 物种名只在种数少时标（阈值 plot$rda_sp_label_max，默认 30）
    n_max <- cfg$plot$rda_sp_label_max %||% 30
    if (n_sp < n_max) {
      sp$name <- rownames(sp)
      p <- p + if (pd_has("ggrepel"))
        ggrepel::geom_text_repel(
          data = sp, ggplot2::aes(x = .data$RDA1, y = .data$RDA2, label = .data$name),
          inherit.aes = FALSE, size = pd_pt2gg(cfg$plot$s_ann %||% 7.5),
          colour = "black", max.overlaps = Inf, seed = 42,
          bg.colour = "white", bg.r = 0.12,
          segment.size = 0.2, segment.colour = "grey55")
      else ggplot2::geom_text(
        data = sp, ggplot2::aes(x = .data$RDA1, y = .data$RDA2, label = .data$name),
        inherit.aes = FALSE, size = pd_pt2gg(cfg$plot$s_ann %||% 7.5),
        colour = "black", check_overlap = TRUE)
    } else {
      pd_msg(sprintf("[42] 物种数 %d ≥ %d → 只画点不标物种名", n_sp, n_max))
    }
  }

  # ---- 环境箭头（#3182BD，小实心头）+ 轴标 + 标题/副标题 ----
  p <- p +
    ggplot2::geom_segment(data = ar,
                          ggplot2::aes(x = 0, y = 0, xend = .data$ax_s, yend = .data$ay_s),
                          inherit.aes = FALSE,
                          colour = pd_pal("rda_env_arrow", cfg = cfg)[1],
                          linewidth = 0.45,
                          arrow = ggplot2::arrow(length = grid::unit(0.09, "cm"),
                                                 type = "closed")) +
    ggplot2::xlab(xlab) + ggplot2::ylab(ylab) +
    ggplot2::labs(title = ttl, subtitle = sub_txt)

  # ★ 环境因子标签：黑字 + 白描边（原文 bg.colour="white", bg.r=0.12）
  p <- p + if (pd_has("ggrepel"))
    ggrepel::geom_text_repel(
      data = ar, ggplot2::aes(x = .data$ax_s, y = .data$ay_s, label = .data$name),
      inherit.aes = FALSE, size = pd_pt2gg(cfg$plot$s_ann %||% 7.5),
      colour = "black", box.padding = 0.26, point.padding = 0.16,
      min.segment.length = 0, segment.size = 0.2, segment.colour = "grey55",
      max.overlaps = Inf, seed = 42, bg.colour = "white", bg.r = 0.12)
  else ggplot2::geom_text(
    data = ar, ggplot2::aes(x = .data$ax_s * 1.05, y = .data$ay_s * 1.05, label = .data$name),
    inherit.aes = FALSE, size = pd_pt2gg(cfg$plot$s_ann %||% 7.5), colour = "black")

  # ★ 主题 + 等轴 + 图例内嵌右下（原文 theme_isme + coord_fixed + legend_inside）
  p <- p + pd_theme_isme(cfg = cfg) + ggplot2::coord_fixed()
  p <- tryCatch(p + do.call(ggplot2::theme, pd_legend_inside(cfg = cfg)),
                error = function(e) p)   # ggplot2 <3.5 无 legend.position="inside" → 退回默认
  p
}

# 42.4 主入口
pd_run_rda <- function(cfg = .pd$cfg, dat = NULL, save = TRUE) {
  if (!pd_require("vegan", "42_rda")) return(invisible(NULL))
  pd_msg("")
  pd_msg("### 42 约束排序（DCA → RDA/CCA）+ envfit ###")
  dat <- dat %||% pd_load_data(cfg)
  ej <- pd_env_join(dat, cfg)
  if (is.null(ej)) return(invisible(NULL))
  m <- ej$df; envs <- ej$envs

  # 样方对齐：多度矩阵的行 → meta/env 合并表
  id <- ej$id
  ab <- dat$abundance
  if (!all(rownames(ab) %in% m[[id]])) {
    keep <- rownames(ab)[rownames(ab) %in% m[[id]]]
    ab <- ab[keep, , drop = FALSE]
    pd_msg("[42] 样方对齐：", nrow(ab), " / ", nrow(dat$abundance))
  }
  m <- m[match(rownames(ab), m[[id]]), , drop = FALSE]
  if (nrow(ab) < 5) { pd_warn("42 跳过：可用样方 < 5"); return(invisible(NULL)) }

  # ★ Hellinger 变换（不转则长尾物种主导 RDA）
  veg_hel <- vegan::decostand(ab, method = "hellinger")
  env_z   <- as.data.frame(scale(m[, envs, drop = FALSE]))
  names(env_z) <- envs

  # ---- DCA → 方法选择（>4 CCA；3–4 皆可；<3 RDA —— 判据本身是业界通行的）----
  # ★ DCA 跑在【未 Hellinger】的多度上（3/4 SD 阈值按未变换标定，Hellinger 会压缩梯度）
  # ★ 梯度取【第 1 轴极差】（opts$dca_gradient="range1"）；旧口径 max4 可用 "legacy_max4" 复现
  dg <- pd_cached("42_dca", NULL, pd_dca_gradient(ab, cfg = cfg), cfg = cfg)
  if (is.null(dg)) { pd_warn("42 跳过：DCA 失败"); return(invisible(NULL)) }
  # 判据用 DCA1（第一行）；legacy_max4 模式下第一行仍是 DCA1
  maxg <- as.numeric(dg$gradient_length[1])
  method <- pd_pick_ordination(maxg)
  pd_msg(sprintf("[42] DCA 第1轴梯度 %.2f SD（%s）→ 用 %s（<3 RDA；3~4 皆可，取 RDA；>4 CCA）",
                 maxg, dg$method[1], toupper(method)))

  # ---- 约束排序（★ 原文：rda(spe, env, scale = TRUE) 双矩阵接口 + scale=TRUE）----
  mod <- pd_cached(paste0("42_", method), NULL, {
    set.seed(cfg$opts$seed %||% 20260101)
    # ★ cca() 没有 scale 参数（vegan formals: X, Y, Z, ...），传了会被 ... 吞掉、静默无效
    #   → 只有 rda 传 scale。见 pitfalls I2
    tryCatch(if (identical(method, "cca")) vegan::cca(veg_hel, env_z)
             else vegan::rda(veg_hel, env_z, scale = cfg$opts$rda_scale %||% FALSE),
             error = function(e) { pd_warn("42 模型失败: ", conditionMessage(e)); NULL })
  }, cfg = cfg)
  if (is.null(mod)) return(invisible(NULL))

  # ---- envfit（999 置换；opts$restrict_perm 设了就用区组受限置换）----
  perm42 <- if (exists("pd_perm_ctrl", mode = "function"))
    pd_perm_ctrl(cfg, m, nperm = cfg$opts$permutations %||% 999) else (cfg$opts$permutations %||% 999)
  ef <- pd_cached("42_envfit", NULL, {
    set.seed(cfg$opts$seed %||% 20260101)
    tryCatch(vegan::envfit(mod, env_z, permutations = perm42),
             error = function(e) { pd_warn("42 envfit 失败: ", conditionMessage(e)); NULL })
  }, cfg = cfg)

  # ---- 整模型 Monte Carlo 检验 ----
  pt <- pd_cached("42_permutest", NULL, {
    set.seed(cfg$opts$seed %||% 20260101)
    tryCatch(vegan::permutest(mod, permutations = perm42),
             error = function(e) { pd_warn("42 permutest 失败: ", conditionMessage(e)); NULL })
  }, cfg = cfg)
  pt_F <- NA_real_; pt_p <- NA_real_
  if (!is.null(pt)) {
    if (!is.null(pt$tab)) {
      # ★ check.names=FALSE —— 默认会把 `Pr(>F)` 改名成 `Pr..F..` 导致取不到 p
      tb <- as.data.frame(pt$tab, check.names = FALSE)
      if ("F" %in% names(tb)) pt_F <- tb$F[1]
      pcol <- grep("^Pr", names(tb), value = TRUE)[1]
      if (!is.na(pcol)) pt_p <- tb[[pcol]][1]
    }
    # ★ vegan ≥2.6 的 permutest.cca 无 $tab，只有 F.0 / F.perm → 从置换分布算 p
    if (!is.finite(pt_F) && !is.null(pt$F.0)) pt_F <- as.numeric(pt$F.0)[1]
    if (!is.finite(pt_p) && !is.null(pt$F.perm) && !is.null(pt$F.0)) {
      fp <- as.numeric(pt$F.perm); f0 <- as.numeric(pt$F.0)[1]
      fp <- fp[is.finite(fp)]
      if (length(fp) && is.finite(f0))
        pt_p <- (sum(fp >= f0) + 1) / (length(fp) + 1)   # 标准置换 p（含 +1 校正）
    }
  }

  # ---- 表 ----
  ef_tab <- if (!is.null(ef) && !is.null(ef$vectors)) {
    data.frame(env = names(ef$vectors$r), r = as.numeric(ef$vectors$r),
               R2 = round(as.numeric(ef$vectors$r)^2, 4),
               p = as.numeric(ef$vectors$pvals),
               stringsAsFactors = FALSE)
  } else data.frame()
  if (nrow(ef_tab)) {
    ef_tab$sig <- pd_sig(ef_tab$p)
    # ★ 表 7-1 的 RDA1/RDA2 = envfit 箭头方向余弦（单位长度，RDA1²+RDA2²=1）
    #   来源：ef$vectors$arrows —— vegan 文档明确 "arrows of unit length"
    #   论文表 7-1 核对：pH (-0.07964, -0.99682) 平方和=1 ✓
    #   ⚠️ 不是 mod$CCA$biplot（那是指向图的箭头，长度∝拟合优度，平方和≠1）
    bp <- tryCatch(as.data.frame(ef$vectors$arrows[, 1:2, drop = FALSE]),
                   error = function(e) NULL)
    if (!is.null(bp) && nrow(bp)) {
      names(bp) <- c("RDA1", "RDA2")
      bp$env <- rownames(bp)
      ef_tab$RDA1 <- bp$RDA1[match(ef_tab$env, bp$env)]
      ef_tab$RDA2 <- bp$RDA2[match(ef_tab$env, bp$env)]
    } else {
      ef_tab$RDA1 <- NA_real_
      ef_tab$RDA2 <- NA_real_
    }
  }

  model_tab <- data.frame(
    item  = c("method", "n_sites", "n_species", "n_env",
              "constraint_inertia", "unconstrained_inertia", "total_inertia",
              "permutest_F", "permutest_p"),
    value = c(method, nrow(ab), ncol(ab), length(envs),
              round(mod$CCA$tot.chi, 4), round(mod$CA$tot.chi, 4), mod$tot.chi,
              ifelse(is.na(pt_F), NA, round(pt_F, 4)), pt_p),
    stringsAsFactors = FALSE)

  if (save) {
    pd_write_table(list(
      dca_gradient = dg,
      envfit       = ef_tab,
      model_test   = model_tab,
      run_info     = data.frame(
        item = c("多度变换", "环境变换", "DCA最大梯度", "选用方法",
                 "envfit 置换", "permutest 置换", "解释变量"),
        value = c("Hellinger (vegan::decostand)", "z-score (scale)",
                  sprintf("%.3f SD", maxg), method,
                  cfg$opts$permutations %||% 999, cfg$opts$permutations %||% 999,
                  paste(envs, collapse = ", ")),
        stringsAsFactors = FALSE)
    ), stem = "rda", module = "42")
  }

  # ---- 图（美化 = Fig3b_dbRDA_rf_gam 面板 A）----
  fig <- NULL
  if (!is.null(ef) && !is.null(ef$vectors)) {
    ss <- vegan::scores(mod, display = "sites", choices = 1:2)
    f1 <- pd_design_factors(cfg)[1]
    grp <- if (f1 %in% names(m)) m[[f1]] else rep("all", nrow(m))
    r2adj <- tryCatch(vegan::RsquareAdj(mod)$adj.r.squared, error = function(e) NA_real_)
    fig <- pd_capture_plot(
      pd_plot_rda_biplot(mod, ef, grp, ss, cfg = cfg, r2adj = r2adj, pval = pt_p),
      "rda_biplot", "42", width_mm = 180, height_mm = 130)
  }

  invisible(list(model = mod, envfit = ef, dca = dg,
                 envfit_table = ef_tab, figure = fig, method = method))
}
