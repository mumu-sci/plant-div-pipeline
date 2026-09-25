# ============================================================
# 30_phylo_build.R · 物种名校正 + 系统发育树构建 + 树可视化
# 依赖：ape ；V.PhyloMaker2 或 V.PhyloMaker ；plantlist(校名，可选) ；ggtree(可视化，可选)
# 纪律：只报告缺什么，不擅自替换学名（见 SKILL.md 硬约束）
# ============================================================

# 30.1 从物种对照表构造 phylo.maker 需要的 sp.list（species / genus / family）
pd_prep_splist <- function(dat, cfg = .pd$cfg, restrict_to_abundance = TRUE, save_inv = TRUE) {
  if (is.null(dat$species)) {
    pd_msg("[30] 未提供 04_species_list.csv → 无法构造 genus/family。")
    pd_msg("[30] 纪律：缺数据只报告不动手。已跳过建树；如已有树，请直接用 99_phylo.tre 跑 31/32。")
    return(NULL)
  }
  sp <- as.data.frame(dat$species)
  names(sp)[1] <- "species"
  low <- tolower(names(sp))
  pick <- function(cands) { i <- which(low %in% cands); if (length(i)) names(sp)[i[1]] else NA }
  gcol <- pick(c("genus", "属", "属名")); fcol <- pick(c("family", "科", "科名"))
  if (is.na(gcol) || is.na(fcol)) {
    pd_warn("物种对照表缺少 genus/family 列（或列名不识别）。已跳过建树。")
    return(NULL)
  }
  df <- data.frame(species = sp$species, genus = sp[[gcol]], family = sp[[fcol]],
                   stringsAsFactors = FALSE)
  # genus / family 也必须清理不可见字符：phylo.maker 用严格字符串相等比较
  # 「属+科」与巨树是否一致，NBSP/零宽字符会让它误报分类不一致（实测 Erysimum 案例）
  inv <- rbind(pd_scan_invisible(df$species, "species(建树用)"),
               pd_scan_invisible(df$genus,   "genus"),
               pd_scan_invisible(df$family,  "family"))
  if (!is.null(inv)) {
    pd_msg(sprintf("[30] genus/family/species 中检出 %d 类不可见字符，已清理：%s",
                   nrow(inv), paste(unique(inv$char_name), collapse = ", ")))
    if (save_inv %||% FALSE) pd_write_table(list(invisible_chars = inv),
                                            stem = "invisible_chars", module = "30")
  }
  df$genus  <- pd_strip_invisible(df$genus)
  df$family <- pd_strip_invisible(df$family)
  if (restrict_to_abundance) {
    keep <- df$species %in% colnames(dat$abundance)
    pd_msg(sprintf("[30] 对照表 %d 条 → 与多度矩阵交集 %d 条", nrow(df), sum(keep)))
    df <- df[keep, , drop = FALSE]
  }
  bad <- is.na(df$genus) | is.na(df$family) | !nzchar(df$genus) | !nzchar(df$family)
  if (any(bad)) {
    pd_warn(sprintf("%d 个物种缺 genus/family，建树时会被跳过（请先补全，本包不自动补）：%s",
                    sum(bad), paste(head(df$species[bad], 10), collapse = ", ")))
    df <- df[!bad, , drop = FALSE]
  }
  df$species <- sub("_", " ", df$species)   # phylo.maker 需要"属 种"带空格的形式
  rownames(df) <- NULL
  df
}

# 30.2 建树：优先 V.PhyloMaker2，回退 V.PhyloMaker v1
# 注意：两个包都只把 GBOTB/nodes 作为 data 数据集，默认参数在包命名空间里取不到，
#       必须显式 data() 载入后把 tree / nodes 作为参数传进去（曾报 "object 'GBOTB.extended' not found"）。
pd_load_pkgdata <- function(pkg, cands) {
  e <- new.env()
  for (nm in cands) {
    ok <- tryCatch({
      suppressWarnings(utils::data(list = nm, package = pkg, envir = e))
      exists(nm, envir = e)
    }, error = function(x) FALSE)
    if (isTRUE(ok)) return(get(nm, envir = e))
  }
  NULL
}

