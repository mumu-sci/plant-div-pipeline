# ============================================================
# 21_impute.R · 性状缺失插补（missForest）
# 依赖：missForest
# 纪律：插补是"生成数据"，必须显式请求；结果单独存放，不自动流入下游
# ============================================================

pd_run_impute <- function(cfg = .pd$cfg, dat = NULL, traits = NULL, save = TRUE) {
  if (!pd_require("missForest", "21_impute")) return(invisible(NULL))
  dat <- dat %||% pd_load_data(cfg)
  pd_msg("")
  pd_msg("### 21 性状缺失插补（missForest）###")

  traits <- traits %||% dat$traits
  if (is.null(traits)) { pd_warn("无性状表，21 跳过"); return(invisible(NULL)) }
  sp_col <- cfg$key$species
  tr <- as.data.frame(traits)
  rownames(tr) <- tr[[sp_col]]; tr[[sp_col]] <- NULL
  tr <- tr[, vapply(tr, is.numeric, logical(1)), drop = FALSE]

  na_before <- colSums(is.na(tr))
  if (sum(na_before) == 0) {
    pd_msg("[21] 性状表无缺失值，无需插补。")
    return(invisible(list(imputed = tr, report = data.frame())))
  }
  pd_msg(sprintf("[21] 缺失情况：共 %d 个缺失 / %d 个格子（%.1f%%）",
                 sum(na_before), length(as.matrix(tr)),
                 100 * sum(na_before) / length(as.matrix(tr))))
  drop_cols <- names(na_before)[na_before == nrow(tr)]
  # ★★ 缺失率上限（2026-09-25，批 5 默认①）
  #   随机森林插补是向【条件均值】收缩 → 会压缩性状方差，
  #   FRic（凸包体积）被系统性低估、RaoQ/FDis 偏小。缺失越多失真越重。
  #   opts$impute_max_miss（默认 0.5）：单个性状缺失率 > 50% 就剔除，不硬插。
  mm <- cfg$opts$impute_max_miss %||% 0.5
  if (is.finite(mm) && mm < 1) {
    hi <- names(na_before)[na_before / nrow(tr) > mm & na_before < nrow(tr)]
    if (length(hi)) {
      pd_msg(sprintf("[21] %d 个性状缺失率 > %.0f%%，剔除不插补（避免 FRic/RaoQ 被过度压缩）: %s",
                     length(hi), 100 * mm, paste(hi, collapse = ", ")))
      drop_cols <- c(drop_cols, hi)
    }
  }
  if (length(drop_cols)) {
    pd_msg(sprintf("[21] 剔除性状 %d 个: %s", length(drop_cols), paste(drop_cols, collapse = ", ")))
    tr <- tr[, !names(tr) %in% drop_cols, drop = FALSE]
  }
  if (ncol(tr) < 2) { pd_warn("可用性状 < 2，无法插补"); return(invisible(NULL)) }

  set.seed(cfg$opts$seed %||% 20260101)
  # missForest 是本模块的耗时点 → 包缓存（改样式后重跑走 cache，不重插补）
  im <- pd_cached("21_missForest", NULL, {
    tryCatch(missForest::missForest(as.data.frame(tr), verbose = FALSE),
             error = function(e) { pd_warn("missForest 失败: ", conditionMessage(e)); NULL })
  }, cfg = cfg)
  if (is.null(im)) return(invisible(NULL))

  # ★ 列名对齐取值（2026-09-25）：旧写法按 names(na_before) 位置索引，
  #   被剔除的全缺失列在 im$ximp 里【根本不存在】→ 取到 NA 再被置 0 →
  #   被误报成「插补了 nrow(tr) 个」，实际是整列剔除、一个都没插。
  after <- colSums(is.na(im$ximp))
  report <- data.frame(
    trait = names(na_before),
    missing_before = as.integer(na_before),
    still_missing_after = as.integer(after[names(na_before)]),
    status = ifelse(names(na_before) %in% drop_cols, "dropped_all_missing",
                    ifelse(names(na_before) %in% names(after), "imputed", "not_in_output")),
    stringsAsFactors = FALSE)
  # 被剔除的列：没有插补，imputed = 0
  dropped <- report$status == "dropped_all_missing"
  report$still_missing_after[dropped] <- report$missing_before[dropped]
  report$still_missing_after[report$status == "not_in_output"] <- NA_integer_
  report$imputed <- report$missing_before - report$still_missing_after
  report$imputed[dropped] <- 0L
  # ★★ NRMSE 接受阈值（2026-09-25，批 5 默认①）
  #   OOB NRMSE 越大插补越不可靠。opts$impute_max_nrmse（默认 0.3）超了就醒目警告。
  oob <- tryCatch(as.numeric(im$OOBerror), error = function(e) NA_real_)
  nrmse <- if (length(oob)) max(oob, na.rm = TRUE) else NA_real_
  pd_msg(sprintf("[21] 插补完成：NRMSE(OOB) = %s",
                 paste(sprintf("%s=%.4f", names(im$OOBerror), round(as.numeric(im$OOBerror), 4)),
                       collapse = ", ")))
  if (is.finite(nrmse) && nrmse > (cfg$opts$impute_max_nrmse %||% 0.3))
    pd_warn(sprintf(paste0("OOB NRMSE = %.3f > %.2f → 插补可靠性低。",
                           "FRic/RaoQ/FDis 会被系统性压缩（向条件均值收缩），",
                           "请在 Methods 声明并做「插补 vs 原始」敏感性分析"),
                    nrmse, cfg$opts$impute_max_nrmse %||% 0.3))

  # 插补前后分布对照（只对缺失最多的 4 个性状画）
  figs <- NULL
  top <- head(report$trait[order(-report$missing_before)], 4)
  if (length(top) && pd_has("ggplot2")) {
    pl <- lapply(top, function(v) {
      d <- rbind(data.frame(value = tr[[v]], type = "original", stringsAsFactors = FALSE),
                 data.frame(value = im$ximp[[v]], type = "imputed", stringsAsFactors = FALSE))
      ggplot2::ggplot(d, ggplot2::aes(x = value, fill = type)) +
        ggplot2::geom_histogram(position = "identity", alpha = 0.5, bins = 20) +
        ggplot2::labs(x = v, y = "count", fill = "") +
        pd_theme() + ggplot2::theme(legend.position = "top")
    })
    p <- patchwork::wrap_plots(pl, ncol = 2)
    # impute 单件仅 save_singles=TRUE 时出；否则由 pd_run_diagnostics() 合成
    figs <- if (isTRUE(cfg$plot$save_singles))
              pd_save_pdf(p, "impute_check", "21", height_mm = 150) else NULL
    .pd$last_impute <- p   # 供 pd_run_diagnostics() 合成 01_data_diagnostics
  }

  out <- list(imputed = im$ximp, report = report, oob = im$OOBerror)
  if (save) {
    pd_write_table(report, stem = "impute_report", module = "21")
    utils::write.csv(im$ximp, file.path(cfg$paths$results, "21_traits_imputed.csv"),
                     row.names = TRUE, fileEncoding = "UTF-8")
    pd_msg("[21] 插补后性状表已存 results/21_traits_imputed.csv（不自动流入下游，需要时在 config 指定）")
  }
  invisible(out)
}
