# ============================================================
# 20_fd.R · 功能多样性（FD::dbFD）+ 功能β多样性（betapart）
# 依赖：FD；betapart（功能β，可选）
# 关键纪律：性状来源必须在 config$opts$trait_input 声明，混用不可比（pitfalls C3）
# ============================================================

# ------------------------------------------------------------
# 20.1 功能β 的快速替代路线：性状空间分格 → 功能实体 → Baselga β
#   为什么需要它：betapart::functional.betapart.core 内部要对**所有样方两两**做凸包交叠，
#   实测 180 样方（16110 对）>10 分钟未完成；即使只取 20 个样方（190 对）10 分钟也跑不完，
#   外推到 180 样方需十几小时 —— 在本数据规模下不可行。
#   替代做法（Villéger 等的"功能实体"思路）：
#     对标准化性状做 PCA → 在前 k 个主轴的分位数网格上把物种分成"功能实体"
#     → 样方 × 功能实体 的存在/缺失矩阵 → betapart::beta.pair（Sørensen）
#   假设：同一网格单元内的物种功能等价。网格数 n_cells 可调，结果对它有依赖，需在 Methods 说明。
# ------------------------------------------------------------
pd_func_beta_traitspace <- function(pa, tr, n_cells = 4, n_axes = 3) {
  if (!pd_has("betapart")) return(NULL)
  pc <- stats::prcomp(tr, center = TRUE, scale. = TRUE)
  k <- min(as.integer(n_axes), ncol(pc$x))
  sc <- pc$x[, 1:k, drop = FALSE]
  bins <- lapply(seq_len(k), function(j) {
    q <- stats::quantile(sc[, j], probs = seq(0, 1, length.out = n_cells + 1), na.rm = TRUE)
    q[1] <- -Inf; q[length(q)] <- Inf
    q <- unique(q)
    if (length(q) < 3) return(rep(1L, nrow(sc)))
    as.integer(cut(sc[, j], breaks = q, labels = FALSE, include.lowest = TRUE))
  })
  cell <- do.call(paste, c(bins, list(sep = "_")))
  names(cell) <- rownames(sc)
  lv <- sort(unique(cell))
  m <- matrix(0L, nrow = nrow(pa), ncol = length(lv), dimnames = list(rownames(pa), lv))
  for (i in seq_len(nrow(pa))) {
    sp <- colnames(pa)[pa[i, ] > 0]
    cc <- unique(cell[sp]); cc <- cc[!is.na(cc)]
    if (length(cc)) m[i, cc] <- 1L
  }
  m <- m[, colSums(m) > 0, drop = FALSE]
  bp <- tryCatch(betapart::beta.pair(m, index.family = "sorensen"), error = function(e) NULL)
  list(matrix = m, beta_pair = bp, n_cells = n_cells, n_axes = k,
       n_entities = ncol(m),
       note = sprintf("trait-space grid: %d axes x %d bins -> %d functional entities",
                      k, n_cells, ncol(m)))
}