pd_make_tree <- function(splist, scenarios = "S3") {
  if (is.null(splist) || !nrow(splist)) return(NULL)
  scn <- toupper(scenarios)
  key <- paste0("scenario.", substr(scn, 2, 2))
  pick <- function(res) {
    if (is.null(res)) return(NULL)
    if (!is.null(res[[key]])) return(res[[key]])
    i <- grep("^scenario", names(res), value = TRUE)
    if (length(i)) return(res[[i[1]]])
    NULL
  }

  # ---- V.PhyloMaker2（首选） ----
  if (pd_has("V.PhyloMaker2")) {
    tr <- pd_load_pkgdata("V.PhyloMaker2",
                          c("GBOTB.extended.TPL", "GBOTB.extended.WP", "GBOTB.extended"))
    nd <- pd_load_pkgdata("V.PhyloMaker2",
                          c("nodes.info.1.TPL", "nodes.info.1", "nodes.info"))
    if (!is.null(tr) && !is.null(nd)) {
      # phylo.maker 约 50s（封丘 150 种）→ 包缓存
      res <- pd_cached("30_phylo_maker_v2", NULL, {
        tryCatch(V.PhyloMaker2::phylo.maker(sp.list = splist, tree = tr, nodes = nd,
                                            scenarios = scn),
                 error = function(e) { pd_msg("[30] V.PhyloMaker2 报错: ", conditionMessage(e)); NULL })
      }, cfg = cfg)
      out <- pick(res)
      if (!is.null(out)) { attr(out, "pd_builder") <- "V.PhyloMaker2"; return(out) }
    } else {
      pd_msg("[30] V.PhyloMaker2 的树数据对象未找到（GBOTB.extended.TPL / nodes.info.1.TPL）")
    }
  }

  # ---- V.PhyloMaker v1（回退） ----
  if (pd_has("V.PhyloMaker")) {
    tr <- pd_load_pkgdata("V.PhyloMaker", c("GBOTB.extended"))
    nd <- pd_load_pkgdata("V.PhyloMaker", c("nodes.info.1", "nodes.info.2"))
    if (is.null(tr)) {
      pd_msg("[30] V.PhyloMaker 的 GBOTB.extended 未找到")
    } else {
      res <- pd_cached("30_phylo_maker_v1", NULL, {
        tryCatch(V.PhyloMaker::phylo.maker(sp.list = splist, tree = tr, nodes = nd,
                                           scenarios = scn),
                 error = function(e) { pd_msg("[30] V.PhyloMaker v1 报错: ", conditionMessage(e)); NULL })
      }, cfg = cfg)
      out <- pick(res)
      if (!is.null(out)) { attr(out, "pd_builder") <- "V.PhyloMaker(v1)"; return(out) }
    }
  }
  pd_warn("建树失败：两个包的树数据对象均不可用，或 scenarios 参数不匹配")
  NULL
}

