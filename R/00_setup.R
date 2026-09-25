# ============================================================
# 00_setup.R · 环境、主题、工具、数据加载
# plant-div-pipeline
# 依赖：本文件不主动安装任何包；缺包时只提示，不报错退出。
# ============================================================

.pd <- new.env(parent = emptyenv())
.pd$cfg     <- NULL
.pd$logfile <- NULL
.pd$warn    <- character(0)

# ------------------------------------------------------------
# 0.1 环境初始化：Windows 下的中文 locale（见 references/03-pitfalls.md A1）
# ------------------------------------------------------------
pd_init_locale <- function(quiet = TRUE) {
  if (.Platform$OS.type == "windows") {
    cur <- Sys.getlocale("LC_CTYPE")
    if (!grepl("UTF-8|utf8|65001", cur)) {
      for (loc in c("Chinese_China.utf8", "zh_CN.UTF-8", "English_United States.utf8")) {
        ok <- tryCatch(suppressWarnings(Sys.setlocale("LC_CTYPE", loc)),
                       error = function(e) "")
        if (nzchar(ok)) {
          if (!quiet) message("[pd] LC_CTYPE -> ", ok)
          break
        }
      }
    }
  }
  invisible(Sys.getlocale("LC_CTYPE"))
}

# ------------------------------------------------------------
# 0.2 日志
# ------------------------------------------------------------
pd_setup <- function(cfg, quiet = FALSE) {
  pd_init_locale(quiet = quiet)
  for (k in c("code", "results", "figures", "logs", "tables", "cache")) {
    d <- cfg$paths[[k]]
    if (!is.null(d) && !is.na(d) && nzchar(d) && !dir.exists(d)) dir.create(d, recursive = TRUE)
  }
  # FIGURE_ONLY=TRUE 隐含 FORCE_RECALC=FALSE（只重画图，分析走缓存）
  if (isTRUE(cfg$opts$FIGURE_ONLY)) cfg$opts$FORCE_RECALC <- FALSE
  .pd$cfg <- cfg
  .pd$data_md5 <- pd_data_md5(cfg)     # G1：开跑快照，交付前用 pd_verify_data_unchanged() 比对
  .pd$logfile <- file.path(cfg$paths$logs,
                           sprintf("%s_%s.log", cfg$project, format(Sys.time(), "%Y%m%d_%H%M%S")))
  pd_msg("============================================================")
  pd_msg("plant-div-pipeline | project = ", cfg$project)
  pd_msg("R ", getRversion(), " | ", Sys.getlocale("LC_CTYPE"))
  pd_msg("[guard] data/ 快照已记（", length(.pd$data_md5), " 个文件）—— 永不改写")
  invisible(cfg)
}

pd_msg <- function(...) {
  txt <- paste0(...)
  cat(txt, "\n", sep = "")
  try(utils::flush(stdout()), silent = TRUE)   # 重定向到文件时也即时可见，便于盯长任务
  if (!is.null(.pd$logfile)) {
    try(cat(sprintf("[%s] %s\n", format(Sys.time(), "%H:%M:%S"), txt),
            file = .pd$logfile, append = TRUE), silent = TRUE)
  }
  invisible(txt)
}

pd_warn <- function(...) {
  txt <- paste0(...)
  .pd$warn <- c(.pd$warn, txt)
  pd_msg("[WARN] ", txt)
}

# ------------------------------------------------------------
# 0.3 缺包检查（优雅降级，见 SKILL.md）
# ------------------------------------------------------------
pd_has <- function(pkg) requireNamespace(pkg, quietly = TRUE)

pd_require <- function(pkgs, module = "?") {
  miss <- pkgs[!vapply(pkgs, pd_has, logical(1))]
  if (length(miss)) {
    cran <- miss[!miss %in% c("V.PhyloMaker2", "plantlist")]
    gh   <- miss[miss %in% c("V.PhyloMaker2", "plantlist")]
    pd_msg(sprintf("[SKIP] 模块 %s 缺少包: %s", module, paste(miss, collapse = ", ")))
    if (length(cran))
      pd_msg(sprintf("       安装: install.packages(c(%s))",
                     paste0('"', cran, '"', collapse = ", ")))
    if (length(gh))
      pd_msg(sprintf("       GitHub: remotes::install_github(%s)",
                     paste0(c('"jinyizju/V.PhyloMaker2"', '"helixcn/plantlist"')[c("V.PhyloMaker2","plantlist") %in% gh],
                            collapse = ", ")))
    pd_msg(sprintf("       本模块已跳过，后续模块继续。"))
    return(FALSE)
  }
  TRUE
}

# ------------------------------------------------------------
# 0.4 学名主键规范化（唯一入口，所有模块必须调用）
# ------------------------------------------------------------
normalize_species <- function(x) {
  x <- as.character(x)
  # 零宽与格式字符：直接删除（U+200B 零宽空格 / U+200C-NJ / U+200D-J / U+FEFF BOM）
  x <- gsub("[\u200b\u200c\u200d\ufeff]", "", x)
  # 各类 Unicode 空格：先转普通空格，再统一裁剪
  #   U+00A0 NBSP、U+1680 OGHAM、U+2000~U+200A、U+202F 窄NBSP、U+205F、U+3000 全角
  # 注意：trimws() 默认只认 [ \t\r\n]，不认这些 —— 不显式转换就会静默匹配失败
  x <- gsub("[\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000]", " ", x)
  x <- trimws(x)
  x <- gsub("[[:space:]]+", "_", x)
  x <- gsub("_+", "_", x)
  x <- sub("^_+", "", x); x <- sub("_+$", "", x)
  x
}

# 文本字段的不可见字符清理（不把空格换成下划线，用于 genus / family / 名称列）
# 场景：物种名单的 family 里混入 U+00A0（NBSP）时，V.PhyloMaker2 的
#       phylo.maker 会报 "Taxonomic classification not consistent"，
#       因为它的比较是严格字符串相等；且 trimws() 不认 NBSP。
pd_strip_invisible <- function(x) {
  x <- as.character(x)
  x <- gsub("[\u200b\u200c\u200d\ufeff]", "", x)
  x <- gsub("[\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000]", " ", x)
  trimws(gsub("[[:space:]]+", " ", x))
}

# 扫描文本向量中的不可见/可疑字符，返回 data.frame（供数据体检与排障使用）
pd_scan_invisible <- function(x, label = "value") {
  pat <- c("\u00a0" = "NBSP 不间断空格", "\u1680" = "OGHAM 空格",
           "\u2000" = "EN QUAD", "\u2002" = "EN SPACE", "\u2003" = "EM SPACE",
           "\u2007" = "FIGURE SPACE", "\u2009" = "THIN SPACE", "\u200a" = "HAIR SPACE",
           "\u200b" = "零宽空格", "\u200c" = "零宽非连接符", "\u200d" = "零宽连接符",
           "\u202f" = "窄 NBSP", "\u205f" = "MEDIUM MATH SPACE",
           "\u3000" = "全角空格", "\ufeff" = "BOM/零宽不换行空格",
           "\t" = "制表符")
  out <- list()
  for (ch in names(pat)) {
    hit <- which(grepl(ch, x, fixed = TRUE))
    if (length(hit))
      out[[length(out) + 1]] <- data.frame(
        label = label, char_name = unname(pat[ch]),
        code = sprintf("U+%04X", utf8ToInt(ch)),
        n_hits = length(hit), n_total = length(x),
        examples = paste(utils::head(x[hit], 3), collapse = " | "),
        stringsAsFactors = FALSE)
  }
  if (!length(out)) return(NULL)
  do.call(rbind, out)
}

# ------------------------------------------------------------
# 0.5 读表（csv/xlsx 自适应，UTF-8 优先）
# ------------------------------------------------------------
pd_read_table <- function(path, sheet = 1) {
  if (length(path) == 0 || is.na(path) || !nzchar(path)) return(NULL)
  if (!file.exists(path)) return(NULL)
  ext <- tolower(tools::file_ext(path))
  if (ext %in% c("csv", "txt", "tsv")) {
    sep <- if (ext == "tsv") "\t" else ","
    # 首行是 # 开头 → 视为注释块（如 05_env_simulated.csv 的「模拟数据」自证说明），
    # read.csv 默认 comment.char="" 会把注释行当数据读进来，这里自动跳过。
    first <- tryCatch(readLines(path, n = 1L, warn = FALSE, encoding = "UTF-8"),
                      error = function(e) "")
    cchar <- if (length(first) && startsWith(trimws(first[1]), "#")) "#" else ""
    for (enc in c("UTF-8-BOM", "UTF-8", "GBK")) {
      d <- tryCatch(utils::read.csv(path, header = TRUE, check.names = FALSE,
                                    fileEncoding = enc, stringsAsFactors = FALSE,
                                    sep = sep, comment.char = cchar),
                    error = function(e) NULL)
      if (!is.null(d) && ncol(d) >= 1) {
        attr(d, "pd_enc") <- enc
        return(d)
      }
    }
    pd_warn("读取失败（编码尝试 UTF-8-BOM/UTF-8/GBK 均失败）: ", path)
    return(NULL)
  }
  if (ext %in% c("xlsx", "xls")) {
    if (!pd_has("readxl")) { pd_warn("需要 readxl 才能读 xlsx: ", path); return(NULL) }
    d <- tryCatch(as.data.frame(readxl::read_excel(path, sheet = sheet)),
                  error = function(e) NULL)
    if (is.null(d)) pd_warn("读取失败: ", path)
    return(d)
  }
  pd_warn("不支持的文件类型: ", path)
  NULL
}

