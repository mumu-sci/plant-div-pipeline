# ============================================================
# 10_alpha.R · α 多样性（物种水平）
# 依赖：vegan
# 输出：results/10_alpha_indices.xlsx, results/10_alpha_*.rds(距离矩阵单独存)
# ============================================================

pd_calc_alpha <- function(abund, rarefy = FALSE, seed = 20260101) {
  stopifnot(is.matrix(abund))
  if (!pd_has("vegan")) { pd_warn("需要 vegan，10_alpha 跳过"); return(NULL) }
  S <- vegan::specnumber(abund)
  Shannon <- vegan::diversity(abund, index = "shannon")
  Simpson <- vegan::diversity(abund, index = "simpson")
  Pielou <- ifelse(S > 1, Shannon / log(S), NA_real_)
  out <- data.frame(sample_id = rownames(abund),
                    S = as.integer(S),
                    Shannon = round(Shannon, 4),
                    Simpson = round(Simpson, 4),
                    Pielou = round(Pielou, 4),
                    N_total = rowSums(abund),
                    stringsAsFactors = FALSE)
  if (rarefy) {
    cnt <- as.matrix(abund)
    integerish <- all(abs(cnt - round(cnt)) < 1e-8)
    if (!integerish) {
      pd_warn("多度矩阵不是整数计数（是重要值/盖度等连续值）→ vegan::rarefy 不可用，已跳过稀释。",
              "如需稀释，请另备个体计数矩阵。")
    } else {
      nmin <- min(rowSums(cnt))
      # ★ 无需 set.seed（2026-09-25）：vegan::rarefy 是【解析期望值】，无随机性，set.seed 是多余的
      r <- vegan::rarefy(cnt, sample = as.integer(nmin))
      out$S_rarefy <- as.numeric(r)
      out$rarefy_n <- as.integer(nmin)
      pd_msg(sprintf("[10] 稀释到 %d 个体计算 S_rarefy", as.integer(nmin)))
    }
  }
  rownames(out) <- out$sample_id
  out
}

pd_beta_distances <- function(abund, methods = c("bray", "jaccard", "kulczynski"), cfg = .pd$cfg) {
  if (!pd_has("vegan")) return(NULL)
  # ★★ Jaccard 口径（2026-09-25，pitfalls I16）
  #   vegdist("jaccard") 默认给【定量 Jaccard（Ružička）】，与常写的定性 Jaccard 数值不同
  #   （实测两口径最大差 0.48）。opts$jaccard_binary=TRUE（默认）→ binary=TRUE 定性版；
  #   FALSE = 旧口径定量版（Methods 需写明 "quantitative Jaccard"）。
  jb <- cfg$opts$jaccard_binary %||% TRUE
  out <- list()
  for (m in methods) {
    bin <- identical(m, "jaccard") && isTRUE(jb)
    d <- tryCatch(vegan::vegdist(abund, method = m, binary = bin),
                  error = function(e) NULL)
    if (is.null(d)) { pd_warn("距离计算失败: ", m); next }
    mat <- as.matrix(d)
    attr(mat, "pd_binary") <- bin
    out[[m]] <- mat
  }
  out
}

pd_run_alpha <- function(cfg = .pd$cfg, dat = NULL, save = TRUE) {
  if (!pd_require("vegan", "10_alpha")) return(invisible(NULL))
  dat <- dat %||% pd_load_data(cfg)
  pd_msg("")
  pd_msg("### 10 α 多样性 ###")

  rare <- isTRUE(cfg$opts$rarefy %||% FALSE)
  if (rare) {
    rng <- range(rowSums(dat$abundance))
    if (rng[2] / max(1, rng[1]) > 2)
      pd_msg(sprintf("[10] 个体/重要值总量差异 > 2 倍（%.0f ~ %.0f）；config$opts$rarefy = TRUE，将尝试稀释（见 01-method-menu §10）",
                     rng[1], rng[2]))
    else
      pd_msg("[10] config$opts$rarefy = TRUE，但总量差异 < 2 倍，稀释意义有限")
  }
  alpha <- pd_calc_alpha(dat$abundance, rarefy = rare)

  # 距离矩阵：单独保存（不并入结果总表，见 pitfalls D3）
  dists <- pd_beta_distances(dat$abundance, cfg$response$beta %||% c("bray", "jaccard"), cfg = cfg)

  # ★★ 口径声明（2026-09-25，pitfalls I21）—— 统计口径写进 run_info，不靠记
  n_tot <- rowSums(dat$abundance, na.rm = TRUE)
  is_iv <- isTRUE(cfg$opts$abundance_is_iv %||% FALSE) ||
    (isTRUE(cfg$opts$na_to_zero) && max(n_tot) <= 1.01 && min(n_tot) >= 0)   # 各行和≈1 → 像重要值
  run_info <- data.frame(
    item = c("Shannon 口径", "Simpson 口径", "Pielou 口径", "N_total 含义",
             "输入数据类型", "rarefy", "稀释深度", "Jaccard 口径"),
    value = c("vegan::diversity 'shannon'（自然对数 ln）",
              "vegan::diversity 'simpson' = 1 - Σp²（Gini-Simpson），【不是】D 或 1/D",
              "H' / ln(S)，S<=1 时 NA",
              if (is_iv) "行和=重要值合计，不是个体数" else "rowSums(abundance)",
              if (is_iv) "重要值（连续）" else "个体计数 / 多度",
              as.character(rare),
              if (rare) sprintf("min(rowSums) = %.0f", min(n_tot)) else "-",
              if (isTRUE(cfg$opts$jaccard_binary %||% TRUE))
                "定性 Jaccard（binary=TRUE，存在-缺失）" else
                "定量 Jaccard / Ružička（binary=FALSE）"),
    stringsAsFactors = FALSE)

  if (save) {
    pd_write_table(list(indices = alpha, run_info = run_info), stem = "indices", module = "10")
    for (m in names(dists)) pd_write_matrix(dists[[m]], paste0("dist_", m), "10")
  }
  pd_msg(sprintf("[10] 完成：%d 样方，Shannon 范围 %.2f ~ %.2f",
                 nrow(alpha), min(alpha$Shannon), max(alpha$Shannon)))
  invisible(list(alpha = alpha, distances = dists))
}