# 30.3 主入口
pd_run_phylo_build <- function(cfg = .pd$cfg, dat = NULL, save = TRUE) {
  dat <- dat %||% pd_load_data(cfg)
  pd_msg("")
  pd_msg("### 30 建树与物种名校正 ###")

  splist <- pd_prep_splist(dat, cfg)
  if (is.null(splist)) return(invisible(NULL))

  # 是否需要校名（plantlist）
  if (pd_has("plantlist")) {
    pd_msg("[30] plantlist 可用：将对学名做 TPL 校正（仅报告不一致，不写回数据）")
    res <- tryCatch(plantlist::TPL(sub("_", " ", splist$species)), error = function(e) NULL)
    if (!is.null(res)) {
      chk <- as.data.frame(res)
      mism <- chk[toupper(chk$YOUR_SEARCH) != toupper(chk$POSSIBLE_GENUS), , drop = FALSE]
      if (nrow(mism))
        pd_msg(sprintf("[30] TPL 提示 %d 条属名待核对: %s", nrow(mism),
                       paste(head(mism$YOUR_SEARCH, 8), collapse = ", ")))
      if (save) pd_write_table(as.data.frame(res), stem = "tpl_check", module = "30")
    }
  } else {
    pd_msg("[30] plantlist 未安装 → 跳过校名（不擅自替换学名）。安装：remotes::install_github(\"helixcn/plantlist\")")
  }

  if (!pd_has("V.PhyloMaker2") && !pd_has("V.PhyloMaker")) {
    pd_warn("V.PhyloMaker2 与 V.PhyloMaker 均未安装 → 无法建树。")
    pd_msg("       安装：remotes::install_github(\"jinyizju/V.PhyloMaker2\")")
    if (save) pd_write_table(splist, stem = "splist_ready", module = "30")
    pd_msg("[30] 已输出可供建树的物种清单 results/30_splist_ready.xlsx，装好包后可直接用。")
    return(invisible(list(splist = splist, tree = NULL)))
  }

  tree <- pd_make_tree(splist, scenarios = cfg$opts$tree_scenario %||% "S3")
  if (is.null(tree)) { pd_warn("建树失败，请检查包版本与数据对象名"); return(invisible(NULL)) }
  pd_msg(sprintf("[30] 建树完成（%s）：tip = %d", attr(tree, "pd_builder"), length(tree$tip.label)))
  if (is.null(tree$edge.length)) pd_warn("生成的树没有枝长 → PD/MNTD 不可用，请检查 scenarios 设置")

  tip_file <- file.path(cfg$paths$results, "30_built_tree.tre")
  ape::write.tree(tree, tip_file)
  pd_msg("[30] 树已写出: ", basename(tip_file))

  if (save) pd_write_table(list(
    tip_labels = data.frame(species = tree$tip.label),
    # ★★ 口径声明（2026-09-25，pitfalls I23）—— Methods 要能溯源
    run_info = data.frame(
      item = c("建树工具", "scenario", "scenario 依据", "骨架树", "tip 数", "枝长"),
      value = c(attr(tree, "pd_builder") %||% "V.PhyloMaker2",
                cfg$opts$tree_scenario %||% "S3",
                "Qian & Jin (2016); Jin & Qian (2019) —— S3 = 缺失种按属内随机插枝到属节点",
                paste(intersect(c("GBOTB.extended.TPL", "GBOTB.extended.WP", "GBOTB.extended"),
                                ls(envir = asNamespace("V.PhyloMaker2"))),
                      collapse = " / "),
                length(tree$tip.label),
                if (is.null(tree$edge.length)) "无（PD/MNTD 不可用）" else "有"),
      stringsAsFactors = FALSE)),
    stem = "tree_tips", module = "30")

  # 可视化（ggtree，可选）
  if (pd_has("ggtree") && pd_has("ggplot2")) {
    trn <- tree; trn$tip.label <- sub("_", " ", trn$tip.label)
    # 仅为对齐论文图外观：ladderize + tip 标签字号 3 + 140×133mm
    #   注意（pitfalls E6）：ggtree 环形树不要套 pd_theme()，会注入网格/坐标轴破坏 circular 布局
    #   论文源码：ggtree(tree, layout='circular', branch.length='none') + geom_tiplab2(size=3)
    #   本图是「简单树」，论文终版 Fig S1 是分组着色树（见 pd_plot_tree_grouped），此处仅作补充
    trn2 <- tryCatch(ape::ladderize(trn), error = function(e) trn)  # 仅为对齐论文图外观
    p <- tryCatch(ggtree::ggtree(trn2, layout = "circular", branch.length = "none") +
                    ggtree::geom_tiplab2(size = 2.0), error = function(e) NULL)  # 1.6 → 3 → 2.4 → 2.0
    if (!is.null(p)) pd_save_pdf(p, "tree_round_simple", "30", width_mm = 185, height_mm = 175)

    # ---- 分组着色的环形树（Fig S1 等价图，主出）----
    g <- tryCatch(pd_plot_tree_grouped(tree, cfg, dat = NULL, splist = splist),
                  error = function(e) { pd_warn("分组着色树失败: ", conditionMessage(e)); NULL })
  }
  invisible(list(splist = splist, tree = tree))
}