# ------------------------------------------------------------
# 0.5b 设计因子解析（唯一入口 —— 单/双因素开关）
#   config$design$factor_mode = "double" -> c("Habitat","Season")
#                            = "single" -> c("Season")
#   未设 factor_mode 时回落 config$design$factors（向后兼容）
#   config$table$factors 若显式给了则优先（70 论文表格可单独覆盖），否则用 design
#   好处：消掉各模块散落的 factors[1]/[2] 取值，单因素模式只改一处
# ------------------------------------------------------------
# ------------------------------------------------------------
# 00.x 采样设计（2026-09-25 新增）—— 决定哪些模块适用、随机效应用谁
# ------------------------------------------------------------
#' 三个取值：
#'   "fixed_plot"   固定样方跟踪（同一样地跨时间重复采样）→ 重复测量
#'   "fixed_site"   站固定、站内样方每季重选（示例数据）→ 独立观测 + Site 空间区组
#'   "independent"  全独立
#' 缺省当 "fixed_site"（最常见、最保守的独立样本口径）。
pd_design_sampling <- function(cfg = .pd$cfg) {
  s <- cfg$design$sampling %||% "fixed_site"
  s <- as.character(s)[1]
  if (!s %in% c("fixed_plot", "fixed_site", "independent")) {
    pd_warn("design$sampling 取值 '", s, "' 不认识，回退 fixed_site；",
            "可选 fixed_plot | fixed_site | independent")
    s <- "fixed_site"
  }
  s
}

# 是否为「固定样方跟踪」设计（只有这种才有时间自相关可测）
pd_is_fixed_plot <- function(cfg = .pd$cfg) identical(pd_design_sampling(cfg), "fixed_plot")

# 该设计下推荐的随机效应公式（供 14_mixed_model 兜底；推不出返回 NULL 要求显式配置）
pd_suggest_random <- function(cfg = .pd$cfg) {
  s <- pd_design_sampling(cfg)
  r <- cfg$design$random
  if (identical(s, "fixed_plot")) {
    u <- r %||% "plot"
    return(sprintf("(1|%s)", u))
  }
  if (identical(s, "fixed_site")) {
    u <- r %||% "Site"
    return(sprintf("(1|%s)", u))
  }
  NULL            # independent：不设随机效应
}

# ------------------------------------------------------------
# 会话信息（2026-09-25）—— 交付附一份，保证可复现
# ------------------------------------------------------------
pd_write_session_info <- function(cfg = .pd$cfg) {
  outdir <- file.path(cfg$paths$root %||% ".", cfg$paths$results %||% "results")
  if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)
  f <- file.path(outdir, "00_session_info.txt")
  pk <- c("vegan", "betapart", "FD", "picante", "ape", "V.PhyloMaker2", "phylosignal",
          "multcomp", "lme4", "lmerTest", "emmeans", "glmm.hp", "dunn.test", "rcompanion",
          "PMCMRplus", "corrplot", "flextable", "officer", "openxlsx", "readxl",
          "MCMCglmm", "nlme", "permute", "ggplot2")
  lines <- c(
    paste0("# plant-div-pipeline 会话信息  ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    paste0("R.version.string: ", R.version.string),
    paste0("platform: ", R.version$platform),
    "",
    "# 关键包版本（NA = 未安装）",
    vapply(pk, function(p)
      sprintf("  %-16s %s", p, if (requireNamespace(p, quietly = TRUE))
        as.character(utils::packageVersion(p)) else "NA"), character(1)),
    "", "# sessionInfo()", capture.output(print(utils::sessionInfo()))
  )
  writeLines(lines, f, useBytes = TRUE)
  pd_msg("[session] 会话信息已写: ", basename(f))
  invisible(f)
}
#' 自由置换是默认（生态学主流）。随机区组/重复测量设计下，可交换性被区组破坏，
#' 应在区组内置换。实测 E2：示例数据自由 vs 受限 0 翻转（效应太强、p 触底），
#' 故【默认不改】，只提供开关。取舍见 pitfalls I10。
pd_perm_ctrl <- function(cfg = .pd$cfg, mt = NULL, nperm = NULL) {
  blk <- cfg$opts$restrict_perm
  nperm <- nperm %||% (cfg$opts$permutations %||% 999)
  if (is.null(blk) || !nzchar(as.character(blk)[1]) || is.na(as.character(blk)[1])) return(nperm)
  if (!pd_has("permute")) {
    pd_warn("restrict_perm 需要 permute 包（install.packages(\"permute\")）→ 退回自由置换")
    return(nperm)
  }
  if (is.null(mt) || !(blk %in% names(mt))) {
    pd_warn("restrict_perm 的分组列 \"", blk, "\" 不在元数据中 → 退回自由置换")
    return(nperm)
  }
  ctrl <- permute::how(nperm = nperm)
  permute::setBlocks(ctrl) <- factor(mt[[blk]])
  pd_msg("[perm] 受限置换：blocks = ", blk, "（", length(unique(mt[[blk]])), " 个区组）")
  ctrl
}

pd_design_factors <- function(cfg = .pd$cfg, source = c("design", "table")) {  source <- match.arg(source)
  if (identical(source, "table")) {
    tf <- cfg$table$factors
    if (!is.null(tf) && length(tf) && !all(is.na(tf))) return(as.character(tf))
  }
  mode <- cfg$design$factor_mode %||% NA_character_
  if (!is.na(mode) && identical(mode, "single")) {
    t <- cfg$design$time %||% "Season"
    if (is.na(t)) t <- (cfg$design$factors %||% "Season")[1]
    return(as.character(t))
  }
  if (!is.na(mode) && identical(mode, "double")) {
    f <- cfg$design$factors
    if (length(f) >= 2) return(as.character(f[1:2]))
    # 只声明了一个因子就退化成单因素，并提示
    pd_warn("factor_mode='double' 但 design$factors 只有 ", length(f),
            " 个，已退化为单因素")
    return(as.character(f))
  }
  as.character(cfg$design$factors %||% "Season")
}

# 是否双因素（用于各模块决定要不要交互项/第二因子分支）
pd_is_double <- function(cfg = .pd$cfg) length(pd_design_factors(cfg)) >= 2

# ------------------------------------------------------------
# 0.6 数据加载（五文件契约 → 标准对象）
# ------------------------------------------------------------
# ------------------------------------------------------------
# 00.x 响应指数回填：results/*.xlsx → meta（只并内存，绝不写回 CSV）
# ------------------------------------------------------------
#' 为什么需要（2026-09-25）：
#'   config$response 可能声明 meta 里没有的列（Simpson / NTI / NRI …）。
#'   10_alpha、20_fd、31_pd_nti_nri 是算完写 results/ 的，不回填就永远进不了
#'   12/52/60/43 的响应集。回填按 sample_id 对齐，缺哪列补哪列。
#'   ★ 绝不改写 data/*.csv —— 封丘真实植物数据有 md5 校验（00-data-contract.md）
#'   ★ opts$enrich_meta = FALSE 可关掉（需要严格复现旧口径时）
pd_enrich_meta <- function(mt, cfg = .pd$cfg) {
  if (is.null(mt) || !nrow(mt)) return(mt)
  if (!isTRUE(cfg$opts$enrich_meta %||% TRUE)) return(mt)
  id <- cfg$key$sample_id %||% "sample_id"
  if (!(id %in% names(mt))) return(mt)

  want <- unique(unlist(cfg$response[c("alpha", "func", "phylo", "community")]))
  want <- want[!is.na(want) & nzchar(as.character(want))]
  miss <- want[!want %in% names(mt)]
  if (!length(miss)) return(mt)
  if (!pd_has("readxl")) return(mt)

  res_dir <- cfg$paths$results
  if (is.null(res_dir) || !dir.exists(res_dir)) return(mt)
  files <- sort(list.files(res_dir, pattern = "\\.xlsx$", full.names = TRUE))
  if (!length(files)) return(mt)

  idv <- as.character(mt[[id]])
  for (f in files) {
    if (!length(miss)) break
    sheets <- tryCatch(readxl::excel_sheets(f), error = function(e) character(0))
    for (sn in sheets) {
      if (!length(miss)) break
      d <- tryCatch(as.data.frame(readxl::read_excel(f, sheet = sn)),
                    error = function(e) NULL)
      if (is.null(d) || !nrow(d) || !ncol(d)) next
      # 表里的 key 列：优先 sample_id；row_id 是 pd_write_table 塞的行名，也能当 key
      kc <- intersect(c(id, "sample_id", "row_id"), names(d))
      if (!length(kc)) next
      kc <- kc[1]
      hit <- intersect(miss, names(d))
      if (!length(hit)) next
      key <- as.character(d[[kc]])
      # ★ 必须真的对得上 sample_id 才并（防 row_id=1,2,3 之类的假 key）
      if (!any(idv %in% key)) next
      for (v in hit) {
        mt[[v]] <- d[[v]][match(idv, key)]
        pd_msg(sprintf("[data] meta 缺列 %s ← %s:%s（按 %s 对齐）", v, basename(f), sn, kc))
      }
      miss <- setdiff(miss, hit)
    }
  }
  if (length(miss))
    pd_msg(sprintf("[data] 响应变量 %s 不在 meta 也不在 results/ —— 先跑对应模块，或在 %s 里加列",
                   paste(miss, collapse = ", "), cfg$files$meta))
  mt
}

