# ============================================================
# 51_heatmap.R · 热图（pheatmap）
#   (a) 物种 × 性状（z-score）
#   (b) 性状 × 性状（相关系数矩阵）
# 依赖：pheatmap
# ============================================================

pd_heat_device <- function(file, w_mm, h_mm, expr) {
  # 修复：原先选了 cairo_pdf 却调 pdf()，导致热图非 cairo 渲染
  dev <- if (.Platform$OS.type == "windows") grDevices::cairo_pdf else grDevices::pdf
  dev(file = file, width = w_mm / 25.4, height = h_mm / 25.4)
  on.exit(grDevices::dev.off(), add = TRUE)
  force(expr)
}

pd_run_heatmap <- function(cfg = .pd$cfg, dat = NULL, traits = NULL,
                           which = c("species_trait", "trait_trait"), save = TRUE) {
  if (!pd_require("pheatmap", "51_heatmap")) return(invisible(NULL))
  dat <- dat %||% pd_load_data(cfg)
  pd_msg("")
  pd_msg("### 51 热图 ###")

  tr <- traits %||% dat$traits
  if (is.null(tr)) {
    pd_msg("[51] 无性状表 → 缺数据只报告不动手，已跳过。")
    return(invisible(NULL))
  }
  tr <- as.data.frame(tr)
  rownames(tr) <- tr[[cfg$key$species]]; tr[[cfg$key$species]] <- NULL
  tr <- tr[, vapply(tr, is.numeric, logical(1)), drop = FALSE]
  tr <- tr[stats::complete.cases(tr), , drop = FALSE]
  keep <- vapply(tr, function(x) stats::sd(x, na.rm = TRUE) > 0, logical(1))
  tr <- tr[, keep, drop = FALSE]
  if (nrow(tr) < 3 || ncol(tr) < 2) { pd_warn("性状矩阵过小，51 跳过"); return(invisible(NULL)) }
  pd_msg(sprintf("[51] 输入：%d 物种 × %d 性状", nrow(tr), ncol(tr)))

  # 仅为对齐论文图外观：取色走 pd_pal("heatmap")（#3A558C/#ffffff/#75D155，与论文一致）
  #   字号对齐论文：fontsize_row=8, fontsize_col=6（矩阵小时）；大矩阵保留自适应回退
  col_fun <- grDevices::colorRampPalette(pd_pal("heatmap", cfg = cfg))(100)
  dist_m <- cfg$opts$pheatmap_dist %||% "euclidean"
  cl_m <- cfg$opts$pheatmap_method %||% "complete"
  files <- character(0); objs <- list()

  # (a) 物种 × 性状
  if ("species_trait" %in% which) {
    z <- scale(tr)
    z <- z[, apply(z, 2, function(x) all(is.finite(x))), drop = FALSE]
    # 单件照出（渲染必需）；合成 51_heatmaps 后按 save_singles 决定是否清理
    f <- file.path(cfg$paths$figures, "51_species_trait_heatmap.pdf")
    # 仅为对齐论文图外观 + 用户第 3 轮反馈：旧版字号过大过长、重叠、挤压热图
    #   显著下调；行名过长截断；物种多时直接不显示行名
    fs_row <- if (nrow(z) <= 30) 6 else 5
    fs_col <- 5
    if (!is.null(rownames(z))) rownames(z) <- substr(rownames(z), 1, 22)   # 长名截断，防重叠
    h_mm <- max(80, min(300, 4 + nrow(z) * 6 / 25.4 * 6))            # 论文 S4 为 180×80mm（扁）
    pheatmap_obj <- NULL
    p1 <- tryCatch({
      pd_heat_device(f, 180, h_mm, {
        # 用 <- 不用 <<-：该 block 的 promise 在 pd_run_heatmap 作用域求值，
        #   <<- 会跳过本地绑定跑到父环境 → pheatmap_obj 恒为 NULL（日志打印 NULL 的原因）
        pheatmap_obj <- pheatmap::pheatmap(
          z, color = col_fun, scale = "none",
          show_rownames = nrow(z) <= 60, show_colnames = TRUE,
          fontsize = 6, fontsize_row = fs_row,
          fontsize_col = fs_col, angle_col = 45,
          clustering_distance_rows = dist_m, clustering_method = cl_m,
          cluster_cols = FALSE, silent = TRUE)
        print(pheatmap_obj)
        pheatmap_obj
      })
      f
    }, error = function(e) { pd_warn("物种-性状热图失败: ", conditionMessage(e)); NULL })
    # pd_heat_device 的 expr 返回值即 pheatmap 对象（device 内 <- 的结果）
    if (is.list(pheatmap_obj) && !is.null(pheatmap_obj$gtable)) {
      # ok
    } else if (is.null(pheatmap_obj)) {
      # 回退：重新取一次（不重复画图，只重建对象）
      pheatmap_obj <- tryCatch(pheatmap::pheatmap(
        z, color = col_fun, scale = "none", silent = TRUE,
        show_rownames = nrow(z) <= 60, show_colnames = TRUE,
        fontsize = 6, fontsize_row = fs_row, fontsize_col = fs_col,
        angle_col = 45, clustering_distance_rows = dist_m, clustering_method = cl_m,
        cluster_cols = FALSE), error = function(e) NULL)
    }
    if (!is.null(p1)) { files <- c(files, p1); pd_msg("[fig] ", basename(p1)) }
    objs$species_trait_gtable <- if (!is.null(pheatmap_obj)) pheatmap_obj$gtable else NULL
  }

  # (b) 性状 × 性状
  if ("trait_trait" %in% which && ncol(tr) >= 3) {
    cors <- stats::cor(tr, use = "pairwise.complete.obs", method = "pearson")
    f2 <- file.path(cfg$paths$figures, "51_trait_trait_corr.pdf")
    side <- max(110, min(150, 60 + 2.2 * ncol(cors)))   # 缩小方阵边长，合成后不挤
    if (!is.null(colnames(cors))) colnames(cors) <- substr(colnames(cors), 1, 18)  # 长性状名截断
    if (!is.null(rownames(cors))) rownames(cors) <- substr(rownames(cors), 1, 18)
    pheatmap_obj2 <- NULL
    p2 <- tryCatch({
      pd_heat_device(f2, side, side, {
        pheatmap_obj2 <- pheatmap::pheatmap(     # <- 不是 <<-（见上）
          cors, color = col_fun, display_numbers = ncol(cors) <= 20,
          number_format = "%.2f", fontsize = 6,
          fontsize_number = 4.5, fontsize_row = 5, fontsize_col = 5,
          angle_col = 45,
          clustering_distance_rows = dist_m, clustering_method = cl_m,
          silent = TRUE)
        print(pheatmap_obj2)
        pheatmap_obj2
      })
      f2
    }, error = function(e) { pd_warn("性状-性状热图失败: ", conditionMessage(e)); NULL })
    if (is.null(pheatmap_obj2) || is.null(pheatmap_obj2$gtable))
      pheatmap_obj2 <- tryCatch(pheatmap::pheatmap(
        cors, color = col_fun, display_numbers = ncol(cors) <= 20,
        number_format = "%.2f", fontsize = 6,
        fontsize_number = 4.5, fontsize_row = 5, fontsize_col = 5,
        angle_col = 45,
        clustering_distance_rows = dist_m, clustering_method = cl_m,
        silent = TRUE), error = function(e) NULL)
    if (!is.null(p2)) files <- c(files, p2)
    objs$cor_matrix <- round(cors, 4)
    objs$trait_trait_gtable <- if (!is.null(pheatmap_obj2)) pheatmap_obj2$gtable else NULL
    # 显著相关对数
    n <- nrow(tr); rcrit <- stats::qt(1 - cfg$opts$alpha / 2, n - 2) / sqrt(n - 2 + stats::qt(1 - cfg$opts$alpha / 2, n - 2)^2)
    npair <- sum(abs(cors[upper.tri(cors)]) >= rcrit, na.rm = TRUE)
    pd_msg(sprintf("[51] 性状相关：%d/%d 对显著（|r| ≥ %.3f, n = %d）",
                   npair, ncol(tr) * (ncol(tr) - 1) / 2, rcrit, n))
  }

  # ---- Fig S3+S4 合一：性状-性状热图 (a) + 性状-物种热图 (b) ----
  #   用户已定「S3 最终是热图（不含 PCA）」—— PCA 只在 Fig 6 画一遍，不再重复
  #   两张都是性状热图（方阵 + 扁图），同类合成一张，写论文时裁开
  hm_a <- objs$trait_trait_gtable
  hm_b <- objs$species_trait_gtable
  if (!is.null(hm_a) && !is.null(hm_b) && pd_has("patchwork") && pd_has("ggplot2")) {
    comp <- tryCatch({
      pa <- patchwork::wrap_elements(full = hm_a)
      pb <- patchwork::wrap_elements(full = hm_b)
      pd_compose(list(pa, pb), ncol = 1, tags = "a", guides = "keep")
    }, error = function(e) { pd_warn("热图合成失败: ", conditionMessage(e)); NULL })
    if (!is.null(comp)) {
      f3 <- pd_save_pdf(comp, "heatmaps", "51", size = "heatmaps")
      if (!is.null(f3)) files <- c(files, f3)
      pd_msg("[51] Fig S3+S4 合一 → 51_heatmaps.pdf（2 面板）")
      # ★ 散图清理规则（用户：「如果拼图已经包括了散图，散图就可以删（冗余）。其他情况下不删」）
      #   两张散图已并入 51_heatmaps.pdf → 冗余，可删；先确认复合图落地且非空。
      if (!isTRUE(cfg$plot$save_singles)) {
        del <- files[grepl("51_species_trait_heatmap|51_trait_trait_corr", files)]
        if (length(del) && !is.null(f3) && file.exists(f3) && isTRUE(file.info(f3)$size > 0)) {
          unlink(del)
          pd_msg("[51] 散图已并入复合图，删除冗余散件 ", length(del), " 张")
          files <- files[!grepl("51_species_trait_heatmap|51_trait_trait_corr", files)]
        } else if (length(del)) {
          pd_warn("[51] 复合图未落地或为空，保留散件不删")
        }
      } else {
        pd_msg("[51] [save_singles=TRUE] 散件已保留")
      }
    }
  }

  out <- c(list(files = files, input = tr), objs)
  # 相关矩阵是 matrix，必须转 data.frame —— pd_write_table 对 matrix 会按 list 逐元素展开
  #   （写成一堆单格 sheet）。见 references/04-paper-tables.md
  if (save && !is.null(objs$cor_matrix))
    pd_write_table(as.data.frame(objs$cor_matrix), stem = "trait_corr", module = "51")
  invisible(out)
}