# ------------------------------------------------------------
# 30.4 按分组着色的环形树
#   复刻原文两个版本：
#     ① groupOTU 按 family 分组着色
#     ② ggtree + geom_tree(aes(color = 分组)) + geom_tippoint(shape = 生境, fill = 生境)
#   分组来源：04_species_list.csv 的 family / genus；
#             若要按生境·季节着色，需在 config$opts$tree_group_file 给一张
#             "species, group, shape" 对照表（列名可配）。
# ------------------------------------------------------------
pd_plot_tree_grouped <- function(tree, cfg = .pd$cfg, dat = NULL, splist = NULL,
                                 group_file = NULL) {
  if (!pd_has("ggtree") || !pd_has("ggplot2")) return(invisible(NULL))
  grp_col <- cfg$opts$tree_group %||% "family"     # family | genus | 自定义列
  gf <- group_file %||% cfg$opts$tree_group_file
  out <- list()

  # ---- 版本①：groupOTU 按 family/genus 分组 ----
  info <- NULL
  if (!is.null(splist) && grp_col %in% names(splist)) {
    info <- data.frame(species = normalize_species(splist[[1]]),
                       grp = as.character(splist[[grp_col]]), stringsAsFactors = FALSE)
  } else if (!is.null(dat$species) && grp_col %in% names(dat$species)) {
    info <- data.frame(species = normalize_species(dat$species[[cfg$key$species]]),
                       grp = as.character(dat$species[[grp_col]]), stringsAsFactors = FALSE)
  }
  if (!is.null(info)) {
    info <- info[!is.na(info$grp) & nzchar(info$grp), , drop = FALSE]
    info <- info[!duplicated(info$species), , drop = FALSE]
    tr <- tree
    tr$tip.label <- normalize_species(tr$tip.label)
    hit <- info$species[info$species %in% tr$tip.label]
    if (length(hit) >= 3) {
      gl <- split(hit, info$grp[match(hit, info$species)])
      gl <- gl[vapply(gl, length, integer(1)) >= 2]      # 只保留 >=2 个物种的分组，否则图例太碎
      if (length(gl)) {
        tr2 <- tryCatch(ggtree::groupOTU(tr, gl), error = function(e) NULL)
        if (!is.null(tr2)) {
          tr2$tip.label <- sub("_", " ", tr2$tip.label)
          # 色板长度必须覆盖 groupOTU 的全部水平（含单物种组，会归为 "0"）
          #   曾按 length(gl) 取值 → "Insufficient values in manual scale. 23 needed but only 22 provided"
          #   又因 tr2$group 在部分 ggtree 版本取不到 → k=0 → "only 0 provided"
          grp_vec <- tr2$group %||% attr(tr2, "group") %||%
                     rep("0", length(tr2$tip.label))
          k <- max(3L, length(unique(as.character(grp_vec))), length(gl) + 1L)
          # 仅为对齐论文图外观：tip 2.5 + 论文草稿色 + guide 覆盖；不套 pd_theme（pitfalls E6）
          p1 <- tryCatch(
            ggtree::ggtree(tr2, layout = "circular", branch.length = "none",
                           ggplot2::aes(colour = .data$group), linewidth = 1) +
              ggtree::geom_tiplab2(size = 1.9, show.legend = FALSE) +   # 1.4 → 2.5 → 2.2 → 1.9（仍被裁）
              ggplot2::scale_colour_manual(values = pd_pal("tree_branch", n = k, cfg = cfg)) +
              # 图例收敛：override.aes size 5 → 2（曾把图例撑爆，被裁得更严重）
              ggplot2::guides(colour = ggplot2::guide_legend(override.aes = list(size = 2))) +
              ggplot2::labs(colour = grp_col) +
              ggplot2::theme(legend.position = "top",
                             legend.key.size  = grid::unit(0.4, "lines"),
                             legend.text      = ggplot2::element_text(size = 6),
                             legend.title     = ggplot2::element_text(size = 6),
                             plot.margin      = ggplot2::margin(3, 3, 3, 3, "mm")),
            error = function(e) { pd_warn("分组树绘制失败: ", conditionMessage(e)); NULL })
          if (!is.null(p1))
            out$by_group <- pd_save_pdf(p1, paste0("tree_round_by_", grp_col), "30",
                                        width_mm = 185, height_mm = 185)
          pd_msg(sprintf("[30] 分组着色环形树：按 %s 分了 %d 组（%d 个有效分组，色板 %d 色）",
                         grp_col, length(gl), k, k))
        }
      } else pd_msg("[30] 分组着色：没有任何分组含 >= 2 个物种，跳过")
    }
  }

  # ---- 版本②：full_join 分组表 + 末端点形状/填充 ----
  if (!is.null(gf) && !is.na(gf) && nzchar(gf) && file.exists(gf)) {
    gd <- pd_read_table(gf)
    if (is.null(gd)) { pd_warn("分组表读取失败: ", gf); return(invisible(out)) }
    lab <- cfg$opts$tree_group_label_col %||% "species"
    if (!lab %in% names(gd)) {
      pd_warn(sprintf("分组表缺少 '%s' 列（可用 opts$tree_group_label_col 指定）", lab))
      return(invisible(out))
    }
    # ⚠️ 曾错：sub("_", " ", normalize_species(...)) 把 label 转成**空格形式**，
    #    而树 tip 是**下划线形式** → full_join 匹配 0 行 → 图上全是白点。
    #    改为两侧都 normalize_species()（空格→下划线 + 清 NBSP 等不可见字符，pitfalls G11）
    gd[[lab]] <- normalize_species(gd[[lab]])
    n_nbsp <- sum(grepl(" ", as.character(gd[[lab]]), fixed = TRUE))
    tree$tip.label <- normalize_species(tree$tip.label)
    n_hit <- sum(tree$tip.label %in% gd[[lab]])
    pd_msg(sprintf("[30] 分组表 %d 行，命中树 tips %d/%d（label 列 '%s'）",
                   nrow(gd), n_hit, length(tree$tip.label), lab))
    if (n_hit < 3) {
      pd_warn("分组表与树 tip 几乎不匹配，跳过版本②（检查 label 是否为下划线学名）")
      return(invisible(out))
    }
    trj <- tryCatch(treeio::full_join(tree, gd, by = c("label" = lab)), error = function(e) NULL)
    if (is.null(trj)) { pd_warn("full_join 失败，跳过版本②"); return(invisible(out)) }
    # ★ 第 3 轮修正：names(trj) 对 treedata 对象返回**空**（列在 @data 槽里），
    #   旧守卫 if (ccol %in% names(trj)) 恒 FALSE → 着色层从未加上 → 树是黑白的。
    #   改用 tidytree::as_tibble() 取真实列名。
    trj_cols <- tryCatch(names(tidytree::as_tibble(trj)), error = function(e) character(0))
    pd_msg(sprintf("[30] full_join 后可用列：%s", paste(trj_cols, collapse = ", ")))
    ccol <- cfg$opts$tree_group_color_col %||% "season"
    scol <- cfg$opts$tree_group_shape_col %||% "habitat"
    # ---- Fig S1 等价图（主出）：分组着色环形树 ----
    #  仅为对齐论文图外观：tip 字号 2.4 / tippoint 2.5 + 论文色板 + shape 24/22/21
    #   PDF 实测 season = Set2[1:3] #66C2A5/#FC8D62/#8DA0CB（tree_branch）
    #              habitat fill = #1F77B4/#D62728/#9467BD（tree_tip）
    #   原论文代码里 scale_color_brewer("Set2") 写在 scale_colour_manual 之后，
    #   把手工色 #FF8C00/#008B8B/#DC143C 覆盖掉了 —— 以 PDF 实测为准。
    #   不套 pd_theme()（pitfalls E6）：会注入网格/坐标轴，破坏 circular 布局。
    #  第 3 轮：图例 override.aes size 5 → 2（size=5 是图例符号尺寸，过大被裁）；
    #          tip 3 → 2.4 + plot.margin + 设备加大到 165mm，防裁剪
    p2 <- tryCatch({
      has_ccol <- ccol %in% trj_cols
      has_scol <- scol %in% trj_cols
      k_season  <- if (has_ccol) max(3L, length(unique(as.character(tidytree::as_tibble(trj)[[ccol]])))) else 3L
      k_habitat <- if (has_scol) max(3L, length(unique(as.character(tidytree::as_tibble(trj)[[scol]])))) else 3L
      p <- ggtree::ggtree(trj, layout = "circular", branch.length = "none")
      if (has_ccol)
        p <- p + ggtree::geom_tree(ggplot2::aes(colour = .data[[ccol]]), linewidth = 1)
      p <- p + ggtree::geom_tiplab2(size = 2.0, hjust = -0.02)   # 1.4 → 3 → 2.4 → 2.0（仍被裁，再降）
      if (has_scol)
        p <- p + ggtree::geom_tippoint(ggplot2::aes(shape = .data[[scol]], fill = .data[[scol]]),
                                       size = 2.5, colour = "grey20")
      if (has_ccol)
        p <- p + ggplot2::scale_colour_manual(values = pd_pal("tree_branch", n = k_season, cfg = cfg))
      if (has_scol) {
        p <- p + ggplot2::scale_fill_manual(values = pd_pal("tree_tip", n = k_habitat, cfg = cfg))
        p <- p + ggplot2::scale_shape_manual(values = c(24, 22, 21)[seq_len(min(3L, k_habitat))])  # 论文有，曾缺
      }
      # 图例收敛：override.aes size 5 → 2（size 是图例符号尺寸，5 会把图例撑爆被裁）
      p + ggplot2::guides(
             colour = ggplot2::guide_legend(override.aes = list(size = 2)),
             fill   = ggplot2::guide_legend(override.aes = list(size = 2)),
             shape  = ggplot2::guide_legend(override.aes = list(size = 2))) +
        ggplot2::theme(legend.position = "top",
                       legend.key.size   = grid::unit(0.4, "lines"),
                       legend.text       = ggplot2::element_text(size = 6),
                       legend.title      = ggplot2::element_text(size = 6),
                       legend.spacing.x  = grid::unit(0.05, "lines"),
                       legend.margin     = ggplot2::margin(0, 0, 0, 0),
                       plot.margin       = ggplot2::margin(3, 3, 3, 3, "mm"))
    }, error = function(e) { pd_warn("版本②绘图失败: ", conditionMessage(e)); NULL })
    if (!is.null(p2))
      out$by_meta <- pd_save_pdf(p2, "tree_grouped_meta", "30", width_mm = 185, height_mm = 175)
  } else if (!is.null(gf) && !is.na(gf) && nzchar(gf)) {
    pd_msg("[30] 未找到分组表（config$opts$tree_group_file），跳过按生境/季节着色的版本")
  }
  invisible(out)
}