pd_load_data <- function(cfg = .pd$cfg, need = c("abundance", "meta")) {
  f <- cfg$files
  out <- list()
  info <- list()

  # --- 多度矩阵 ---
  ab <- pd_read_table(f$abundance)
  if (is.null(ab)) stop("多度矩阵读取失败: ", f$abundance, call. = FALSE)
  id_col <- names(ab)[1]
  n_species_raw <- ncol(ab) - 1
  na_cells <- sum(is.na(ab[, -1, drop = FALSE]))
  if (isTRUE(cfg$opts$na_to_zero) && na_cells > 0) {
    ab[, -1][is.na(ab[, -1, drop = FALSE])] <- 0
    pd_msg(sprintf("[data] 多度矩阵 NA -> 0：替换 %d 个格子（见 pitfalls C1）", na_cells))
  }
  sid <- as.character(ab[[1]])
  sp_raw <- names(ab)[-1]
  sp_new <- normalize_species(sp_raw)
  n_dup <- sum(duplicated(sp_new))
  if (n_dup > 0) {
    dup <- unique(sp_new[duplicated(sp_new)])
    stop("规范化后学名重复 ", n_dup, " 个：", paste(dup, collapse = ", "),
         "\n请先修数据（references/00-data-contract.md §3）", call. = FALSE)
  }
  changed <- sum(sp_raw != sp_new)
  if (changed > 0)
    pd_msg(sprintf("[data] 学名规范化：%d/%d 个列名被修改（尾空格/空白等，见 pitfalls B2）",
                   changed, length(sp_raw)))
  m <- as.matrix(ab[, -1, drop = FALSE])
  storage.mode(m) <- "double"
  rownames(m) <- sid
  colnames(m) <- sp_new
  zero_cols <- which(colSums(m, na.rm = TRUE) == 0)
  if (length(zero_cols)) {
    pd_msg(sprintf("[data] 剔除全 0 物种列 %d 个: %s", length(zero_cols),
                   paste(head(colnames(m)[zero_cols], 10), collapse = ", ")))
    m <- m[, -zero_cols, drop = FALSE]
  }
  if (cfg$opts$rare_remove_min_occ > 0) {
    keep <- colSums(m > 0) >= cfg$opts$rare_remove_min_occ
    pd_msg(sprintf("[data] 稀有物种剔除（出现样方 < %d）：保留 %d / %d",
                   cfg$opts$rare_remove_min_occ, sum(keep), length(keep)))
    m <- m[, keep, drop = FALSE]
  }
  out$abundance <- m
  info$abundance <- list(rows = nrow(m), species = ncol(m),
                         species_raw = n_species_raw, name_changed = changed,
                         na_to_zero = na_cells, enc = attr(ab, "pd_enc"))

  # --- 元数据 ---
  mt <- pd_read_table(f$meta)
  if (is.null(mt)) stop("元数据读取失败: ", f$meta, call. = FALSE)
  mt[[1]] <- as.character(mt[[1]])
  names(mt)[1] <- cfg$key$sample_id
  ord_lv <- cfg$design$ordered_levels
  for (fn in cfg$design$factors) {
    if (!fn %in% names(mt)) {
      pd_warn(sprintf("元数据缺少声明的因子列 '%s'（config$design$factors）", fn))
      next
    }
    mt[[fn]] <- factor(trimws(as.character(mt[[fn]])))
    if (!is.null(ord_lv[[fn]])) {
      lv <- ord_lv[[fn]]
      if (!all(lv %in% levels(mt[[fn]])))
        pd_warn(sprintf("因子 %s 的 ordered_levels 与实际水平不符。实际: %s",
                        fn, paste(levels(mt[[fn]]), collapse = ", ")))
      mt[[fn]] <- factor(mt[[fn]], levels = lv)
    }
  }
  for (rc in setdiff(c(cfg$design$random, cfg$design$time), c(NA, cfg$design$factors))) {
    if (!is.null(rc) && !is.na(rc) && nzchar(rc) && rc %in% names(mt)) {
      mt[[rc]] <- factor(trimws(as.character(mt[[rc]])))
      if (!is.null(ord_lv[[rc]])) mt[[rc]] <- factor(mt[[rc]], levels = ord_lv[[rc]])
    }
  }
  out$meta <- mt
  info$meta <- list(rows = nrow(mt), cols = names(mt))

  # ★ 把 results/ 里已算好的响应指数并进 meta（只并内存，不改写 CSV）
  #   为什么需要：response 可能声明了 meta 里没有的列（如 Simpson / NTI / NRI），
  #   而 10_alpha / 31_pd_nti_nri 是算完写 results/ 的，不回填就永远进不了 12/52/60/43。
  #   ★ 绝不改写 data/*.csv —— 封丘真实数据有 md5 校验（见 00-data-contract.md）
  n_before <- ncol(out$meta)
  out$meta <- pd_enrich_meta(out$meta, cfg = cfg)
  if (ncol(out$meta) != n_before)
    info$meta$cols_enriched <- setdiff(names(out$meta), names(mt))

  # ★ 口径校验（2026-09-25，pitfalls I26）：SES 类列应当近似均值 0
  #   config$phylo 用 mntd/mpd，table$vars 用 "SES.MNTD"，靠别名映射；
  #   若数据里放的是【原始 MNTD/MPD】，别名会把未标准化值当 SES 标注。这里报警。
  for (cc in c("mntd", "mpd", "NTI", "NRI")) {
    if (cc %in% names(out$meta)) {
      v <- suppressWarnings(as.numeric(out$meta[[cc]]))
      v <- v[is.finite(v)]
      if (length(v) >= 5) {
        mu <- mean(v); sdv <- stats::sd(v)
        looks_ses <- abs(mu) < 1 && sdv > 0.05 && sdv < 6
        info$meta[[paste0("ses_like_", cc)]] <- looks_ses
        if (!looks_ses)
          pd_msg(sprintf("[data] %s 的均值=%.3f / sd=%.3f —— 不像标准化效应量（SES 应均值≈0）；",
                         cc, mu, sdv),
                 "若这是原始 MNTD/MPD，请改名避免被当 SES 标注")
      }
    }
  }

  # --- sample_id 一一对应 ---
  a <- rownames(out$abundance); b <- as.character(mt[[cfg$key$sample_id]])
  only_a <- setdiff(a, b); only_b <- setdiff(b, a)
  info$id_check <- list(only_in_abundance = only_a, only_in_meta = only_b,
                        matched = sum(a %in% b))
  if (length(only_a)) pd_warn(sprintf("仅出现在多度矩阵的 sample_id（%d 个）: %s",
                                      length(only_a), paste(head(only_a, 10), collapse = ", ")))
  if (length(only_b)) pd_warn(sprintf("仅出现在元数据的 sample_id（%d 个）: %s",
                                      length(only_b), paste(head(only_b, 10), collapse = ", ")))

  # --- 性状表 ---
  if (!is.na(f$traits) && nzchar(f$traits)) {
    tr <- pd_read_table(f$traits)
    if (!is.null(tr)) {
      names(tr)[1] <- cfg$key$species
      tr[[cfg$key$species]] <- normalize_species(tr[[cfg$key$species]])
      if (anyDuplicated(tr[[cfg$key$species]]))
        pd_warn("性状表存在重复物种行，已保留首行；请核实。")
      tr <- tr[!duplicated(tr[[cfg$key$species]]), , drop = FALSE]
      out$traits <- tr
      info$traits <- list(rows = nrow(tr), traits = ncol(tr) - 1)
    }
  }

  # --- 物种对照表 ---
  if (!is.na(f$species) && nzchar(f$species)) {
    sp <- pd_read_table(f$species)
    if (!is.null(sp)) {
      names(sp)[1] <- cfg$key$species
      sp[[cfg$key$species]] <- normalize_species(sp[[cfg$key$species]])
      out$species <- sp
      info$species <- list(rows = nrow(sp))
    }
  }

  # --- 系统发育树 ---
  if (!is.na(f$phylo) && nzchar(f$phylo)) {
    if (!pd_has("ape")) {
      pd_warn("需要 ape 才能读树；已跳过。")
    } else if (file.exists(f$phylo)) {
      tr <- tryCatch(ape::read.tree(f$phylo), error = function(e) NULL)
      if (is.null(tr)) {
        pd_warn("树文件读取失败: ", f$phylo)
      } else {
        raw <- tr$tip.label
        tr$tip.label <- normalize_species(raw)
        if (anyDuplicated(tr$tip.label)) {
          pd_warn("树 tip 规范化后出现重复，已去重（保留首次出现）。")
          tr <- ape::drop.tip(tr, tr$tip.label[duplicated(tr$tip.label)])
        }
        changed <- sum(raw != tr$tip.label)
        if (changed > 0)
          pd_msg(sprintf("[data] 树 tip 规范化：%d 个被修改（尾空格等，见 pitfalls B1）", changed))
        out$tree <- tr
        info$tree <- list(tips = length(tr$tip.label), changed = changed,
                          has_branch_length = !is.null(tr$edge.length))
        if (is.null(tr$edge.length))
          pd_warn("树没有枝长，PD/MNTD 无法计算，请改用有枝长的树。")
      }
    } else pd_warn("树文件不存在: ", f$phylo)
  }

  out$info <- info
  out$sample_id <- a
  out
}

