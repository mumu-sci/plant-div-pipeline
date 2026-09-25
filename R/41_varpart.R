# ============================================================
# 41_varpart.R · 方差分解（vegan::varpart）
# 关键口径：分类因子必须哑变量化（dummy），不能当连续变量
#   coding = "dummy"（推荐/默认） | "numeric"（复现旧的连续编码口径）
# 注意：vegan::varpart 需要 2~4 个解释表，不能只给 1 个
#       （曾因单表调用报 "needs two to four explanatory tables"）
# ============================================================

pd_dummy <- function(x) {
  x <- factor(x)
  m <- stats::model.matrix(~ x)
  m <- m[, colnames(m) != "(Intercept)", drop = FALSE]   # 丢掉参照水平，避免与截距共线（否则 rda 报 aliased）
  colnames(m) <- sub("^x", "", colnames(m))
  m
}

# 单个解释集合的"单独"解释量
# 群落矩阵：用 RDA + RsquareAdj，与 varpart 内部模型保持一致
#   （曾用 capscale(distance="bray")，与 varpart 的 RDA 口径不一致 → 同表内两个数字来自两套模型）
# 向量：用 lm
pd_r2_alone <- function(Y, X, distance = "bray") {
  if (is.null(dim(Y))) {
    d <- data.frame(y = as.numeric(Y))
    m <- tryCatch(stats::lm(y ~ X, data = d), error = function(e) NULL)
    if (is.null(m)) return(NA_real_)
    return(summary(m)$adj.r.squared)
  }
  m <- tryCatch(vegan::rda(Y, X), error = function(e) NULL)
  if (is.null(m)) return(NA_real_)
  z <- tryCatch(vegan::RsquareAdj(m)$adj.r.squared, error = function(e) NA_real_)
  if (length(z)) z[1] else NA_real_
}

