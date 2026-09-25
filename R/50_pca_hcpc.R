# ============================================================
# 50_pca_hcpc.R · PCA 降维 + 层次聚类（HCPC）
# 依赖：FactoMineR ；factoextra（画图）
# ============================================================

pd_run_pca_hcpc <- function(cfg = .pd$cfg, dat = NULL, traits = NULL,
                            ncp = 5, save = TRUE, sig_traits = NULL) {
  if (!pd_require(c("FactoMineR"), "50_pca_hcpc")) return(invisible(NULL))
  dat <- dat %||% pd_load_data(cfg)
  pd_msg("")
  pd_msg("### 50 PCA + HCPC ###")

  tr <- traits %||% dat$traits
  if (is.null(tr)) {
    pd_msg("[50] 无性状表 → 缺数据只报告不动手，已跳过。")
    return(invisible(NULL))
  }
  tr <- as.data.frame(tr)
  rownames(tr) <- tr[[cfg$key$species]]; tr[[cfg$key$species]] <- NULL
  tr <- tr[, vapply(tr, is.numeric, logical(1)), drop = FALSE]
  na_cells <- sum(is.na(tr))
  if (na_cells > 0) {
    pd_msg(sprintf("[50] 性状表含 %d 个缺失 → 按行完整删除（如需插补请先跑 21_impute 并把结果作为 traits 传入）", na_cells))
    tr <- tr[stats::complete.cases(tr), , drop = FALSE]
  }
  keep <- vapply(tr, function(x) stats::sd(x, na.rm = TRUE) > 0, logical(1))
  if (!all(keep)) pd_msg(sprintf("[50] 剔除零方差性状 %d 个: %s", sum(!keep),
                                 paste(names(tr)[!keep], collapse = ", ")))
  tr <- tr[, keep, drop = FALSE]
  if (nrow(tr) < 5 || ncol(tr) < 2) { pd_warn("样本或性状过少，PCA 跳过"); return(invisible(NULL)) }
  pd_msg(sprintf("[50] PCA 输入：%d 物种 × %d 性状", nrow(tr), ncol(tr)))

  pca <- tryCatch(FactoMineR::PCA(tr, scale.unit = TRUE, graph = FALSE, ncp = min(ncp, ncol(tr))),
                  error = function(e) { pd_warn("PCA 失败: ", conditionMessage(e)); NULL })
  if (is.null(pca)) return(invisible(NULL))

  eig <- data.frame(axis = rownames(pca$eig), eigenvalue = round(pca$eig[, 1], 4),
                    pct_variance = round(pca$eig[, 2], 3),
                    cum_pct = round(pca$eig[, 3], 3), stringsAsFactors = FALSE)
  li <- as.data.frame(pca$var$coord)
  names(li) <- paste0("coord_", names(li))
  li <- cbind(trait = rownames(li), round(li, 4))
  ct <- as.data.frame(pca$var$contrib); names(ct) <- paste0("contrib_", names(ct))
  ct <- cbind(trait = rownames(ct), round(ct, 3))
  ind <- as.data.frame(pca$ind$coord); names(ind) <- paste0("Dim.", seq_len(ncol(ind)))
  ind <- cbind(species = rownames(ind), round(ind, 4))
  pd_msg(sprintf("[50] PC1+PC2 解释 %.1f%%（PC1 %.1f%%, PC2 %.1f%%）",
                 eig$cum_pct[2], eig$pct_variance[1], eig$pct_variance[2]))

  # ---- biplot ----
  # 仅为对齐论文图外观：配色 col.var=#0E5484 / col.ind=#6CBF59（PDF 实测）
  #   显示参：arrow.size=1, alpha.ind=0.7, alpha.var=0.7, labelsize=2, repel=TRUE
  #   Fig 6 变体：opts$pca_color_by="signal" 时按系统发育信号显著性着色
  #     显著 → pca_var_sig(#FF0000，实测纯红)；不显著 → pca_var_nosig(#000000)
  #     纯色彩映射，PCA 计算不动
  bi <- NULL
  if (pd_has("factoextra") && pd_has("ggplot2")) {
    col_var <- pd_pal("pca_var", cfg = cfg)[1]
    col_ind <- pd_pal("pca_ind", cfg = cfg)[1]
    color_by <- cfg$opts$pca_color_by %||% "none"
    if (identical(color_by, "signal")) {
      sig <- sig_traits %||% (cfg$opts$pca_sig_traits %||% character(0))
      if (length(sig)) {
        nms <- rownames(pca$var$coord)
        col_var <- ifelse(nms %in% sig,
                          pd_pal("pca_var_sig",   cfg = cfg)[1],
                          pd_pal("pca_var_nosig", cfg = cfg)[1])
        pd_msg(sprintf("[50] Fig 6 式着色：%d/%d 个性状标为有系统发育信号",
                       sum(nms %in% sig), length(nms)))
      } else {
        pd_msg("[50] pca_color_by='signal' 但未给 sig_traits / opts$pca_sig_traits，回退默认 biplot 色")
      }
    }
    bi <- tryCatch(factoextra::fviz_pca_biplot(pca, geom = "point",
                                               col.var = col_var, col.ind = col_ind,
                                               repel = TRUE, label = "var",
                                               labelsize = 2, addEllipses = FALSE,
                                               arrow.size = 1,
                                               alpha.ind = 0.7, alpha.var = 0.7) +
                     pd_theme() +
                     ggplot2::labs(x = sprintf("PC1 (%.1f%%)", eig$pct_variance[1]),
                                   y = sprintf("PC2 (%.1f%%)", eig$pct_variance[2])),
                   error = function(e) NULL)
    if (!is.null(bi)) {
      if (isTRUE(cfg$plot$save_singles))
        pd_save_pdf(bi, "pca_biplot", "50", size = "fig6_pca")   # 散件（检查用）
    }
    sc <- tryCatch(factoextra::fviz_eig(pca, addlabels = TRUE, barfill = "grey70") + pd_theme(),
                   error = function(e) NULL)
    if (!is.null(sc) && isTRUE(cfg$plot$save_singles))
      pd_save_pdf(sc, "pca_scree", "50", height_mm = 90)
    # ---- Fig 6 等价图：PCA biplot (a) + scree (b) 合成一张 ----
    #   scree 是 PCA 特征值信息，本属 PCA，不再单独出（消重复）
    if (!is.null(bi) && !is.null(sc)) {
      comp <- pd_compose(list(bi, sc), ncol = 1, tags = "a")
      pd_save_pdf(comp, "fig6_pca", "50", size = "fig6_pca")
    } else if (!is.null(bi)) {
      pd_save_pdf(bi, "fig6_pca", "50", size = "fig6_pca")
    }
    .pd$last_pca_biplot <- bi   # 保留作扩展（S3 已改为纯热图，不再用）
  }

  # ---- HCPC ----
  # ★★ 簇数（2026-09-25，批 5 默认①+②）
  #   opts$hcpc_nclust = "auto"（默认）→ nb.clust = -1，由 HCPC 按树高惯量拐点自动定；
  #   设整数（如 4）→ 先验指定（旧口径），并在日志里写明是先验值。
  hc <- NULL; hc_tab <- NULL
  nc_raw <- cfg$opts$hcpc_nclust %||% "auto"
  if (identical(nc_raw, "auto")) {
    nc <- -1L
    pd_msg("[50] HCPC 簇数 = auto（由惯量拐点自动定）")
  } else {
    nc <- as.integer(nc_raw)
    pd_msg(sprintf("[50] HCPC 簇数 = %d（【先验指定】，非数据驱动）", nc))
  }
  if (is.finite(nc) && (nc == -1L || (nc >= 2 && nc < nrow(tr)))) {
    hc <- tryCatch(FactoMineR::HCPC(pca, nb.clust = nc, graph = FALSE),
                   error = function(e) { pd_warn("HCPC 失败: ", conditionMessage(e)); NULL })
    if (!is.null(hc)) {
      cl <- hc$data.clust$clust
      nc_act <- length(unique(cl))
      hc_tab <- data.frame(species = rownames(hc$data.clust), cluster = as.integer(cl),
                           stringsAsFactors = FALSE)
      pd_msg(sprintf("[50] HCPC 完成：%d 簇，各簇大小 %s", nc_act,
                     paste(table(hc_tab$cluster), collapse = " / ")))
      # 惯量损失（便于报告）
      if (!is.null(hc$call))
        pd_msg(sprintf("[50] 簇间惯量占比 = %s",
                       paste(round(hc$call$bw.incr$inertia.before.graupe /
                                     sum(hc$call$bw.incr$inertia.before.graupe, na.rm = TRUE), 3),
                             collapse = " / ")))
    }
  }

  out <- list(pca = pca, eig = eig, loadings = li, contrib = ct,
              scores = ind, hcpc = hc_tab, input = tr, biplot = bi)  # biplot 供 S3 拼图
  if (save) pd_write_table(list(eigenvalues = eig, loadings = li, contributions = ct,
                                species_scores = ind,
                                hcpc_clusters = if (is.null(hc_tab)) data.frame() else hc_tab),
                           stem = "pca", module = "50")
  invisible(out)
}