# ------------------------------------------------------------
# 0.7 四方物种名对齐（体检与各模块共用）
# ------------------------------------------------------------
pd_species_align <- function(dat, cfg = .pd$cfg) {
  emb <- colnames(dat$abundance)
  trt <- if (!is.null(dat$traits)) dat$traits[[cfg$key$species]] else character(0)
  lst <- if (!is.null(dat$species)) dat$species[[cfg$key$species]] else character(0)
  tre <- if (!is.null(dat$tree)) dat$tree$tip.label else character(0)
  sets <- list(abundance = emb, traits = trt, species_list = lst, tree = tre)
  sets <- sets[vapply(sets, length, integer(1)) > 0]
  allsp <- sort(unique(unlist(sets)))
  mat <- data.frame(species = allsp, stringsAsFactors = FALSE)
  for (nm in names(sets)) mat[[nm]] <- allsp %in% sets[[nm]]
  core <- Reduce(intersect, sets)
  list(table = mat, sets = sets, core = core,
       counts = vapply(sets, length, integer(1)),
       n_core = length(core),
       only = lapply(sets, function(s) setdiff(s, core)))
}

# ------------------------------------------------------------
# 0.7b 疑似同物异名诊断（实测于封丘：性状表与多度矩阵只有 101/150 字面匹配）
# 原理：两边都有同一个属，但种加词完全不同 → 极可能来自不同分类学骨架
#       （如 TRY 按属匹配留下的痕迹：Afroaster_hispidus vs Aster_hispidus）
# ------------------------------------------------------------
pd_suspect_synonyms <- function(al) {
  s <- al$sets
  if (length(s) < 2) return(data.frame())
  genus <- function(v) sub("_.*$", "", v)
  epit  <- function(v) sub("^[^_]+_?", "", v)
  out <- list()
  nm <- names(s)
  for (i in seq_len(length(nm) - 1)) for (j in (i + 1):length(nm)) {
    a <- s[[nm[i]]]; b <- s[[nm[j]]]
    if (!length(a) || !length(b)) next
    ga <- genus(a); gb <- genus(b)
    common_g <- intersect(unique(ga), unique(gb))
    for (g in common_g) {
      ea <- sort(unique(epit(a[ga == g]))); eb <- sort(unique(epit(b[gb == g])))
      if (!length(ea) || !length(eb)) next
      if (length(intersect(ea, eb)) == 0)          # 同属但种加词完全不重叠 → 可疑
        out[[length(out) + 1]] <- data.frame(
          set_A = nm[i], set_B = nm[j], genus = g,
          epithets_A = paste(ea, collapse = " / "),
          epithets_B = paste(eb, collapse = " / "),
          stringsAsFactors = FALSE)
    }
  }
  if (!length(out)) return(data.frame())
  do.call(rbind, out)
}

