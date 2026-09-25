# ============================================================
# 31_pd_nti_nri.R · 谱系多样性：PD / MNTD / MPD / NTI / NRI
# 依赖：picante ；ape
# 对应原代码：pd(t(data), tree) + ses.mntd/ses.mpd(null.model='taxa.labels')
# 长任务提醒：runs 至少 999 时是耗时大户，执行前须报时间预估
# ============================================================

pd_run_pd_nti_nri <- function(cfg = .pd$cfg, dat = NULL, tree = NULL, save = TRUE) {
  if (!pd_require(c("picante", "ape"), "31_pd_nti_nri")) return(invisible(NULL))
  dat <- dat %||% pd_load_data(cfg)
  pd_msg("")
  pd_msg("### 31 PD / NTI / NRI ###")

  tree <- tree %||% dat$tree
  if (is.null(tree)) {
    pd_msg("[31] 没有可用系统发育树（config$files$phylo 未提供或读取失败）。")
    pd_msg("[31] 纪律：缺数据只报告不动手。请放入 99_phylo.tre，或先跑 30_phylo_build。已跳过。")
    return(invisible(NULL))
  }
  if (is.null(tree$edge.length)) {
    pd_warn("树无枝长，PD/MNTD 无法计算。已跳过 31。")
    return(invisible(NULL))
  }
  tree$tip.label <- normalize_species(tree$tip.label)
  ab <- dat$abundance

  common <- intersect(colnames(ab), tree$tip.label)
  drop_sp <- setdiff(colnames(ab), tree$tip.label)
  pd_msg(sprintf("[31] 物种对齐：多度 %d × 树 %d → 交集 %d", ncol(ab), length(tree$tip.label), length(common)))
  if (length(drop_sp))
    pd_msg(sprintf("[31]   不在树中（%d 个，将不参与谱系指数）：%s", length(drop_sp),
                   paste(head(drop_sp, 10), collapse = ", ")))
  trim_tip <- setdiff(tree$tip.label, common)
  if (length(trim_tip)) {
    pd_msg(sprintf("[31]   树中无多度记录（%d 个，已从树中剪除）：%s", length(trim_tip),
                   paste(head(trim_tip, 10), collapse = ", ")))
    tree <- ape::drop.tip(tree, trim_tip)
  }
  if (length(common) < 5) { pd_warn("交集物种 < 5，谱系指数不可靠，已跳过"); return(invisible(NULL)) }

  comm <- ab[, common, drop = FALSE]
  pd_dist <- ape::cophenetic.phylo(tree)

  # ---- 1. PD（Faith）----
  pdr <- tryCatch(picante::pd(comm, tree, include.root = TRUE), error = function(e) NULL)
  if (is.null(pdr)) { pd_warn("PD 计算失败"); return(invisible(NULL)) }
  pd_tab <- data.frame(sample_id = rownames(pdr), PD = round(pdr$PD, 4),
                       SR = as.integer(pdr$SR), stringsAsFactors = FALSE)

  # ---- 2. MNTD / NTI ----
  runs <- as.integer(cfg$opts$runs %||% 999)
  nm   <- cfg$opts$null_model %||% "taxa.labels"
  aw   <- isTRUE(cfg$opts$abundance_weighted %||% TRUE)
  label <- cfg$opts$runs_label %||% "final"
  pd_msg(sprintf("[31] 零模型 = %s | 多度加权 = %s | 置换 = %d（标记 %s）", nm, aw, runs, label))
  pd_msg(sprintf("[31] 提示：置换 %d 时本模块可能需要数分钟到数十分钟。测试可先在 config 改 runs=199 并设 runs_label=\"test\"。",
                 runs))

  t0 <- Sys.time()
  # 置换检验（runs 次）是本模块耗时点 → 包缓存
  ses <- pd_cached("31_ses_mntd_mpd", NULL, {
    list(
      mntd = tryCatch(picante::ses.mntd(comm, pd_dist, null.model = nm,
                                        abundance.weighted = aw, runs = runs),
                      error = function(e) { pd_warn("ses.mntd 失败: ", conditionMessage(e)); NULL }),
      mpd  = tryCatch(picante::ses.mpd(comm, pd_dist, null.model = nm,
                                       abundance.weighted = aw, runs = runs),
                      error = function(e) { pd_warn("ses.mpd 失败: ", conditionMessage(e)); NULL })
    )
  }, cfg = cfg)
  z_mntd <- ses$mntd
  z_mpd  <- ses$mpd
  el <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
  pd_msg(sprintf("[31] 置换完成，用时 %.2f 分钟", el))

  build <- function(z, obs_col, z_col, p_col, out_name) {
    if (is.null(z)) return(NULL)
    d <- data.frame(sample_id = rownames(z))
    d[[out_name]] <- round(-z[[z_col]], 4)                     # NTI = -mntd.obs.z ；NRI = -mpd.obs.z
    d[[paste0(out_name, "_obs")]] <- round(z[[obs_col]], 4)
    d[[paste0(out_name, "_z")]] <- round(z[[z_col]], 4)
    # 用 picante 的原生列名（mntd.obs.p / mpd.obs.p），不叫 NTI_p —— 否则会被当成 NTI 的 p 值误引
    d[[p_col]] <- signif(z[[p_col]], 4)
    d$ntaxa <- as.integer(z$ntaxa)
    d$pattern <- ifelse(d[[out_name]] > 2, "聚集(clustering)",
                 ifelse(d[[out_name]] < -2, "发散(overdispersion)", "随机(random)"))
    d
  }
  nti <- build(z_mntd, "mntd.obs", "mntd.obs.z", "mntd.obs.p", "NTI")
  nri <- build(z_mpd,  "mpd.obs",  "mpd.obs.z",  "mpd.obs.p",  "NRI")

  res <- pd_tab
  if (!is.null(nti)) res <- merge(res, nti, by = "sample_id", all.x = TRUE, sort = FALSE)
  if (!is.null(nri)) res <- merge(res,
                                  nri[, c("sample_id", "NRI", "NRI_obs", "NRI_z", "mpd.obs.p", "pattern")],
                                  by = "sample_id", all.x = TRUE, sort = FALSE)
  names(res)[names(res) == "pattern.x"] <- "pattern_NTI"
  names(res)[names(res) == "pattern.y"] <- "pattern_NRI"
  names(res)[names(res) == "ntaxa.x"] <- "ntaxa"
  res$ntaxa.y <- NULL
  if ("SR" %in% names(res)) res$SR <- NULL   # 与 ntaxa 重复，只留一个

  # 按分组因子的均值汇总
  summ <- NULL
  f1 <- cfg$design$factors[1]
  if (length(f1) && f1 %in% names(dat$meta)) {
    g <- dat$meta[[f1]][match(res$sample_id, as.character(dat$meta[[cfg$key$sample_id]]))]
    vars <- intersect(c("PD", "NTI", "NRI", "SR"), names(res))
    summ <- do.call(rbind, lapply(vars, function(v) {
      m <- tapply(res[[v]], g, function(z) round(mean(z, na.rm = TRUE), 4))
      data.frame(variable = v, group = names(m), mean = as.numeric(m), stringsAsFactors = FALSE)
    }))
  }
  cat("\n--- 谱系指数（前 6 行）---\n"); print(utils::head(res, 6))

  out <- list(table = res, summary = summ, elapsed_min = el, runs = runs, null_model = nm)
  if (save) {
    tabs <- list("pd_nti_nri" = res)
    if (!is.null(summ)) tabs$group_means <- summ
    # ★★ 口径声明（2026-09-25，pitfalls I22）
    tabs$run_info <- data.frame(
      item = c("PD 口径", "include.root", "零模型", "多度加权", "NTI/NRI 符号",
               "mntd.obs.p 口径", "置换次数", "标记", "耗时(分)"),
      value = c("Faith's PD（picante::pd 总枝长）",
                "TRUE —— 通往树根的枝计入每个样方 PD（picante 文档 Warning，需在 Methods 声明）",
                nm,
                if (isTRUE(aw)) "TRUE —— 且多度为【重要值】时是 IV 加权版，与文献 PA 版不可比"
                else "FALSE（存在-缺失口径）",
                "NTI = -ses.mntd 的 z；NRI = -ses.mpd 的 z（NTI>2 聚集 / < -2 发散）",
                "ses.mntd 的 mntd.obs.p 是【单尾秩 p】（p = rank/(runs+1)，小 p = 观测低于零模型）",
                runs, label, el),
      stringsAsFactors = FALSE)
    pd_write_table(tabs, stem = paste0("runs", runs, "_", label), module = "31")
  }
  invisible(out)
}
