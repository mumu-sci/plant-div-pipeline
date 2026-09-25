# ============================================================
# 16_mcmcglmm.R · 贝叶斯混合模型（MCMCglmm）
#   MCMCglmm(fixed = Shannon ~ Habitat + Season + Habitat:Season,
#            random = ~ Site, family = "gaussian")   # 随机截距
# ★★ MCMCglmm 的 random 公式【不接受 lme4 的 (1|Site) 语法】（pitfalls I6，2026-09-25 实测）
#   写 "~ Habitat + (1|Site)" 会报 "invalid substring arguments"，整模块跑不通。
#   正确写法：
#     随机截距            ~ Site
#     Site 下随机斜率      ~ us(Habitat):Site        （也可简写 ~ Habitat:Site）
#     截距 + 斜率         ~ Site + us(Habitat):Site
#   注：lme4 的 "(Habitat|Site)" 才是随机斜率，"(1|Site)" 只是随机截距。
# 依赖：MCMCglmm（含 coda）
# 长任务纪律：MCMC 采样是耗时步骤，先打印规模与预估，再跑；结果表记录实际耗时
# ============================================================

# 依 random 公式文字统计随机项个数，用于构造合适的先验
# ★ 按 MCMCglmm 语法拆项（以 + 分隔）；lme4 的 (1|Site) 写法在这里一律报错提示
pd_mcmc_n_raneff <- function(rand_form) {
  if (grepl("\\|", rand_form)) {
    pd_warn("MCMCglmm 的 random 公式不接受 lme4 的 (1|Site) 写法；",
            "请改成 ~ Site / ~ us(Habitat):Site / ~ Site + us(Habitat):Site")
    return(NA_integer_)
  }
  terms <- trimws(unlist(strsplit(rand_form, "\\+")))
  terms <- terms[nzchar(terms) & terms != "~"]
  length(terms)
}

# 每个随机项的维数（MCMCglmm 先验 V 要按维数给）
#   ~X          → 1（随机截距）
#   ~us(F):G    → nlevels(F)（F 的随机斜率，按 G 分组）
#   ~F:G        → nlevels(F)
pd_mcmc_raneff_dims <- function(rand_form, dd = NULL, factors = NULL) {
  terms <- trimws(unlist(strsplit(gsub("^~", "", rand_form), "\\+")))
  terms <- terms[nzchar(terms)]
  vapply(terms, function(t) {
    if (grepl("^us\\(", t)) {
      inner <- sub("^us\\(([^)]+)\\).*$", "\\1", t)
      if (!is.null(dd) && inner %in% names(dd)) nlevels(factor(dd[[inner]])) else 2L
    } else if (grepl(":", t)) {
      lhs <- trimws(strsplit(t, ":")[[1]][1])
      if (!is.null(dd) && lhs %in% names(dd)) nlevels(factor(dd[[lhs]])) else 2L
    } else 1L
  }, integer(1), USE.NAMES = FALSE)
}