# ------------------------------------------------------------
# 0.7b 模块级 .rds 缓存（pitfalls E9）
#   目标：改样式后秒级重出图，不重跑检验/模拟。
#   失效键 = 数据文件 md5 + 影响统计的 opts 参数签名
#   FORCE_RECALC = TRUE  → 无视缓存重算并覆盖
#   FIGURE_ONLY  = TRUE  → 分析全走缓存，只重画图
# ------------------------------------------------------------
pd_cache_dir <- function(cfg = .pd$cfg) {
  d <- cfg$paths$cache %||% file.path(cfg$paths$root %||% ".", "cache")
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

pd_cache_path <- function(stem, cfg = .pd$cfg) {
  file.path(pd_cache_dir(cfg), sprintf("%s.rds", gsub("[^A-Za-z0-9_]", "_", stem)))
}

# 失效键：数据文件 md5 + 影响统计的 opts 签名（改样式不影响键 → 命中缓存）
pd_cache_key <- function(cfg = .pd$cfg) {
  files <- unlist(cfg$files)
  files <- files[!is.na(files) & nzchar(files) & file.exists(files)]
  md5 <- if (length(files)) unname(tools::md5sum(files)) else "no_file"
  o <- cfg$opts %||% list()
  # 只取影响统计结果的参数（样式参数不进键 → 改样式不触发重算）
  stat_keys <- c("seed", "alpha", "multiple_adj", "alpha_test", "include_interaction",
                 "letter_method", "distance", "permanova_by", "permanova_model",
                 "runs", "permutations", "null_model", "abundance_weighted",
                 "random_structure", "rarefy", "trait_input", "varpart_coding",
                 "varpart_community_transform", "mcmc_nitt", "mcmc_burnin", "mcmc_thin",
                 "mcmc_random", "hcpc_nclust", "pheatmap_dist", "pheatmap_method",
                 "lipa_reps", "phylo_sim_nsim", "phylo_sim_reps", "tree_scenario",
                 "pca_ncp", "ref_levels",
                 # ★ 2026-09-25 新增口径开关（改口径必须触发重算，否则吃到旧缓存）
                 "dca_gradient", "rda_scale", "mds_autotransform", "jaccard_binary",
                 "signal_p_adjust", "reg_p_adjust", "spearman_p_adjust", "anova_type",
                 "restrict_perm", "sampling", "impute_max_miss", "impute_max_nrmse",
                 "signal_reps", "abundance_is_iv")
  sig <- vapply(stat_keys, function(k) {
    v <- o[[k]]
    if (is.null(v)) NA_character_ else paste(as.character(v), collapse = "|")
  }, character(1))
  paste(c(md5, names(sig)[!is.na(sig)], sig[!is.na(sig)]), collapse = "\n")
}

pd_cache_get <- function(stem, key = NULL, cfg = .pd$cfg) {
  if (isTRUE(cfg$opts$FORCE_RECALC)) return(NULL)
  p <- pd_cache_path(stem, cfg)
  if (!file.exists(p)) return(NULL)
  obj <- tryCatch(readRDS(p), error = function(e) { pd_warn("缓存读取失败: ", p); NULL })
  if (is.null(obj)) return(NULL)
  if (!is.null(key) && !identical(obj$.__key, key)) {
    pd_msg("[cache] ", stem, " 失效键不匹配（数据或参数已变），重算")
    return(NULL)
  }
  pd_msg("[cache] hit ", stem, if (isTRUE(cfg$opts$FIGURE_ONLY)) "  (FIGURE_ONLY → 只重画图)")
  obj$.__value
}

pd_cache_set <- function(stem, value, key = NULL, cfg = .pd$cfg) {
  p <- pd_cache_path(stem, cfg)
  obj <- list(.__key = key, .__value = value, .__when = Sys.time())
  tryCatch(saveRDS(obj, p), error = function(e) pd_warn("缓存写入失败: ", p, " — ", conditionMessage(e)))
  invisible(value)
}

# 包一层缓存的通用执行器：包住**昂贵计算**（绘图总是重画 → 改样式秒级重出）
#   FORCE_RECALC=TRUE → 无视缓存重算
#   key=NULL → 自动按数据 md5 + opts 签名算
pd_cached <- function(stem, key = NULL, expr, cfg = .pd$cfg) {
  if (is.null(key)) key <- pd_cache_key(cfg)
  if (!isTRUE(cfg$opts$FORCE_RECALC)) {
    hit <- pd_cache_get(stem, key, cfg)
    if (!is.null(hit)) return(hit)
  }
  val <- force(expr)
  pd_cache_set(stem, val, key, cfg)
  val
}

# ------------------------------------------------------------
# 0.8 出版级主题与导出（pt 绝对字号 + 物理尺寸）
# ------------------------------------------------------------
# 出版主题：pt 绝对字号 + 物理尺寸（pitfalls E1）。
# 对齐论文原图风格（Ecological indicators 接收版）：
#   论文用 theme_bw() + rel(1.2)/rel(1.5) + gray80 主网格。
#   本包禁用 rel()（pitfalls E1），故把 rel(1.2)/rel(1.5) 换算成 base_pt 绝对偏移，
#   保留论文的层级比例：rel(1.2)@base11=13.2pt -> base_pt+2；rel(1.5)=16.5pt -> base_pt+5。
#   若并排比对后字号仍偏小，改 config$plot$base_pt（9→10/11），不要把绝对 pt 写死进这里。
pd_theme_mdpi <- function(base_size = NULL, cfg = .pd$cfg) {
  # ★ 逐条抄 Diversity 2023（MDPI）RDA代码.txt 的 theme —— 那篇的图型（RDA/回归）
  #   用这一套，不用 pd_theme（那是封丘 EI 风格：gray80 网格、无面板边框）
  #   原文：panel.background 白底黑边 / panel.grid 空 / axis.line 黑
  #         axis.title & axis.text size=18 / text family="B"(Arial) size=20
  #         axis.ticks.length = 0.4 lines
  #   base_size 映射：原文 18pt 是在 6×6 in 图上；这里按 skill 的 pt 体系给，
  #   默认 base_pt+9（≈18pt），要更大改 config$plot$base_pt
  bs <- base_size %||% ((cfg$plot$base_pt %||% 9) + 9)
  ggplot2::theme_bw(base_size = bs) +
    ggplot2::theme(
      panel.background = ggplot2::element_rect(fill = "white", colour = "black"),
      panel.grid       = ggplot2::element_blank(),
      axis.line        = ggplot2::element_line(colour = "black"),
      axis.ticks       = ggplot2::element_line(colour = "black"),
      axis.ticks.length = grid::unit(0.4, "lines"),
      axis.title       = ggplot2::element_text(colour = "black", size = bs),
      axis.text        = ggplot2::element_text(colour = "black", size = bs),
      legend.title     = ggplot2::element_blank(),
      legend.key       = ggplot2::element_blank(),
      legend.text      = ggplot2::element_text(size = bs),
      plot.title       = ggplot2::element_text(size = bs + 4, colour = "black",
                                               face = "bold", hjust = 0.5),
      text = ggplot2::element_text(family = cfg$plot$font_en %||% "Arial", size = bs + 2)
    )
}

# ------------------------------------------------------------
# 0.9a2 pd_theme_isme —— 排序双标图主题（Fig3b_dbRDA_rf_gam 面板 A 风格）
#   逐条抄 `03-生态学数据分析/R代码/00c_setup_and_data_preparation.R` 的 theme_isme()：
#     theme_bw + 无网格 + panel.border 黑 0.5 + Arial
#     axis.line/ticks 黑 0.35；ticks.length 0.15cm
#     S_TICK=8 / S_TTL=9 / S_LEG=7.5 / S_ANN=7.5 / S_TAG=10
#   与 pd_theme_mdpi 的差别：mdpi 是 axis.text=bs(≈18pt) 大字、ticks 0.4 lines；
#   isme 是 8/9pt 小字 + 紧凑 ticks + 显式 panel.border。42 用 isme，43/52 仍用 mdpi。
# ------------------------------------------------------------
pd_theme_isme <- function(base_size = NULL, cfg = .pd$cfg) {
  # 字号按原文绝对 pt（S_TICK=8 / S_TTL=9），不走 base_pt 偏移
  s_tick <- cfg$plot$s_tick %||% 8
  s_ttl  <- cfg$plot$s_ttl  %||% 9
  s_leg  <- cfg$plot$s_leg  %||% 7.5
  fam    <- cfg$plot$font_en %||% "Arial"
  ggplot2::theme_bw(base_size = base_size %||% s_ttl) +
    ggplot2::theme(
      text              = ggplot2::element_text(family = fam),
      panel.grid.major  = ggplot2::element_blank(),
      panel.grid.minor  = ggplot2::element_blank(),
      panel.border      = ggplot2::element_rect(colour = "black", linewidth = 0.5, fill = NA),
      panel.background  = ggplot2::element_rect(fill = "white"),
      axis.line         = ggplot2::element_line(linewidth = 0.35, colour = "black"),
      axis.text         = ggplot2::element_text(size = s_tick, colour = "black", family = fam),
      axis.title        = ggplot2::element_text(size = s_ttl, colour = "black"),
      axis.ticks        = ggplot2::element_line(colour = "black", linewidth = 0.35),
      axis.ticks.length = grid::unit(0.15, "cm"),
      legend.title      = ggplot2::element_text(size = s_leg, colour = "black", face = "bold"),
      legend.text       = ggplot2::element_text(size = s_leg, colour = "black"),
      legend.key.size   = grid::unit(0.35, "cm"),
      legend.background = ggplot2::element_rect(fill = "white", colour = NA),
      legend.box.spacing = grid::unit(0.1, "cm"),
      legend.spacing    = grid::unit(0.05, "cm"),
      strip.text        = ggplot2::element_text(size = s_leg, face = "bold"),
      strip.background  = ggplot2::element_blank(),
      # 注：ggplot2 4.x 移除了 strip.border，不设它（设了会告警）
      plot.title        = ggplot2::element_text(size = s_ttl, face = "bold", hjust = 0.5),
      plot.subtitle     = ggplot2::element_text(size = s_ttl, hjust = 0.5),
      plot.margin       = ggplot2::margin(4, 4, 4, 4, unit = "pt")
    )
}

# 图例内嵌右下角（原文 legend_inside()）—— 供 42 与后续排序图复用
#   注：theme() 不吃 !!! 注入 → 必须 do.call(theme, pd_legend_inside())
pd_legend_inside <- function(pos = c(0.99, 0.01), cfg = .pd$cfg) {
  s_leg <- cfg$plot$s_leg %||% 7.5
  list(
    legend.position        = "inside",
    legend.position.inside = pos,
    legend.justification   = c(1, 0),
    legend.key             = ggplot2::element_blank(),
    legend.background      = ggplot2::element_rect(fill = "white", colour = NA),
    legend.key.size        = grid::unit(0.3, "cm"),
    legend.title           = ggplot2::element_text(size = s_leg, face = "bold"),
    legend.text            = ggplot2::element_text(size = s_leg)
  )
}

# geom_text/geom_text_repel 的 size 单位是 mm，pt → mm（原文 pt2gg）
pd_pt2gg <- function(pt) pt * 0.352778

pd_theme <- function(base_pt = NULL, lang = NULL,
                     grid = c("major", "none"),   # 论文箱线/NMDS/PCA 有 gray80 主网格；地图用 none
                     family = NULL,                # Fig 5 (PD/SES.MNTD) 论文用 Times New Roman
                     compact = FALSE) {            # TRUE = 旧紧凑字号（多面板诊断图防溢出）
  cfg <- .pd$cfg
  grid <- match.arg(grid)
  base_pt <- base_pt %||% (cfg$plot$base_pt %||% 9)
  lang    <- lang    %||% (cfg$plot$lang %||% "en")
  tier1 <- if (compact) base_pt - 0.5 else base_pt + 2   # 对应论文 rel(1.2) 层
  tier2 <- if (compact) base_pt + 1   else base_pt + 5   # 对应论文 rel(1.5) 层
  fam <- family %||% if (identical(lang, "zh")) (cfg$plot$font_zh %||% "SimSun")
                     else (cfg$plot$font_en %||% "sans")
  ggplot2::theme_bw(base_size = base_pt, base_family = fam) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = if (identical(grid, "major"))
        ggplot2::element_line(colour = "gray80", linewidth = 0.2) else ggplot2::element_blank(),
      strip.background = ggplot2::element_rect(fill = "grey95", colour = "grey30"),
      strip.text  = ggplot2::element_text(size = tier1, face = "bold"),
      axis.text   = ggplot2::element_text(size = tier1, colour = "black"),
      axis.title  = ggplot2::element_text(size = tier1),
      legend.text = ggplot2::element_text(size = tier1),
      legend.title= ggplot2::element_text(size = tier1),
      plot.title  = ggplot2::element_text(size = tier2, face = "bold", hjust = 0.5),
      legend.key.size = grid::unit(1.2, "lines"),
      legend.background = ggplot2::element_rect(fill = "transparent", colour = NA),
      # ★ 全局统一：图例一律放底部（用户第 3 轮）。右侧图例吃宽度、挤压绘图区。
      legend.position = "bottom",
      legend.direction = "horizontal"
    )
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || is.na(a[1])) b else a