pd_run_fd <- function(cfg = .pd$cfg, dat = NULL, traits = NULL, save = TRUE) {
  if (!pd_require(c("FD"), "20_fd")) return(invisible(NULL))
  dat <- dat %||% pd_load_data(cfg)
  pd_msg("")
  pd_msg("### 20 功能多样性 ###")

  if (is.null(traits)) {
    if (is.null(dat$traits)) {
      pd_msg("[20] 未提供性状表（config$files$traits）。")
      pd_msg("[20] 纪律：缺数据只报告不动手 —— 请确认性状表来源后再跑。已跳过。")
      return(invisible(NULL))
    }
    traits <- dat$traits
  }
  sp_col <- cfg$key$species
  traits <- as.data.frame(traits)
  rownames(traits) <- traits[[sp_col]]
  traits[[sp_col]] <- NULL
  traits <- traits[, vapply(traits, is.numeric, logical(1)), drop = FALSE]

  ab <- dat$abundance
  common <- intersect(colnames(ab), rownames(traits))
  only_ab <- setdiff(colnames(ab), rownames(traits))
  only_tr <- setdiff(rownames(traits), colnames(ab))
  pd_msg(sprintf("[20] 物种对齐：多度 %d / 性状 %d → 交集 %d", ncol(ab), nrow(traits), length(common)))
  if (length(only_ab)) pd_msg(sprintf("[20]   不在性状表（将不参与 FD）：%d 个 —— %s",
                                      length(only_ab), paste(head(only_ab, 10), collapse = ", ")))
  if (length(only_tr)) pd_msg(sprintf("[20]   不在多度矩阵（不参与）：%d 个 —— %s",
                                      length(only_tr), paste(head(only_tr, 10), collapse = ", ")))
  if (length(common) < 3) { pd_warn("交集物种 < 3，无法计算 FD。已跳过。"); return(invisible(NULL)) }

  # 性状来源标记（口径可追溯）
  src <- cfg$opts$trait_input %||% "raw"
  pd_msg(sprintf("[20] 性状来源 = %s | 性状数 = %d", src, ncol(traits)))

  tr <- traits[common, , drop = FALSE]
  na_traits <- sum(is.na(tr))
  if (na_traits > 0) {
    pd_warn(sprintf("性状表含 %d 个缺失值。dbFD 会剔除含缺失的物种（可用 21_impute 先插补）。", na_traits))
  }
  a <- ab[, common, drop = FALSE]
  # dbFD 要求至少 1 个性状且性状间无完全共线
  keep_tr <- vapply(tr, function(x) stats::sd(x, na.rm = TRUE) > 0 &&
                      sum(!is.na(x)) >= 3, logical(1))
  if (!all(keep_tr)) {
    pd_msg(sprintf("[20] 剔除零方差/过少观测的性状 %d 个: %s", sum(!keep_tr),
                   paste(names(tr)[!keep_tr], collapse = ", ")))
    tr <- tr[, keep_tr, drop = FALSE]
  }
  if (ncol(tr) < 1) { pd_warn("无可用性状，跳过。"); return(invisible(NULL)) }

  nsp <- rowSums(a > 0)
  pd_msg(sprintf("[20] 各样方物种数：min=%d，median=%d，max=%d；性状数=%d",
                 min(nsp), as.integer(stats::median(nsp)), max(nsp), ncol(tr)))

  # ★★ FRic 的 S > T 约束【事前预检】（2026-09-25，pitfalls I11）
  #   dbFD 要求「每个样方物种数 > 凸包维数」。旧写法是算完看 FRic 有没有 NA 才告警，
  #   性状多（如 37 个）时多数样方 FRic=NA、结果表大面积缺失。
  #   现在：不满足就自动把 PCoA 轴数 m 降到 min(nsp)-1，或明确提示减性状。
  m_arg <- "max"
  min_nsp <- min(nsp, na.rm = TRUE)
  if (min_nsp <= ncol(tr)) {
    m_try <- max(1L, min_nsp - 1L)
    pd_warn(sprintf(paste0("FRic 预检：最小样方物种数 %d <= 性状数 %d → 凸包会大面积 NA。",
                           "自动把 dbFD(m=) 降到 %d 个 PCoA 轴；",
                           "若仍不够请减少性状数（建议 <= %d）或改用 FD 的 RaoQ/FDis"),
                    min_nsp, ncol(tr), m_try, min_nsp - 1L))
    m_arg <- m_try
  }

  fd <- tryCatch(FD::dbFD(x = tr, a = as.matrix(a), calc.FRic = TRUE, calc.FDiv = TRUE,
                          calc.CWM = TRUE, stand.x = TRUE, messages = FALSE,
                          m = m_arg),
                 error = function(e) { pd_warn("dbFD 失败: ", conditionMessage(e)); NULL },
                 warning = function(w) {
                   pd_msg("[20] dbFD 警告: ", conditionMessage(w))
                   suppressWarnings(FD::dbFD(x = tr, a = as.matrix(a), calc.FRic = TRUE,
                                             calc.FDiv = TRUE, calc.CWM = TRUE,
                                             stand.x = TRUE, messages = FALSE, m = m_arg))
                 })
  if (is.null(fd)) return(invisible(NULL))

  na_fric <- if (is.null(fd$FRic)) nrow(a) else sum(is.na(fd$FRic))
  if (na_fric > 0)
    pd_warn(sprintf("FRic 在 %d/%d 个样方为 NA —— dbFD 要求样方内物种数 > 性状数（当前性状 %d 个）。"
                    , na_fric, nrow(a), ncol(tr)))
  na_feve <- if (is.null(fd$FEve)) nrow(a) else sum(is.na(fd$FEve))
  if (na_feve > 0)
    pd_warn(sprintf("FEve 在 %d/%d 个样方为 NA（样方内物种数 < 3 时不可算）", na_feve, nrow(a)))

  grab <- function(x, nm) if (is.null(x)) rep(NA_real_, nrow(a)) else as.numeric(x[[nm]])
  res <- data.frame(
    sample_id = rownames(a),
    nbsp = grab(fd, "nbsp"), sing.sp = grab(fd, "sing.sp"),
    FRic = round(grab(fd, "FRic"), 4), FEve = round(grab(fd, "FEve"), 4),
    FDiv = round(grab(fd, "FDiv"), 4), FDis = round(grab(fd, "FDis"), 4),
    RaoQ = round(grab(fd, "RaoQ"), 4), stringsAsFactors = FALSE)
  cwm <- fd$CWM
  if (!is.null(cwm)) {
    cwm <- as.data.frame(cwm); names(cwm) <- paste0("CWM_", names(cwm))
    res <- cbind(res, cwm[rownames(a), , drop = FALSE])
  }
  show <- intersect(c("sample_id", "nbsp", "FRic", "FEve", "FDiv", "FDis", "RaoQ"), names(res))
  cat("\n--- 功能多样性（前 6 行；CWM 列已写入结果表，不在控制台展开）---\n")
  print(utils::head(res[, show, drop = FALSE], 6))

  # ---- 功能β多样性 ----
  fb <- NULL
  tr_beta <- tr                      # 功能β 实际使用的性状输入（可能是 PCA 主轴）
  beta_note <- sprintf("%d raw traits", ncol(tr))
  if (isTRUE(cfg$opts$beta_partition)) {
    if (!pd_has("betapart")) {
      pd_warn("需要 betapart 做功能β分解，已跳过")
    } else {
      pa <- ifelse(a > 0, 1, 0)
      min_sp <- min(rowSums(pa))
      if (min_sp <= ncol(tr)) {
        # 原文的做法正是先做性状 PCA、用前几个主轴（trait-FD.N-part-III.csv = 5 个主轴）
        # 所以这里做同样的降维回退，而不是直接放弃
        if (isTRUE(cfg$opts$fd_axis_fallback %||% TRUE)) {
          k <- min(as.integer(cfg$opts$fd_axis_n %||% 5), min_sp - 1L)
          if (k >= 2) {
            pc <- tryCatch(stats::prcomp(tr, center = TRUE, scale. = TRUE), error = function(e) NULL)
            if (!is.null(pc)) {
              tr_beta <- as.data.frame(pc$x[, 1:k, drop = FALSE])
              beta_note <- sprintf("%d PCA axes of %d traits (PCA on the %d aligned species)",
                                   k, ncol(tr), nrow(tr))
              pd_msg(sprintf(paste0("[20] 功能β：原始性状 %d 个 > 最小群落物种数 %d，",
                                    "凸包要求不满足 → 按原文做法改用 %d 个性状 PCA 主轴"),
                             ncol(tr), min_sp, k))
            } else pd_warn("性状 PCA 失败，功能β 跳过")
          } else {
            pd_warn(sprintf("功能β 跳过：最小群落物种数 %d 太少，降维到 %d 轴也不够", min_sp, k))
          }
        } else {
          pd_warn(sprintf(paste0("功能β（betapart）已跳过：最小群落物种数 %d ≤ 性状数 %d。",
                                 "把 opts$fd_axis_fallback 设为 TRUE 可自动做性状 PCA 降维。"),
                          min_sp, ncol(tr)))
        }
      }
      if (!is.null(tr_beta) && ncol(tr_beta) < min_sp) {
        # betapart 的 functional.betapart.core 内部要算**所有样方两两**的凸包交叠，
        # 所以即使 multi=FALSE 也是 O(n²)：180 样方 = 16110 对，实测 >10 分钟未完成。
        # → 大样本默认不跑，给出配对规模与开启方法，由用户决定（长任务纪律）
        n_pair <- nrow(pa) * (nrow(pa) - 1) / 2
        max_sites <- as.integer(cfg$opts$fd_beta_max_sites %||% 120)
        method <- cfg$opts$fd_beta_method %||% "auto"   # auto | betapart | traitspace
        use_betapart <- identical(method, "betapart") ||
          (identical(method, "auto") && nrow(pa) <= max_sites)
        if (use_betapart) {
          pd_msg(sprintf(paste0("[20] functional.betapart.core 开始（%d 个样方 → %d 对，",
                                "× %d 个性状输入）。这一步是 O(n²)，可能耗时数十分钟。"),
                         nrow(pa), n_pair, ncol(tr_beta)))
          t0 <- Sys.time()
          fb <- tryCatch(betapart::functional.betapart.core(x = pa, traits = tr_beta, multi = FALSE),
                         error = function(e) { pd_warn("functional.betapart.core 失败: ", conditionMessage(e)); NULL })
          fb_min <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
          if (!is.null(fb)) {
            attr(fb, "pd_traits") <- beta_note
            attr(fb, "pd_minutes") <- fb_min
            attr(fb, "pd_method") <- "betapart::functional.betapart.core"
            pd_msg(sprintf("[20] 功能β核心完成（性状输入：%s；用时 %.2f 分钟）：shared=%.3f  not.shared=%.3f",
                           beta_note, fb_min, sum(fb$shared), sum(fb$not.shared)))
          }
        } else if (identical(method, "betapart")) {
          pd_warn(sprintf(paste0("功能β 已跳过：opts$fd_beta_method='betapart' 但 %d 个样方（%d 对）",
                                 "超过阈值 %d。实测该规模需数小时。"),
                          nrow(pa), n_pair, max_sites))
          pd_msg("       确认要跑请设 opts$fd_beta_confirm = TRUE；或改用 opts$fd_beta_method='traitspace'。")
        } else if (isTRUE(cfg$opts$fd_beta_confirm %||% FALSE)) {
          pd_msg("[20] fd_beta_confirm = TRUE → 强制走 betapart（很慢，请耐心）")
          t0 <- Sys.time()
          fb <- tryCatch(betapart::functional.betapart.core(x = pa, traits = tr_beta, multi = FALSE),
                         error = function(e) { pd_warn("functional.betapart.core 失败: ", conditionMessage(e)); NULL })
          if (!is.null(fb)) {
            attr(fb, "pd_traits") <- beta_note
            attr(fb, "pd_minutes") <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
            attr(fb, "pd_method") <- "betapart::functional.betapart.core"
          }
        } else {
          # auto + 超出阈值 → 走性状空间分格替代路线
          pd_warn(sprintf(paste0("功能β：%d 个样方（%d 对）超出 betapart 可行规模（阈值 %d）。",
                                 "实测 20 个样方 190 对已 >10 分钟，故改走「性状空间功能实体」替代路线。"),
                          nrow(pa), n_pair, max_sites))
          tsres <- tryCatch(pd_func_beta_traitspace(
            pa, tr_beta,
            n_cells = as.integer(cfg$opts$fd_traitspace_bins %||% 4),
            n_axes  = as.integer(cfg$opts$fd_traitspace_axes %||% 3)),
            error = function(e) { pd_warn("性状空间功能β失败: ", conditionMessage(e)); NULL })
          if (!is.null(tsres)) {
            fb <- list(shared = tsres$note, not.shared = NA, pd_traitspace = tsres)
            attr(fb, "pd_traits") <- beta_note
            attr(fb, "pd_minutes") <- NA
            attr(fb, "pd_method") <- "traitspace functional entities + betapart::beta.pair (Sørensen)"
            bt <- tsres$beta_pair
            if (!is.null(bt)) pd_msg(sprintf(paste0("[20] 性状空间功能β完成：%s；",
                                                    "turnover(beta.sim)=%.3f，nestedness(beta.sne)=%.3f，total(beta.sor)=%.3f"),
                                             tsres$note, mean(bt$beta.sim), mean(bt$beta.sne), mean(bt$beta.sor)))
            pd_msg("       ⚠ 该路线假设「同一网格单元的物种功能等价」，结果依赖网格数（opts$fd_traitspace_bins），Methods 需写明。")
          }
        }
      }
    }
  }

  out <- list(fd = res, dbFD = fd, func_beta = fb, traits_used = tr, source = src)
  if (save) {
    tabs <- list("fd_indices" = res)
    if (!is.null(fb)) {
      # 复刻原文 test.core.xlsx：把 functional.betapart.core 的每个组件单独写成一个 sheet
      for (nm in names(fb)) {
        z <- pd_obj_to_df(fb[[nm]], nm)
        if (!is.null(z) && nrow(z)) tabs[[paste0("core_", gsub("[^A-Za-z0-9]", "_", nm))]] <- z
      }
      # 性状空间替代路线的产物
      if (!is.null(fb$pd_traitspace) && !is.null(fb$pd_traitspace$beta_pair)) {
        ts <- fb$pd_traitspace
        for (nmk in names(ts$beta_pair)) {
          z <- pd_obj_to_df(ts$beta_pair[[nmk]], nmk)
          if (!is.null(z) && nrow(z)) tabs[[paste0("funcbeta_", nmk)]] <- z
        }
        tabs$funcbeta_note <- data.frame(
          item = c("方法", "网格分位数", "主轴数", "功能实体数", "性状输入"),
          value = c(attr(fb, "pd_method"), ts$n_cells, ts$n_axes, ts$n_entities, beta_note),
          stringsAsFactors = FALSE)
      }
      # 逐样方两两的 multi=TRUE 版本：180 样方 = 16110 对凸包交叠，极慢，原文并未使用
      # → 默认关闭，仅当 opts$fd_beta_pairwise = TRUE 时才尝试
      if (isTRUE(cfg$opts$fd_beta_pairwise %||% FALSE)) {
        pd_msg("[20] 计算功能β 两两矩阵（multi=TRUE）——这一步很慢，请耐心等待…")
        feas <- tryCatch(as.data.frame(betapart::functional.betapart.core(x = pa, traits = tr_beta, multi = TRUE)$pairwise),
                         error = function(e) { pd_warn("两两功能β失败: ", conditionMessage(e)); NULL })
        if (!is.null(feas)) tabs$func_beta_pairwise <- feas
      }
    }
    tabs$run_info <- data.frame(
      item = c("FD 性状数", "FRic 维数 m", "功能β 方法", "功能β 口径声明",
               "功能β 性状输入", "功能β 耗时(分)", "输入数据类型",
               "多度∩性状 物种数", "性状来源标记", "样方数"),
      value = c(ncol(tr), as.character(m_arg),
                if (is.null(fb)) "未执行（已跳过，见日志）" else (attr(fb, "pd_method") %||% "betapart"),
                # ★★ 口径声明（2026-09-25，pitfalls I28）
                if (identical(attr(fb, "pd_method") %||% "", "trait-space-gridded"))
                  paste0("★ 性状空间分格【离散化功能实体近似】，不是 Villéger(2011)/",
                         "Baselga & Villéger(2014) 的凸包体积分解；数值不可与文献 functional ",
                         "turnover/nestedness 直接比较。依赖分格数/轴数（",
                         cfg$opts$fd_traitspace_bins %||% 4, "/",
                         cfg$opts$fd_traitspace_axes %||% 3, "），须做敏感性。")
                else "betapart::functional.betapart.core（凸包核心量，文献口径）",
                beta_note,
                if (is.null(fb)) NA else (attr(fb, "pd_minutes") %||% NA),
                if (isTRUE(cfg$opts$abundance_is_iv %||% FALSE)) "重要值（连续）" else "多度/计数",
                length(common), src, nrow(a)),
      stringsAsFactors = FALSE)
    pd_write_table(tabs, stem = "dbFD", module = "20")
    utils::write.csv(tr, file.path(cfg$paths$results, "20_traits_used.csv"),
                     row.names = TRUE, fileEncoding = "UTF-8")
  }
  invisible(out)
}