pd_run_mcmcglmm <- function(cfg = .pd$cfg, dat = NULL, vars = NULL, save = TRUE) {
  if (!pd_require("MCMCglmm", "16_mcmcglmm")) return(invisible(NULL))
  dat <- dat %||% pd_load_data(cfg)
  pd_msg("")
  pd_msg("### 16 贝叶斯混合模型（MCMCglmm）###")

  vars <- vars %||% cfg$response$alpha
  vars <- vars[vars %in% names(dat$meta)]
  if (!length(vars)) { pd_warn("无可用因变量（config$response$alpha）"); return(invisible(NULL)) }
  factors <- cfg$design$factors[cfg$design$factors %in% names(dat$meta)]
  if (!length(factors)) { pd_warn("无分组因子"); return(invisible(NULL)) }

  rv <- cfg$design$random
  rv <- if (is.null(rv) || is.na(rv) || !nzchar(rv) || !(rv %in% names(dat$meta))) NULL else rv
  if (is.null(rv)) { pd_warn("config$design$random 未指定有效的随机因子 → 16 跳过"); return(invisible(NULL)) }

  nitt   <- as.integer(cfg$opts$mcmc_nitt   %||% 13000)
  burnin <- as.integer(cfg$opts$mcmc_burnin %||% 3000)
  thin   <- as.integer(cfg$opts$mcmc_thin   %||% 10)
  nthin  <- floor((nitt - burnin) / thin)
  rand_form <- cfg$opts$mcmc_random %||% paste0("~ ", rv)   # 例："~ Habitat + (1|Site)"
  fixed_txt <- if (isTRUE(cfg$opts$include_interaction))
    paste(sprintf("`%s`", factors), collapse = " + ") else
      paste(sprintf("`%s`", factors), collapse = " + ")
  if (isTRUE(cfg$opts$include_interaction) && length(factors) >= 2)
    fixed_txt <- paste0(fixed_txt, " + ", sprintf("`%s`", factors[1]), ":",
                        sprintf("`%s`", factors[2]))

  pd_msg(sprintf("[16] 固定效应 = %s | 随机效应 = %s", fixed_txt, rand_form))
  pd_msg(sprintf("[16] 采样规模：nitt=%d, burnin=%d, thin=%d → 保留 %d 个后验样本",
                 nitt, burnin, thin, nthin))
  pd_msg("[16] 提示：MCMC 是长任务。若首次运行，可先在 config 把 mcmc_nitt 降到 3000 / burnin 1000 测时间。")

  # 先验：随机项 > 1 时默认先验不够，需要给出 G 列表
  nre <- pd_mcmc_n_raneff(rand_form)
  prior <- NULL
  if (isTRUE(nre > 1)) {
    # ★★ 先验维度按【每项实际随机效应维数】构造（2026-09-25，pitfalls I25）
    #   旧写法每项一律 diag(1) —— 随机斜率 / 多维项（如 us(Habitat):Site）维度不够，MCMCglmm 会炸。
    #   ~X → 1 维；~us(F):G → nlevels(F) 维。
    dims <- pd_mcmc_raneff_dims(rand_form, dd = dat$meta, factors = factors)
    G <- lapply(dims, function(k)
      list(V = diag(k), nu = 1, alpha.mu = rep(0, k), alpha.V = diag(25^2, k)))
    prior <- list(G = G, R = list(V = 1, nu = 0.002))
    pd_msg(sprintf("[16] 随机效应先验维度：%s（共 %d 项）", paste(dims, collapse = "+"), length(dims)))
  }

  coef_all <- list(); re_all <- list(); r2_all <- list(); diag_all <- list()
  trace_figs <- list()
  elapsed <- numeric(0)

  for (y in vars) {
    dd <- dat$meta[stats::complete.cases(dat$meta[, c(y, factors, rv)]), , drop = FALSE]
    for (f in factors) dd[[f]] <- droplevels(factor(dd[[f]]))
    dd[[rv]] <- factor(dd[[rv]])
    fx <- stats::as.formula(sprintf("`%s` ~ %s", y, fixed_txt))
    rd <- stats::as.formula(rand_form)

    set.seed(cfg$opts$seed %||% 20260101)
    t0 <- Sys.time()
    # MCMC 采样是本模块耗时点 → 包缓存（按变量分 key，改样式重跑不重采样）
    m <- pd_cached(paste0("16_mcmc_", gsub("[^A-Za-z0-9]", "_", y)), NULL, {
      tryCatch({
        if (is.null(prior))
          MCMCglmm::MCMCglmm(fixed = fx, random = rd, family = "gaussian", data = dd,
                             nitt = nitt, burnin = burnin, thin = thin, verbose = FALSE)
        else
          MCMCglmm::MCMCglmm(fixed = fx, random = rd, family = "gaussian", data = dd,
                             prior = prior, nitt = nitt, burnin = burnin, thin = thin,
                             verbose = FALSE)
      }, error = function(e) { pd_warn("MCMCglmm 拟合失败（", y, "）: ", conditionMessage(e)); NULL })
    }, cfg = cfg)
    if (is.null(m)) next
    el <- round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 2)
    elapsed <- c(elapsed, el)
    pd_msg(sprintf("[16] %s 采样完成，用时 %.2f 分钟", y, el))

    # 固定效应后验
    ss <- summary(m)$solutions
    coef_all[[y]] <- data.frame(
      variable = y, term = rownames(ss),
      post_mean = round(ss[, "post.mean"], 4), l95 = round(ss[, "l-95% CI"], 4),
      u95 = round(ss[, "u-95% CI"], 4), pMCMC = signif(ss[, "pMCMC"], 4),
      eff_sample = round(ss[, "eff.samp"], 1),
      # 科学的显著性判定：95% 可信区间是否跨 0（与 pMCMC 互为旁证）
      ci_excludes_0 = (ss[, "l-95% CI"] > 0) | (ss[, "u-95% CI"] < 0),
      stringsAsFactors = FALSE, row.names = NULL)

    # 方差成分：MCMCglmm 没有导出 VarCorr（原先用 MCMCglmm::VarCorr 会报
    #   "'VarCorr' is not an exported object from 'namespace:MCMCglmm'"），
    #   改用 summary() 的 Gcovariances / Rcovariances
    sm <- summary(m)
    vc_rows <- list()
    for (nmk in c("Gcovariances", "Rcovariances")) {
      z <- sm[[nmk]]
      if (is.null(z)) next
      z <- as.data.frame(z)
      vc_rows[[length(vc_rows) + 1]] <- data.frame(
        variable = y, component = nmk, term = rownames(z),
        post_mean = round(z[[1]], 6),
        l95 = round(z[[2]], 6), u95 = round(z[[3]], 6),
        stringsAsFactors = FALSE, row.names = NULL)
    }
    if (length(vc_rows)) re_all[[y]] <- do.call(rbind, vc_rows)

    # R²：MCMCglmm 对 gaussian 不总返回 r.squared（本机返回 NULL），
    #     故按 Nakagawa 分解用后验均值自算：var(Xβ) / (var(Xβ)+V_G+V_R)
    r2 <- tryCatch(summary(m)$r.squared, error = function(e) NULL)
    if (!is.null(r2)) {
      v <- unlist(r2)
      nmv <- names(v); if (is.null(nmv)) nmv <- paste0("R2_", seq_along(v))
      r2_all[[y]] <- data.frame(variable = y, component = nmv,
                                value = round(as.numeric(v), 4), stringsAsFactors = FALSE)
    } else {
      X <- tryCatch(stats::model.matrix(fx, data = dd), error = function(e) NULL)
      vcv <- colMeans(m$VCV); nmvcv <- colnames(m$VCV)
      isR <- grepl("units|^R$|residual", nmvcv, ignore.case = TRUE)
      vres <- sum(vcv[isR]); vrand <- sum(vcv[!isR])
      if (!is.null(X) && ncol(X) > 0) {
        b <- colMeans(m$Sol); nmb <- colnames(m$Sol)
        beta <- if (all(colnames(X) %in% nmb)) b[colnames(X)]
                else if (length(nmb) == ncol(X)) stats::setNames(b, colnames(X)) else NULL
        if (!is.null(beta)) {
          Xb <- as.vector(X %*% as.numeric(beta))
          varf <- stats::var(Xb)
          r2m <- varf / (varf + vrand + vres)
          r2c <- (varf + vrand) / (varf + vrand + vres)
          r2_all[[y]] <- data.frame(variable = y,
            component = c("R2marginal", "R2conditional"),
            value = round(c(r2m, r2c), 4), stringsAsFactors = FALSE)
          pd_msg(sprintf("[16] %s：R2m = %.3f，R2c = %.3f（按后验均值 + Nakagawa 分解自算）",
                         y, r2m, r2c))
        }
      }
    }

    # 收敛诊断：DIC + 后验一阶自相关
    # 注意：MCMCglmm 的 autocorr() 未导出（直接 MCMCglmm::autocorr 会失败），
    #       这里直接用 stats::acf 按列算 lag-1 自相关，再取绝对值中位数
    lag1_ac <- function(mm) {
      if (is.null(mm) || !ncol(mm)) return(NA_real_)
      v <- apply(as.matrix(mm), 2, function(z) {
        z <- z[is.finite(z)]
        if (length(z) < 5) return(NA_real_)
        a <- tryCatch(stats::acf(z, lag.max = 1, plot = FALSE)$acf[2], error = function(e) NA_real_)
        as.numeric(a)
      })
      stats::median(abs(v), na.rm = TRUE)
    }
    m1_sol <- lag1_ac(m$Sol)
    m1_vcv <- lag1_ac(m$VCV)
    if (!is.finite(m1_sol)) m1_sol <- NA_real_
    if (!is.finite(m1_vcv)) m1_vcv <- NA_real_
    # 混合是否足够：固定效应链与方差成分链**都要**看
    #   （实测 Shannon 的 VCV 链 lag-1 = 0.247 而 Sol 链只有 0.018 —— 只看 Sol 会漏掉）
    mixing_ok <- (is.na(m1_sol) || m1_sol < 0.1) && (is.na(m1_vcv) || m1_vcv < 0.1)
    diag_all[[y]] <- data.frame(
      variable = y, DIC = round(m$DIC, 2), n_samples = nrow(m$Sol),
      lag1_autocorr_Sol = round(m1_sol, 4), lag1_autocorr_VCV = round(m1_vcv, 4),
      mixing_ok = mixing_ok, minutes = el, stringsAsFactors = FALSE)
    if (!isTRUE(mixing_ok)) {
      bad <- c(if (!is.na(m1_sol) && m1_sol >= 0.1) sprintf("固定效应链 %.3f", m1_sol),
               if (!is.na(m1_vcv) && m1_vcv >= 0.1) sprintf("方差成分链 %.3f", m1_vcv))
      pd_warn(sprintf("%s 的 MCMC 混合不足（lag-1 自相关 >= 0.1：%s）→ 应增大 thin 或 nitt，",
                      y, paste(bad, collapse = "；")))
      pd_warn("     混合不足时后验可信区间会偏窄，pMCMC 可能假显著。")
    }

    # ---- 迹图 ----
    # [第 3 轮删除] 用户决定删除 stats_tests_panel 及其组成图代码。
    #   ★ 收敛诊断在 diagnostics 表：DIC + 后验【lag-1 自相关】。
  #   ⚠️ 【没有 Gelman R-hat】（单链也算不了），需要 R-hat 请用 coda 跑多链再算（2026-09-25 修正注释）。
    #   要看迹图可临时恢复：coda::traceplot(m$Sol) / coda::traceplot(m$VCV)
  }
  if (!length(coef_all)) { pd_warn("16 无成功模型"); return(invisible(NULL)) }
  bind <- function(l) if (length(l)) do.call(rbind, lapply(l, function(z) { rownames(z) <- NULL; z })) else data.frame()

  coef_tab <- bind(coef_all); re_tab <- bind(re_all); r2_tab <- bind(r2_all); dg_tab <- bind(diag_all)
  cat("\n--- MCMCglmm 固定效应后验 ---\n"); print(utils::head(coef_tab, 10))
  cat("\n--- 收敛诊断 ---\n"); print(dg_tab)

  out <- list(coefficients = coef_tab, random_effects = re_tab, r2 = r2_tab,
              diagnostics = dg_tab, trace_figures = trace_figs,
              total_minutes = sum(elapsed), settings = list(
                nitt = nitt, burnin = burnin, thin = thin, random = rand_form,
                fixed = fixed_txt, n_raneff = nre, prior_used = !is.null(prior)))
  if (save) {
    pd_write_table(list(
      fixed_effects = coef_tab, random_effects = re_tab, r2 = r2_tab,
      diagnostics = dg_tab,
      run_info = data.frame(
        item = c("固定效应", "随机效应", "nitt", "burnin", "thin", "后验样本数",
                 "随机项个数", "是否自定义先验", "总耗时(分)", "显著性判定"),
        value = c(fixed_txt, rand_form, nitt, burnin, thin, nthin, nre,
                  !is.null(prior), round(sum(elapsed), 2),
                  "95% 可信区间是否跨 0（ci_excludes_0 列），与 pMCMC 互为旁证"),
        stringsAsFactors = FALSE)),
      stem = "mcmcglmm", module = "16")
  }
  invisible(out)
}