pd_size_mm <- function(cfg = .pd$cfg, what = NULL) {
  s <- cfg$plot$size %||% "double"
  if (!is.null(what)) return(what)
  if (identical(s, "single")) 90 else if (identical(s, "double")) 190 else cfg$plot$width_mm
}

# ------------------------------------------------------------
# 0.10b 数据护栏（2026-09-25）—— data/*.csv 永不改写
#   封丘真实植物数据有 md5 约定（references/00-data-contract.md §6）。
#   pd_assert_not_data()      : 4 个写出口统一拦截，落盘路径解析后不得在 data/ 下
#   pd_verify_data_unchanged(): 交付前比对 md5 快照，变了就 stop
#   ★ 这是硬门槛，不是措辞警告 —— 旧版只有注释，代码层不拦（00-data-contract.md 曾自承）
# ------------------------------------------------------------
pd_data_dir <- function(cfg = .pd$cfg) {
  d <- cfg$paths$data %||% "data"
  if (!grepl("^(/|[A-Za-z]:)", d)) d <- file.path(cfg$paths$root %||% ".", d)
  normalizePath(d, winslash = "/", mustWork = FALSE)
}

pd_assert_not_data <- function(path, cfg = .pd$cfg) {
  if (is.null(path) || !length(path) || !nzchar(path[1])) return(invisible(path))
  d <- pd_data_dir(cfg)
  # 路径可能是绝对的，也可能是相对 root 的（"data/x.csv"）→ 两种解析都查
  cand <- unique(c(path, file.path(cfg$paths$root %||% ".", path)))
  hit <- vapply(cand, function(p) {
    np <- normalizePath(p, winslash = "/", mustWork = FALSE)
    identical(np, d) || startsWith(np, paste0(d, "/"))
  }, logical(1), USE.NAMES = FALSE)
  if (any(hit))
    stop("拒绝写入 data/：", path[1],
         " —— 封丘真实数据受 md5 约定保护（references/00-data-contract.md §6）",
         call. = FALSE)
  invisible(path)
}

pd_data_md5 <- function(cfg = .pd$cfg) {
  fs <- list.files(pd_data_dir(cfg), pattern = "[.](csv|tre)$", full.names = TRUE)
  if (!length(fs)) return(character(0))
  stats::setNames(unname(tools::md5sum(fs)), basename(fs))
}

pd_verify_data_unchanged <- function(cfg = .pd$cfg, snapshot = NULL) {
  snap <- snapshot %||% .pd$data_md5
  now  <- pd_data_md5(cfg)
  if (!length(snap)) {
    # 没有快照就无从比对 —— 不误报，改成记快照并提示
    .pd$data_md5 <- now
    pd_msg("[guard] 无 md5 快照可比对，已记当前为基线（", length(now),
           " 个文件）。比对需在 pd_setup() 之后调用。")
    return(invisible(FALSE))
  }
  nms  <- union(names(snap), names(now))
  bad  <- nms[vapply(nms, function(n) !identical(snap[[n]], now[[n]]), logical(1))]
  if (length(bad))
    stop("data/ 已被改写：", paste(bad, collapse = ", "),
         " —— 立即停止并核查（references/00-data-contract.md §6）", call. = FALSE)
  pd_msg("[guard] data/*.csv md5 未变（", length(now), " 个文件）")
  invisible(TRUE)
}

pd_save_pdf <- function(p, stem, module, width_mm = NULL, height_mm = NULL,
                        size = NULL, cfg = .pd$cfg) {
  if (!pd_has("ggplot2")) return(invisible(NULL))
  if (!is.null(size)) {                 # 按论文图尺寸注册表取（config$plot$fig_size）
    s <- pd_fig_size(size, cfg)
    width_mm  <- width_mm  %||% s$width_mm
    height_mm <- height_mm %||% s$height_mm
  }
  w <- (width_mm %||% pd_size_mm(cfg)) / 25.4
  h <- (height_mm %||% (cfg$plot$height_mm %||% 120)) / 25.4
  nm <- sprintf("%s_%s.pdf", module, stem)
  pth <- file.path(cfg$paths$figures, nm)
  if (file.exists(pth)) {            # 不静默覆盖（pitfalls D2）
    pth <- file.path(cfg$paths$figures,
                     sprintf("%s_%s_%s.pdf", module, stem, format(Sys.time(), "%H%M%S")))
    pd_msg("[fig] 同名图形已存在，改存 ", basename(pth))
  }
  pd_assert_not_data(pth, cfg)        # G1 硬门槛
  dev <- if (.Platform$OS.type == "windows") grDevices::cairo_pdf else "pdf"
  ggplot2::ggsave(pth, plot = p, width = w, height = h, units = "in", device = dev, limitsize = FALSE)
  pd_msg(sprintf("[fig] %s  (%.0f x %.0f mm)", nm, w * 25.4, h * 25.4))
  invisible(pth)
}

pd_write_table <- function(df, stem, module, sheet = "result", cfg = .pd$cfg) {
  nm <- sprintf("%s_%s.xlsx", module, stem)
  pth <- file.path(cfg$paths$results, nm)
  if (file.exists(pth)) {
    pth <- file.path(cfg$paths$results, sprintf("%s_%s_%s.xlsx", module, stem,
                                                format(Sys.time(), "%H%M%S")))
    pd_msg("[tab] 同名结果表已存在，改存 ", basename(pth))
  }
  pd_assert_not_data(pth, cfg)        # G1 硬门槛
  if (!pd_has("openxlsx")) { pd_warn("需要 openxlsx 才能写 xlsx，已跳过: ", nm); return(invisible(NULL)) }
  wb <- openxlsx::createWorkbook()
  if (is.data.frame(df)) df <- list(df)
  for (i in seq_along(df)) {
    sn <- names(df)[i]
    if (is.null(sn) || !nzchar(sn)) sn <- if (i == 1) sheet else paste0("sheet", i)
    sn <- substr(gsub("[\\[\\]\\*\\?/\\\\:]", "_", sn), 1, 31)
    openxlsx::addWorksheet(wb, sn)
    dd <- as.data.frame(df[[i]])
    # 长文本 / 距离矩阵保护（见 pitfalls D3）
    if (is.matrix(df[[i]]) || any(vapply(dd, is.matrix, logical(1))))
      stop("结果表包含矩阵列，请单独保存（pitfalls D3）")
    dd <- cbind(rownames(dd), dd)
    names(dd)[1] <- "row_id"
    openxlsx::writeData(wb, sn, dd)
  }
  openxlsx::saveWorkbook(wb, pth, overwrite = TRUE)
  pd_msg("[tab] ", basename(pth))
  invisible(pth)
}

pd_write_matrix <- function(mat, stem, module, cfg = .pd$cfg) {
  nm <- sprintf("%s_%s.rds", module, stem)
  pth <- file.path(cfg$paths$results, nm)
  csv <- file.path(cfg$paths$results, sprintf("%s_%s_long.csv", module, stem))
  # ★★ 同名不静默覆盖（2026-09-25，pitfalls I27）—— 与 pd_write_table / pd_save_pdf 对齐
  #   旧写法直接 saveRDS + write.csv，重跑会静默覆盖距离矩阵，与 pitfalls D2 自相矛盾。
  if (file.exists(pth) || file.exists(csv)) {
    ts <- format(Sys.time(), "%H%M%S")
    pth <- sub("[.]rds$", paste0("_", ts, ".rds"), pth)
    csv <- sub("[.]csv$", paste0("_", ts, ".csv"), csv)
    pd_msg("[mat] 同名结果已存在，改存 ", basename(pth))
  }
  pd_assert_not_data(pth, cfg)        # G1 硬门槛
  pd_assert_not_data(csv, cfg)        # G1 硬门槛（csv 出口同样拦）
  saveRDS(mat, pth)
  m <- as.matrix(mat)
  df <- data.frame(row = rownames(m)[row(m)], col = colnames(m)[col(m)],
                   value = as.vector(m), stringsAsFactors = FALSE)
  utils::write.csv(df, csv, row.names = FALSE, fileEncoding = "UTF-8")
  pd_msg("[mat] ", basename(pth), " + ", basename(csv))
  invisible(pth)
}

