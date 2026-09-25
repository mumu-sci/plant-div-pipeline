# ============================================================
# 14_mixed_model.R · 线性混合效应模型 + R² 分解 + 边际均值
# 依赖：lme4 lmerTest emmeans ；glmm.hp（可选）
# 见 references/01-method-menu.md §2.14
# ============================================================

pd_run_mixed <- function(cfg = .pd$cfg, dat = NULL, vars = NULL, save = TRUE) {
  if (!pd_require(c("lme4", "lmerTest", "emmeans"), "14_mixed_model")) return(invisible(NULL))
  dat <- dat %||% pd_load_data(cfg)
  pd_msg("")
  pd_msg("### 14 混合效应模型 ###")

  vars <- vars %||% cfg$response$alpha
  vars <- vars[vars %in% names(dat$meta)]
  factors <- cfg$design$factors[cfg$design$factors %in% names(dat$meta)]
  # ★★ 随机结构双入口统一（2026-09-25，pitfalls I8）
  #   旧写法兜底写死 "(1|Site)"，换设计（如 fixed_plot 应为 (1|plot)）就错；
  #   且 14 读 opts$random_structure、15/16 读 design$random，两个独立键容易悄悄分叉。
  #   现在：opts$random_structure 显式写了就尊重；否则按 design$sampling + design$random 推导。
  rs <- cfg$opts$random_structure
  if (is.null(rs) || !nzchar(as.character(rs)[1]) || is.na(as.character(rs)[1])) {
    rs <- if (exists("pd_suggest_random", mode = "function")) pd_suggest_random(cfg) else NULL
    if (is.null(rs)) {
      pd_warn("design$sampling = \"", pd_design_sampling(cfg),
              "\" 不需要随机效应，且 opts$random_structure 未显式配置 → 14 跳过；",
              "若确实需要混合模型，请显式写 opts$random_structure（如 \"(1|Site)\"）")
      return(invisible(NULL))
    }
    pd_msg("[14] 随机结构按 design$sampling 自动推导：", rs)
  }
  rand_var <- gsub(".*\\|\\s*([^)\\s]+)\\s*\\).*", "\\1", rs)
  if (identical(rand_var, rs))   # 公式里没有 | → 取最后一个标识符
    rand_var <- tail(trimws(unlist(strsplit(gsub("[()~]", " ", rs), "\\s+"))), 1)
  if (!(rand_var %in% names(dat$meta))) {
    pd_warn(sprintf("随机效应分组变量 '%s' 不在元数据中 → 14 模块跳过", rand_var))
    return(invisible(NULL))
  }
  pd_msg(sprintf("[14] 固定效应 = %s | 随机效应 = %s",
                 paste(sprintf("`%s`", factors), collapse = " * "), rs))

  fixed <- if (isTRUE(cfg$opts$include_interaction))
    paste(sprintf("`%s`", factors), collapse = " * ") else
      paste(sprintf("`%s`", factors), collapse = " + ")

  coef_all <- list(); anova_all <- list(); r2_all <- list(); emm_all <- list()
  re_all <- list()
  ref_lv <- cfg$opts$ref_levels %||% list()   # 参考水平（原文对 Habitat/Season 做了 relevel）

  for (y in vars) {
    form <- stats::as.formula(sprintf("`%s` ~ %s + %s", y, fixed, rs))
    dd <- dat$meta[stats::complete.cases(dat$meta[, c(y, factors, rand_var)]), , drop = FALSE]
    dd[[rand_var]] <- droplevels(factor(dd[[rand_var]]))
    for (f in factors) {
      dd[[f]] <- droplevels(factor(dd[[f]]))
      # 设定参考水平（影响系数解释与 emmeans 对比基线）
      rl <- ref_lv[[f]]
      if (!is.null(rl) && rl %in% levels(dd[[f]])) dd[[f]] <- stats::relevel(dd[[f]], ref = rl)
    }

    m <- tryCatch(lmerTest::lmer(form, data = dd, REML = TRUE), error = function(e) NULL)
    if (is.null(m)) { pd_warn("模型拟合失败: ", y, " | ", form); next }
    sg <- tryCatch(lme4::isSingular(m), error = function(e) NA)
    if (isTRUE(sg)) pd_warn(sprintf("%s 的模型为奇异拟合（isSingular=TRUE），随机效应可能过度参数化", y))

    # 固定效应系数
    cs <- summary(m)$coefficients
    coef_all[[y]] <- data.frame(
      variable = y, term = rownames(cs),
      Estimate = round(cs[, "Estimate"], 4),
      SE = round(cs[, "Std. Error"], 4),
      df = round(cs[, "df"], 2),
      t = round(cs[, "t value"], 4),
      p = signif(cs[, "Pr(>|t|)"], 4),
      sig = pd_sig(cs[, "Pr(>|t|)"]), stringsAsFactors = FALSE, row.names = NULL)

    # 类型 III 方差分析（Satterthwaite）
    at <- tryCatch(as.data.frame(stats::anova(m)), error = function(e) NULL)
    if (!is.null(at)) {
      at$term <- rownames(at)
      # ★★ 效应量口径修正（pitfalls I3，2026-09-25 实测修复）
      #   旧写法 eta = SS/sum(SS) —— 而 anova(lmerTest) 【没有 Residuals 行】，
      #   分母只有固定效应 SS 之和 → 恒加和为 1，既非 η² 也非 partial η²，系统性高估。
      #   改用 partial η² = SS / (SS + SS_resid)；SS_resid 用 sigma^2 × (n − rank(X)) 估计。
      #   算不出就退化为 ss_share_fixed（如实命名，不再叫 eta2）。
      ss_eff <- as.numeric(at[["Sum Sq"]])
      ss_res <- tryCatch({
        X <- lme4::getME(m, "X")
        stats::sigma(m)^2 * (stats::nobs(m) - qr(X)$rank)
      }, error = function(e) NA_real_)
      if (is.finite(ss_res) && ss_res > 0) {
        eta <- ss_eff / (ss_eff + ss_res)
        eta_nm <- "partial_eta2"
      } else {
        eta <- ss_eff / sum(ss_eff, na.rm = TRUE)
        eta_nm <- "ss_share_fixed"
        pd_msg(sprintf("[14] %s: 算不出残差 SS → 效应量退化为 ss_share_fixed（不是 eta²）", y))
      }
      anova_all[[y]] <- data.frame(variable = y, term = at$term,
        df_num = at$NumDF, df_den = round(at$DenDF, 2),
        F = round(at[["F value"]], 4),
        p = signif(at[["Pr(>F)"]], 4), sig = pd_sig(at[["Pr(>F)"]]),
        effect_size = round(eta, 4), effect_size_type = eta_nm,
        stringsAsFactors = FALSE, row.names = NULL)
    }

    # --- 方差成分：支持随机截距 + 随机斜率 ---
    # VarCorr[[1]] 在 (Season|Site) 时是 3x3 矩阵（截距/斜率/协方差），
    # 直接 as.numeric() 会得到 9 个数，塞进单列 data.frame 会报错 —— 见代码审查 P2
    vc_all <- as.data.frame(lme4::VarCorr(m))
    vc_all$variable <- y
    re_all[[y]] <- vc_all
    vmat <- as.matrix(lme4::VarCorr(m)[[1]])
    sdv  <- sqrt(diag(vmat))
    varr <- sum(diag(vmat))

    # --- R²：边际 / 条件 ---
    r2m <- tryCatch(MuMIn::r.squaredGLMM(m), error = function(e) NULL)
    if (is.null(r2m) && pd_has("performance")) {
      pr2 <- tryCatch(as.data.frame(performance::r2(m)), error = function(e) NULL)
      if (!is.null(pr2) && all(c("R2_marginal", "R2_conditional") %in% names(pr2))) {
        r2m <- matrix(c(pr2$R2_marginal[1], pr2$R2_conditional[1]), nrow = 1,
                      dimnames = list(NULL, c("R2m", "R2c")))
      }
    }
    if (is.null(r2m)) {
      # Nakagawa 兜底：固定效应部分必须用 var(Xβ)，不能用 var(fitted(m))
      # lmer 的 fitted() 已含随机效应 → 会把随机方差算进分子，R²m 高估（见代码审查 P7）
      Xb   <- as.vector(stats::model.matrix(m) %*% lme4::fixef(m))
      varf <- stats::var(Xb, na.rm = TRUE)
      res2 <- stats::sigma(m)^2
      r2m <- matrix(c(varf / (varf + varr + res2), (varf + varr) / (varf + varr + res2)),
                    nrow = 1, dimnames = list(NULL, c("R2m", "R2c")))
      pd_msg("[14] 注：MuMIn 与 performance 均不可用，R² 由内置 Nakagawa 公式计算")
    }
    aic <- stats::AIC(m); bic <- stats::BIC(m); ll <- as.numeric(stats::logLik(m))
    r2_all[[y]] <- data.frame(variable = y,
      R2marginal = round(r2m[1, "R2m"], 4), R2conditional = round(r2m[1, "R2c"], 4),
      AIC = round(aic, 2), BIC = round(bic, 2), logLik = round(ll, 2),
      singular = isTRUE(sg), n = nrow(dd),
      random_var = rand_var, n_random_terms = nrow(vmat),
      random_sd = paste(sprintf("%.4f", sdv), collapse = " / "),
      residual_sd = round(stats::sigma(m), 4), stringsAsFactors = FALSE)

    # 边际均值（emmeans）
    em <- tryCatch({
      e <- emmeans::emmeans(m, stats::as.formula(paste("~", paste(sprintf("`%s`", factors), collapse = " * "))))
      as.data.frame(summary(e))
    }, error = function(e) NULL)
    if (!is.null(em)) { em$variable <- y; emm_all[[y]] <- em }
    pd_msg(sprintf("[14] %s：R2m=%.3f R2c=%.3f AIC=%.1f%s",
                   y, r2m[1, "R2m"], r2m[1, "R2c"], aic, if (isTRUE(sg)) " [奇异拟合]" else ""))
  }
  bind <- function(l) if (length(l)) do.call(rbind, l) else data.frame()

  # glmm.hp 方差分解（可选）
  hp_out <- NULL
  if (isTRUE(cfg$opts$fit_r2_decomp)) {
    if (!pd_has("glmm.hp")) {
      pd_warn("需要 glmm.hp 才能做混合模型 R² 分解，已跳过（install.packages(\"glmm.hp\")）")
    } else if (length(vars)) {
      hp_out <- tryCatch({
        res <- lapply(vars, function(y) {
          form <- stats::as.formula(sprintf("`%s` ~ %s + %s", y, fixed, rs))
          m <- lmerTest::lmer(form, data = dat$meta)
          h <- glmm.hp::glmm.hp(m)
          # ★★ 元素名与列名修正（pitfalls I4，2026-09-25 实测修复）
          #   glmm.hp 1.0.0 返回元素是 hierarchical.partitioning（不是 h.part）：
          #     names(h) = r.squaredGLMM | hierarchical.partitioning | variables | type
          #   旧写法 h$h.part 为 NULL → "undefined columns selected" → 被 tryCatch 吞 →
          #   r2_decomp 永远空表。且 as.data.frame(...)[,1] 取到的是【Unique】不是 Individual。
          #   实测列名：Unique | Average.share | Individual | I.perc(%)
          hp <- h$hierarchical.partitioning %||% h$h.part
          if (is.null(hp)) stop("glmm.hp 未返回 hierarchical.partitioning")
          hp <- as.data.frame(hp)
          col <- if ("Individual" %in% names(hp)) "Individual" else names(hp)[1]
          data.frame(variable = y,
                     component = rownames(hp),
                     # glmm.hp 分解的是【边际 R²】（固定效应间分摊），标签写明口径
                     individual_contrib_to_marginal_R2 = round(as.numeric(hp[[col]]), 4),
                     stringsAsFactors = FALSE, row.names = NULL)
        })
        do.call(rbind, res)
      }, error = function(e) { pd_warn("glmm.hp 失败: ", conditionMessage(e)); NULL })
    }
  }

  out <- list(coefficients = bind(coef_all), anova = bind(anova_all),
              r2 = bind(r2_all), emmeans = bind(emm_all), r2_decomp = hp_out,
              random_effects = bind(re_all), random_structure = rs)
  if (save) pd_write_table(list(coefficients = out$coefficients, anova = out$anova,
                                model_fit = out$r2, random_effects = out$random_effects,
                                emmeans = out$emmeans,
                                r2_decomposition = if (is.null(hp_out)) data.frame() else hp_out,
                                run_info = data.frame(
                                  item = c("固定效应", "随机效应", "参考水平", "备注"),
                                  value = c(fixed, rs,
                                            if (length(ref_lv)) paste(names(ref_lv), unlist(ref_lv),
                                                                      sep = "=", collapse = "; ") else "未设定（用默认首水平）",
                                            "R2m/R2c 由 MuMIn::r.squaredGLMM（缺失时用 performance 或内置 Nakagawa）"),
                                  stringsAsFactors = FALSE)),
                           stem = "mixed", module = "14")
  if (is.null(hp_out)) pd_msg("[14] 提示：R² 分解未产出（缺 glmm.hp）。安装后可补齐该结果表。")
  invisible(out)
}