pd_run_varpart <- function(cfg = .pd$cfg, dat = NULL, response = "community",
                           vars = NULL, coding = NULL, save = TRUE) {
  if (!pd_require("vegan", "41_varpart")) return(invisible(NULL))
  dat <- dat %||% pd_load_data(cfg)
  pd_msg("")
  pd_msg("### 41 方差分解 ###")

  coding <- coding %||% cfg$opts$varpart_coding %||% "dummy"
  dist_m <- cfg$opts$distance %||% "bray"
  sets <- cfg$design$factors[cfg$design$factors %in% names(dat$meta)]
  if (length(sets) < 2) {
    pd_warn("方差分解需要 ≥ 2 组解释变量（config$design$factors）。已跳过。")
    return(invisible(NULL))
  }
  id <- cfg$key$sample_id
  mt <- dat$meta
  mt <- mt[match(rownames(dat$abundance), as.character(mt[[id]])), , drop = FALSE]

  # ★★ 列联表平衡性 / 共线性检查（2026-09-25，批 5 默认②只提示）
  #   不平衡设计下两组解释量的「共同部分」（shared fraction）会虚高或分配任意。
  if (length(sets) >= 2) {
    tab <- tryCatch(table(mt[[sets[1]]], mt[[sets[2]]]), error = function(e) NULL)
    if (!is.null(tab)) {
      z <- sum(tab == 0)
      if (z > 0)
        pd_warn(sprintf("列联表 %s × %s 有 %d 个空格（%d/%d 组合缺失）→ 不平衡设计，",
                        sets[1], sets[2], z, z, length(tab)),
                "varpart 的 shared fraction 会虚高/任意分配，正文须说明")
      else pd_msg(sprintf("[41] 列联表 %s × %s 完全平衡（每格 n=%d）", sets[1], sets[2], tab[1]))
    }
    if (pd_has("vegan")) {
      Xd <- do.call(cbind, lapply(sets, function(f) pd_dummy(mt[[f]])))
      v <- tryCatch(vegan::vif.cca(vegan::rda(rep(0, nrow(Xd)), Xd)), error = function(e) NULL)
      if (!is.null(v)) {
        hi <- names(v)[v > 10]
        if (length(hi))
          pd_warn("解释变量共线性高（VIF>10）：", paste(hi, collapse = ", "),
                  " → 共享方差会被算进 shared fraction")
        else pd_msg(sprintf("[41] VIF 最大 %.1f（<10，无严重共线）", max(v)))
      }
    }
  }

  # 群落矩阵先做 Hellinger 转换（Legendre & Gallagher 2001），否则 varpart 内部按原始多度做 RDA，
  # 与 Bray-Curtis 体系不匹配，且 Habitat/Season 的相对重要性会翻转（见代码审查 P1）
  ytrans <- cfg$opts$varpart_community_transform %||% "hellinger"
  make_Y <- function(r) {
    if (identical(r, "community")) {
      m <- dat$abundance
      if (identical(ytrans, "hellinger")) m <- vegan::decostand(m, "hellinger")
      return(m)
    }
    if (r %in% names(mt)) return(mt[[r]])
    # ★ 别名解析（2026-09-25）：config 写的是论文名（F.Ric / mntd / mpd），
    #   而 20_fd 输出 FRic/FEve/FDiv、31 输出 NTI_obs/NRI_obs —— 对不上会【静默跳过】。
    #   复用 60_plots 的 pd_match_var；找不到就明确报警，不造数。
    alt <- ""
    if (exists("pd_match_var", mode = "function"))
      alt <- tryCatch(pd_match_var(r, names(mt)), error = function(e) "")
    if (!is.null(alt) && nzchar(alt[1]) && alt[1] %in% names(mt)) {
      pd_msg(sprintf("[41] %s → 实际列 %s（别名解析）", r, alt[1]))
      return(mt[[alt[1]]])
    }
    NULL
  }
  Ys <- unique(c("community", vars %||% c(cfg$response$alpha, cfg$response$func, cfg$response$phylo)))
  Ys <- Ys[!is.na(Ys)]

  Xs <- lapply(sets, function(f) {
    if (identical(coding, "dummy")) pd_dummy(mt[[f]])
    else matrix(as.numeric(factor(mt[[f]])), ncol = 1, dimnames = list(NULL, f))
  })
  names(Xs) <- sets

  call_vp <- function(Y, Xlist) {     # 第一个解释矩阵必须命名为 X
    args <- Xlist
    names(args)[1] <- "X"
    do.call(vegan::varpart, c(list(Y = Y), args))
  }

  rows <- list(); frac_rows <- list(); ind_rows <- list(); vp_list <- list()
  for (r in Ys) {
    Y <- make_Y(r)
    if (is.null(Y)) {
      pd_warn("41 跳过响应 ", r, "：meta 里没有该列（或别名）。meta 实有数值列 = ",
              paste(intersect(names(mt), unique(c(cfg$response$alpha, cfg$response$func,
                                                  cfg$response$phylo, cfg$response$community))),
                    collapse = ", "))
      next
    }
    if (is.vector(Y)) {
      ok <- !is.na(Y); if (sum(ok) < 10) next
      Yv <- Y[ok]; Xv <- lapply(Xs, function(m) m[ok, , drop = FALSE])
    } else {
      Yv <- Y; Xv <- Xs
    }
    vp <- tryCatch(call_vp(Yv, Xv),
                   error = function(e) { pd_warn("varpart 失败（", r, "）: ", conditionMessage(e)); NULL })
    if (is.null(vp)) next
    vp_list[[r]] <- vp

    fr <- as.data.frame(vp$part$fract); fr$response <- r; fr$fraction <- rownames(fr)
    frac_rows[[r]] <- fr
    ind <- tryCatch(as.data.frame(vp$part$indfract), error = function(e) NULL)
    if (!is.null(ind)) { ind$response <- r; ind$fraction <- rownames(ind); ind_rows[[r]] <- ind }

    for (f in sets) {
      rows[[length(rows) + 1]] <- data.frame(
        response = r, explanatory_set = f, coding = coding,
        adj_R2_alone = round(pd_r2_alone(Yv, Xv[[f]], dist_m), 4),
        n_explanatory_sets = length(sets),
        stringsAsFactors = FALSE)
    }
    uni <- if (!is.null(ind)) ind$Adj.R.squared[grep("\\|", ind$fraction)] else numeric(0)
    shr <- if (!is.null(ind)) {
      z <- ind$Adj.R.squared[grep("\u2229|Shared|shared", ind$fraction)]
      if (!length(z) && nrow(ind) >= 3) z <- ind$Adj.R.squared[3]   # varpart 的 [c] 行
      z
    } else numeric(0)
    pd_msg(sprintf("[41] %-9s 唯一解释量 adj.R2 = [%s]；共同 = [%s]（coding = %s，%s 距离）",
                   r,
                   if (!length(uni)) "NA" else paste(round(uni, 3), collapse = ", "),
                   if (!length(shr)) "NA" else paste(round(shr, 3), collapse = ", "),
                   coding, dist_m))
  }
  if (!length(rows)) { pd_warn("方差分解无结果"); return(invisible(NULL)) }
  contrib <- do.call(rbind, rows); rownames(contrib) <- NULL
  frac <- do.call(rbind, frac_rows); rownames(frac) <- NULL
  indf <- if (length(ind_rows)) do.call(rbind, ind_rows) else data.frame()
  rownames(indf) <- NULL
  cat("\n--- 方差分解：各集合「单独」解释量（Adj.R2）---\n"); print(contrib)

  # ---- Venn 图 ----
  # [第 3 轮删除] 用户决定删除 stats_tests_panel 及其组成图代码。
  #   varpart 的数值结果仍在 contributions / fractions / individual 三张表里。
  #   要看 Venn 可临时恢复：plot(vp, bg = c("hotpink","skyblue"))。

  out <- list(contributions = contrib, fractions = frac, individual = indf,
              coding = coding, sets = sets, distance = dist_m)
  if (save) pd_write_table(list(explained_alone = contrib, fractions = frac,
                                individual_fractions = indf,
                                run_info = data.frame(
                                  item = c("解释变量集合", "编码方式", "响应变量", "群落矩阵转换",
                                           "说明"),
                                  value = c(paste(sets, collapse = " + "), coding,
                                            paste(unique(contrib$response), collapse = ", "),
                                            ytrans,
                                            "community 用 Hellinger 转换后的 RDA；向量响应用 lm。两者与 varpart 内部模型一致。"),
                                  stringsAsFactors = FALSE)),
                           stem = paste0("varpart_", coding), module = "41")
  invisible(out)
}