# ------------------------------------------------------------
# 0.11 万能出图：ggplot 对象走 ggsave，grid/base 对象走 cairo_pdf + print
#      （phylosignal 的 barplot/dotplot/gridplot.phylo4d 可能是 ggplot，也可能是 grid 对象）
# ------------------------------------------------------------
pd_save_any <- function(obj, stem, module, width_mm = NULL, height_mm = NULL, cfg = .pd$cfg) {
  if (is.null(obj)) return(invisible(NULL))
  if (inherits(obj, "ggplot")) return(pd_save_pdf(obj, stem, module, width_mm, height_mm, cfg))
  w <- (width_mm %||% pd_size_mm(cfg)) / 25.4
  h <- (height_mm %||% (cfg$plot$height_mm %||% 120)) / 25.4
  nm <- sprintf("%s_%s.pdf", module, stem)
  pth <- file.path(cfg$paths$figures, nm)
  if (file.exists(pth))
    pth <- file.path(cfg$paths$figures, sprintf("%s_%s_%s.pdf", module, stem, format(Sys.time(), "%H%M%S")))
  pd_assert_not_data(pth, cfg)        # G1 硬门槛
  dev <- if (.Platform$OS.type == "windows") grDevices::cairo_pdf else "pdf"
  ok <- tryCatch({
    dev_open <- get(dev)
    dev_open(pth, width = w, height = h)
    on.exit(try(grDevices::dev.off(), silent = TRUE), add = TRUE)
    print(obj)
    grDevices::dev.off(); TRUE
  }, error = function(e) {
    try(grDevices::dev.off(), silent = TRUE)
    pd_warn("出图失败（", nm, "）: ", conditionMessage(e)); FALSE
  })
  if (isTRUE(ok)) pd_msg("[fig] ", basename(pth))
  if (isTRUE(ok)) pth else NULL
}

# phylosignal 的 *.phylo4d 绘图函数没有导出，必须走泛型；用 getS3method 显式拿
pd_get_s3 <- function(gen, cls, pkg) {
  m <- tryCatch(utils::getS3method(gen, cls), error = function(e) NULL)
  if (is.null(m)) m <- tryCatch(get(paste0(gen, ".", cls), envir = asNamespace(pkg)),
                                error = function(e) NULL)
  m
}

# ------------------------------------------------------------
# 0.12 捕获式出图：兼容三种情况
#   ① 返回 ggplot/grid 对象（phylosignal 部分函数）→ 交给 pd_save_any
#   ② 画到当前设备并返回 NULL（base 图形，如 phylosignal 的 barplot.phylo4d /
#      plot.phylosim）→ 自己开 cairo_pdf 再画一次
#   ③ 返回 lattice/trellis 对象 → 设备上 print()
# ------------------------------------------------------------
pd_capture_plot <- function(expr, stem, module, width_mm = NULL, height_mm = NULL, cfg = .pd$cfg) {
  e <- substitute(expr); env <- parent.frame()
  w <- (width_mm %||% pd_size_mm(cfg)) / 25.4
  h <- (height_mm %||% (cfg$plot$height_mm %||% 120)) / 25.4
  nm <- sprintf("%s_%s.pdf", module, stem)
  pth <- file.path(cfg$paths$figures, nm)
  if (file.exists(pth))
    pth <- file.path(cfg$paths$figures, sprintf("%s_%s_%s.pdf", module, stem, format(Sys.time(), "%H%M%S")))

  # 总是显式开设备：base 图形会直接画进去；ggplot/grid 对象再补 print/grid.draw
  if (.Platform$OS.type == "windows") grDevices::cairo_pdf(pth, width = w, height = h)
  else grDevices::pdf(pth, width = w, height = h)
  ok <- tryCatch({
    obj <- eval(e, envir = env)
    if (inherits(obj, "ggplot")) {
      print(obj)
    } else if (inherits(obj, c("gtable", "grob", "gg"))) {
      grid::grid.draw(obj)
    } else if (inherits(obj, "trellis")) {
      print(obj)
    } else if (!is.null(obj) && length(class(obj)) && !is.function(obj)) {
      print(obj)
    }
    TRUE
  }, error = function(err) {
    pd_warn("出图失败（", nm, "）: ", conditionMessage(err)); FALSE
  })
  try(grDevices::dev.off(), silent = TRUE)
  if (isTRUE(ok)) { pd_msg("[fig] ", basename(pth)); pth } else NULL
}

pd_stress_note <- function(stress) {
  if (is.na(stress)) return("stress 缺失")
  if (stress > 0.2) "[!] stress > 0.2，排序结果不可靠，需增加 k 或换方法（见 pitfalls）"
  else if (stress > 0.1) "stress 一般（0.1~0.2），可作解释性参考"
  else "stress < 0.1，排序良好"
}

# ------------------------------------------------------------
# 0.9 配色工具（对应原文的 ggsci / RColorBrewer / rgbToHex 探索）
# ------------------------------------------------------------
rgb_to_hex <- function(r, g, b) {
  sprintf("#%02X%02X%02X", as.integer(r), as.integer(g), as.integer(b))
}

# 支持三种写法：'custom'（config$plot$palette）/ 'npg' 等 ggsci 名称 / 'brewer:Dark2' / 直接给颜色向量
pd_palette <- function(name = NULL, n = NULL, cfg = .pd$cfg) {
  name <- name %||% (cfg$plot$palette_name %||% "custom")
  base <- NULL
  if (length(name) > 1) {
    base <- name                                  # 直接传颜色向量
  } else if (name %in% c("custom", NA, "")) {
    base <- cfg$plot$palette %||% c("#D55F4D", "#2C89A2", "#FFA07A")
  } else if (grepl("^brewer:", name)) {
    if (!pd_has("RColorBrewer")) {
      pd_warn("需要 RColorBrewer 才能用 ", name, "，已回退自定义配色")
    } else {
      nm <- sub("^brewer:", "", name)
      k <- min(9, max(3, n %||% 8))
      base <- tryCatch(RColorBrewer::brewer.pal(k, nm), error = function(e) NULL)
      if (is.null(base)) pd_warn("RColorBrewer 调色板不存在: ", nm, "，已回退")
    }
  } else if (pd_has("ggsci")) {
    fn <- tryCatch(utils::getAnywhere(paste0("pal_", name))$objs[[1]], error = function(e) NULL)
    if (is.null(fn)) fn <- tryCatch(getExportedValue("ggsci", paste0("pal_", name)), error = function(e) NULL)
    if (is.null(fn)) {
      pd_warn("ggsci 里没有调色板 '", name, "'，已回退自定义配色")
    } else {
      k <- max(3, n %||% 8)
      base <- tryCatch(fn("nrc")(k), error = function(e) tryCatch(fn(1)(k), error = function(e2) NULL))
      if (is.null(base)) pd_warn("调色板 '", name, "' 取色失败，已回退")
    }
  } else {
    pd_warn("需要 ggsci 才能用 '", name, "'，已回退自定义配色")
  }
  if (is.null(base)) base <- cfg$plot$palette %||% c("#D55F4D", "#2C89A2", "#FFA07A")
  if (!is.null(n)) rep(base, length.out = n) else base
}

pd_show_palette <- function(n = 8, name = NULL, cfg = .pd$cfg) {
  if (!pd_has("ggplot2")) return(invisible(NULL))
  cols <- pd_palette(name = name, n = n, cfg = cfg)
  d <- data.frame(x = seq_along(cols), y = 1, col = cols, lab = cols, stringsAsFactors = FALSE)
  ggplot2::ggplot(d, ggplot2::aes(x = .data$x, y = .data$y, fill = .data$col)) +
    ggplot2::geom_tile(colour = "white", linewidth = 0.3) +
    ggplot2::scale_fill_identity() + pd_theme() +
    ggplot2::labs(x = NULL, y = NULL,
                  title = sprintf("palette: %s", name %||% (cfg$plot$palette_name %||% "custom"))) +
    ggplot2::theme(axis.text = ggplot2::element_blank(),
                   axis.ticks = ggplot2::element_blank(),
                   panel.grid = ggplot2::element_blank())
}

