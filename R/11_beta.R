# ============================================================
# 11_beta.R · β 多样性：距离矩阵 + 替换/嵌套分解
# 依赖：vegan；betapart（分解，可选）
# ============================================================

pd_run_beta <- function(cfg = .pd$cfg, dat = NULL, save = TRUE) {
  if (!pd_require("vegan", "11_beta")) return(invisible(NULL))
  dat <- dat %||% pd_load_data(cfg)
  pd_msg("")
  pd_msg("### 11 β 多样性 ###")

  ab <- dat$abundance
  methods <- cfg$response$beta %||% c("bray", "jaccard")
  dists <- pd_beta_distances(ab, methods)

  res <- list(distances = dists)

  # ---- 替换 vs 嵌套分解（betapart） ----
  if (isTRUE(cfg$opts$beta_partition)) {
    if (!pd_has("betapart")) {
      pd_warn("需要 betapart 才能做 turnover/nestedness 分解，已跳过（install.packages(\"betapart\")）")
    } else {
      pa <- ifelse(ab > 0, 1, 0)
      bp <- tryCatch(betapart::beta.pair(pa, index.family = "sorensen"),
                     error = function(e) NULL)
      if (is.null(bp)) {
        pd_warn("beta.pair 计算失败")
      } else {
        res$beta_partition <- bp
        # 拆成"组间平均"的汇总：整体 + 两两分组均值
        summ <- data.frame(component = c("turnover(beta.sim)", "nestedness(beta.sne)", "total(beta.sor)"),
                           overall_mean = round(c(mean(bp$beta.sim), mean(bp$beta.sne), mean(bp$beta.sor)), 4),
                           stringsAsFactors = FALSE)
        f1 <- cfg$design$factors[1]
        if (length(f1) && f1 %in% names(dat$meta)) {
          g <- factor(dat$meta[[f1]][match(rownames(ab), dat$meta[[cfg$key$sample_id]])])
          for (comp in c("beta.sim", "beta.sne", "beta.sor")) {
            m <- as.matrix(bp[[comp]]); diag(m) <- NA
            gm <- tapply(seq_along(g), g, function(i) mean(m[i, i], na.rm = TRUE))
            for (lv in names(gm)) summ[[paste0(comp, "_", lv)]] <- round(gm[[lv]], 4)
          }
        }
        res$partition_summary <- summ
        pd_msg(sprintf("[11] 分解完成：turnover=%.3f, nestedness=%.3f, total=%.3f",
                       mean(bp$beta.sim), mean(bp$beta.sne), mean(bp$beta.sor)))
        if (save) {
          pd_write_matrix(as.matrix(bp$beta.sim), "beta_sim_turnover", "11")
          pd_write_matrix(as.matrix(bp$beta.sne), "beta_sne_nestedness", "11")
        }
      }
    }
  }

  if (save) {
    for (m in names(dists)) pd_write_matrix(dists[[m]], paste0("dist_", m), "11")
    if (!is.null(res$partition_summary))
      pd_write_table(res$partition_summary, stem = "partition", module = "11")
  }
  pd_msg("[11] 完成")
  invisible(res)
}