# ------------------------------------------------------------
# 0.9b 命名色板注册表（对齐论文原图；色值全部来自论文 PDF 提色 / 原始 R 代码）
#   论文图调用点用 pd_pal("<role>")；非论文/诊断图仍可用 pd_palette()。
#   注册表在 config$plot$palettes，缺名时回退 pd_palette()。
# ------------------------------------------------------------
pd_pal <- function(name, n = NULL, cfg = .pd$cfg) {
  base <- (cfg$plot$palettes %||% list())[[name]]
  if (is.null(base) || !length(base)) {
    pd_warn("色板名 '", name, "' 未在 config$plot$palettes 定义（或为空），回退 pd_palette()")
    base <- pd_palette(cfg = cfg)
  }
  if (!length(base)) base <- "grey30"          # 兜底，绝不返回 0 长度（否则 scale_*_manual 报错）
  if (!is.null(n) && is.finite(n) && n > 0) rep(base, length.out = n) else base
}

# ------------------------------------------------------------
# 0.9c 论文图物理尺寸注册表 + patchwork 统一拼图出口
#   尺寸来自论文 PDF MediaBox（见 config$plot$fig_size）。
#   同类多图一律走 pd_compose()，统一打 (a)(b) 标签，不散落 plot_annotation。
# ------------------------------------------------------------
pd_fig_size <- function(name, cfg = .pd$cfg) {
  s <- (cfg$plot$fig_size %||% list())[[name]]
  if (is.null(s)) s <- c(190, 120)
  list(width_mm = s[1], height_mm = s[2])
}

pd_compose <- function(plots, ncol = NULL, nrow = NULL,
                       tags = "a", tag_prefix = "(", tag_suffix = ")",
                       tag_pt = NULL, guides = "collect", legend = "bottom",
                       cfg = .pd$cfg) {
  if (!pd_has("patchwork")) {
    pd_warn("缺少 patchwork，拼图降级为返回第一张图")
    return(plots[[1]])
  }
  pt <- tag_pt %||% (cfg$plot$tag_pt %||% ((cfg$plot$base_pt %||% 9) + 2))
  # ★ 关键：收集图例的摆放由 plot_annotation 的 theme 决定，
  #   加在 wrap_plots 结果上不生效（这就是图例没到底部的原因）。
  ann_theme <- ggplot2::theme(
    plot.tag        = ggplot2::element_text(size = pt, face = "bold"),
    legend.position = legend %||% "bottom",
    legend.direction = "horizontal"
  )
  patchwork::wrap_plots(plots, ncol = ncol, nrow = nrow, guides = guides) +
    patchwork::plot_annotation(
      tag_levels = if (is.null(tags) || identical(tags, FALSE)) NULL else tags,
      tag_prefix = tag_prefix, tag_suffix = tag_suffix,
      theme = ann_theme)
}

# ------------------------------------------------------------
# 0.9d PDF 文件级合并（base/grid 图形用 —— patchwork 收不到 grob）
#   用于：Venn / MCMC 迹图 / phylo4d 套图 / phyloSim / correlogram
#   合并后按 plot$save_singles 决定是否删除被合的散件
# ------------------------------------------------------------
pd_combine_pdfs <- function(paths, stem, module, cfg = .pd$cfg) {
  paths <- paths[!is.na(paths) & nzchar(paths) & file.exists(paths)]
  if (!length(paths)) return(invisible(NULL))
  if (length(paths) == 1) return(invisible(paths))   # 只有一张就不用合

  nm  <- sprintf("%s_%s.pdf", module, stem)
  pth <- file.path(cfg$paths$figures, nm)
  if (file.exists(pth)) {                           # 不静默覆盖（pitfalls D2）
    pth <- file.path(cfg$paths$figures,
                     sprintf("%s_%s_%s.pdf", module, stem, format(Sys.time(), "%H%M%S")))
    pd_msg("[fig] 同名图形已存在，改存 ", basename(pth))
  }

  ok <- FALSE
  if (pd_has("pdftools")) {
    ok <- tryCatch({ pdftools::pdf_combine(paths, pth); TRUE },
                   error = function(e) { pd_warn("pdf_combine 失败: ", conditionMessage(e)); FALSE })
  }
  if (!ok) {
    # 回退 qpdf 命令行
    args <- c("--empty", "--pages", paths, "--", pth)
    ok <- tryCatch({
      st <- system2("qpdf", args, stdout = FALSE, stderr = FALSE)
      is.numeric(st) && st == 0 && file.exists(pth)
    }, error = function(e) FALSE)
  }
  if (!ok) {
    pd_warn("pdftools / qpdf 均不可用，保留散件不合并（", length(paths), " 张）")
    return(invisible(paths))
  }

  pd_msg(sprintf("[fig] %s  (合并 %d 张)", basename(pth), length(paths)))
  # ★ 散图清理规则（用户：「如果拼图已经包括了散图，散图就可以删（冗余）。其他情况下不删」）
  #   这些散图已全部并入 pth → 冗余，可删；但必须先确认复合图已落地且非空。
  #   未并入复合图的图、历史输出：一律不删（新图写新文件/新文件夹）。
  if (!isTRUE(cfg$plot$save_singles)) {
    del <- setdiff(paths, pth)
    if (length(del)) {
      ok <- file.exists(pth) && isTRUE(file.info(pth)$size > 0)
      if (ok) {
        unlink(del)
        pd_msg("       散图已并入复合图，删除冗余散件 ", length(del), " 张: ",
               paste(basename(del), collapse = ", "))
      } else {
        pd_warn("复合图未落地或为空，保留散件不删（", length(del), " 张）")
      }
    }
  } else {
    pd_msg("       [save_singles=TRUE] 散件已保留")
  }
  invisible(pth)
}

# ------------------------------------------------------------
# 0.9e 跨模块胶水：数据诊断汇总
#   data_diagnostics = QQ + impute（分析前数据体检，跨 01/21 模块）
#   模块间靠 .pd$last_* 传递对象，不硬耦合
#   [第 3 轮删除] stats_tests_panel 胶水（ANOSIM 秩 + Venn + MCMC 迹）已随组成图一并删除
# ------------------------------------------------------------
pd_run_diagnostics <- function(cfg = .pd$cfg) {
  qq  <- .pd$last_qq       # ggplot 或已保存路径
  imp <- .pd$last_impute   # patchwork / ggplot 或已保存路径
  # 若模块已落盘且 save_singles=TRUE，散件仍在；这里再合成一张
  plots <- list()
  if (inherits(qq,  c("gg", "ggplot", "patchwork"))) plots$qq <- qq
  if (inherits(imp, c("gg", "ggplot", "patchwork"))) plots$impute <- imp
  if (length(plots) >= 1 && pd_has("patchwork") && pd_has("ggplot2")) {
    out <- if (length(plots) == 1) plots[[1]] else pd_compose(plots, ncol = 1, tags = "a", guides = "keep")
    f <- pd_save_pdf(out, "data_diagnostics", "01", size = "data_diagnostics")
    if (!is.null(f))
      pd_msg(sprintf("[glue] 数据诊断 01_data_diagnostics.pdf（QQ + impute，%d 面板）", length(plots)))
    return(invisible(f))
  }
  # 退化路径：两者都只有文件 → 文件级合并
  paths <- c(qq, imp)
  paths <- paths[vapply(paths, function(x) is.character(x) && file.exists(x), logical(1))]
  if (length(paths) >= 2) return(invisible(pd_combine_pdfs(paths, "data_diagnostics", "01", cfg = cfg)))
  pd_msg("[glue] data_diagnostics：QQ / impute 不齐，跳过")
  invisible(NULL)
}

# ------------------------------------------------------------
# 0.10 任意对象 → 可写入 xlsx 的长表（向量 / 矩阵 / dist / data.frame）
#      用于把 betapart、picante 等返回的多组件对象逐个落成 sheet
# ------------------------------------------------------------
pd_obj_to_df <- function(x, name = "value", drop_null = TRUE) {
  if (is.null(x)) return(NULL)
  if (is.data.frame(x)) {
    z <- cbind(row_id = rownames(x), x)
    rownames(z) <- NULL
    return(z)
  }
  if (inherits(x, "dist")) {
    m <- as.matrix(x)
    return(data.frame(row = rownames(m)[row(m)], col = colnames(m)[col(m)],
                      value = as.vector(m), stringsAsFactors = FALSE))
  }
  if (is.matrix(x)) {
    return(data.frame(row = rownames(x)[row(x)], col = colnames(x)[col(x)],
                      value = as.vector(x), stringsAsFactors = FALSE))
  }
  if (is.atomic(x)) {
    nm <- names(x)
    return(data.frame(item = if (is.null(nm)) seq_along(x) else nm,
                      value = as.vector(x), stringsAsFactors = FALSE))
  }
  if (drop_null) NULL else data.frame(item = name, value = paste(utils::capture.output(str(x)), collapse = " "))
}
