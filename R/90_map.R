# ============================================================
# 90_map.R · 研究区概况图（底图 + 采样点 + 嵌图 + 引线）
# 依赖：sf + ggplot2 ；ggspatial（比例尺/指北针，可选）；cowplot（嵌图，可选）
# 纪律：不联网、不使用任何地图 API 密钥、不硬编码 key
#   底图边界由用户提供本地文件（GeoJSON / shapefile）
#   按用户决定：不做 DEM 高程、不做河流图层
# ============================================================

# 自动识别经纬度列名（用户表里可能叫 lon/lng/longitude、lat/纬度）
pd_pick_col <- function(df, want, alts) {
  for (k in c(want, alts)) if (!is.null(k) && !is.na(k) && k %in% names(df)) return(k)
  NULL
}

pd_run_map <- function(cfg = .pd$cfg, save = TRUE) {
  if (!pd_require(c("sf", "ggplot2"), "90_map")) return(invisible(NULL))
  pd_msg("")
  pd_msg("### 90 研究区概况图 ###")
  m <- cfg$map

  need <- c(boundary = m$boundary)
  if (is.null(m$boundary) || is.na(m$boundary) || !nzchar(m$boundary)) {
    pd_msg("[90] config$map$boundary 未指定 → 缺数据只报告不动手，已跳过。")
    pd_msg("     请在 config 里给出行政区边界文件（GeoJSON/shapefile）路径。")
    return(invisible(NULL))
  }
  if (!file.exists(m$boundary)) {
    pd_warn("底图文件不存在: ", m$boundary, " → 90 跳过")
    return(invisible(NULL))
  }

  main_shp <- tryCatch(sf::read_sf(m$boundary), error = function(e) {
    pd_warn("底图读取失败: ", conditionMessage(e)); NULL })
  if (is.null(main_shp)) return(invisible(NULL))
  pd_msg(sprintf("[90] 底图: %s（%d 个要素）", basename(m$boundary), nrow(main_shp)))

  # ---- 采样点 ----
  sites <- NULL
  if (!is.null(m$sites_csv) && !is.na(m$sites_csv) && nzchar(m$sites_csv)) {
    if (!file.exists(m$sites_csv)) {
      pd_warn("采样点表不存在: ", m$sites_csv)
    } else {
      sites <- pd_read_table(m$sites_csv)
      if (!is.null(sites)) {
        lc <- pd_pick_col(sites, m$lon_col, c("lon", "lng", "longitude", "long", "x", "经度"))
        ac <- pd_pick_col(sites, m$lat_col, c("lat", "latitude", "y", "纬度"))
        if (is.null(lc) || is.null(ac)) {
          pd_warn("采样点表里找不到经纬度列（现有列：", paste(names(sites), collapse = ", "), "）")
          sites <- NULL
        } else {
          sites <- data.frame(lon = as.numeric(sites[[lc]]), lat = as.numeric(sites[[ac]]))
          sites <- sites[stats::complete.cases(sites), , drop = FALSE]
          pd_msg(sprintf("[90] 采样点: %s（%d 个；用列 %s / %s）",
                         basename(m$sites_csv), nrow(sites), lc, ac))
        }
      }
    }
  } else pd_msg("[90] 未指定采样点表（config$map$sites_csv）→ 只画底图")

  pal <- pd_palette(cfg = cfg)

  # ---- 主图 ----
  p_main <- ggplot2::ggplot() +
    ggplot2::geom_sf(data = main_shp, fill = "grey95", colour = "grey25", linewidth = 0.35)
  if (pd_has("ggspatial")) {
    p_main <- p_main +
      ggspatial::annotation_scale(location = m$scale_loc %||% "br", width_hint = 0.25) +
      ggspatial::annotation_north_arrow(
        location = m$north_loc %||% "tl", which_north = "true",
        style = ggspatial::north_arrow_nautical(fill = c("grey40", "white"), line_col = "grey20"),
        height = ggplot2::unit(1.1, "cm"), width = ggplot2::unit(1.1, "cm"))
  } else {
    pd_msg("[90] 未安装 ggspatial → 跳过比例尺与指北针")
  }
  if (!is.null(sites))
    p_main <- p_main + ggplot2::geom_point(data = sites,
      ggplot2::aes(x = .data$lon, y = .data$lat), colour = pd_pal("map_point")[1], size = 2.5)  # 论文 size=2.5

  # 研究区在省图上的位置标注
  clon <- m$county_lon; clat <- m$county_lat
  if (!is.null(clon) && !is.null(clat) && !is.na(clon) && !is.na(clat)) {
    p_main <- p_main +
      ggplot2::geom_point(ggplot2::aes(x = clon, y = clat), colour = "black",
                          size = 1.8, shape = 17) +
      ggplot2::annotate("text", x = clon, y = clat + 0.25, size = (cfg$plot$base_pt %||% 9) * 0.32,
                        label = m$boundary_name %||% "Study area")
  }
  if (!is.null(m$xlim) && !is.null(m$ylim))
    p_main <- p_main + ggplot2::coord_sf(xlim = m$xlim, ylim = m$ylim)
  p_main <- p_main + pd_theme(grid = "none") +
    ggplot2::theme(legend.title = ggplot2::element_blank()) +   # 论文地图 legend.title 为空
    ggplot2::labs(x = NULL, y = NULL) +
    ggplot2::theme(axis.text = ggplot2::element_text(size = (cfg$plot$base_pt %||% 9) - 1.5))

  figs <- list()
  # study_area_main 是 composite 的冗余子集（同一底图重画），默认不出
  if (isTRUE(cfg$plot$save_singles))
    main_file <- pd_save_pdf(p_main, "study_area_main", "90", width_mm = 150, height_mm = 120)
  figs$main <- main_file

  # ---- 嵌图（研究区放大图）----
  if (!is.null(m$inset) && !is.na(m$inset) && nzchar(m$inset) && file.exists(m$inset)) {
    ins <- tryCatch(sf::read_sf(m$inset), error = function(e) NULL)
    if (!is.null(ins)) {
      p_inset <- ggplot2::ggplot() +
        ggplot2::geom_sf(data = ins, fill = "grey92", colour = "grey25", linewidth = 0.4) +
        ggplot2::theme_void(base_size = (cfg$plot$base_pt %||% 9) - 1) +
        ggplot2::theme(panel.border = ggplot2::element_rect(colour = "grey25", fill = NA, linewidth = 0.5),
                       plot.title = ggplot2::element_text(size = (cfg$plot$base_pt %||% 9) - 1,
                                                          hjust = 0.5),
                       plot.margin = ggplot2::margin(2, 2, 2, 2))
      if (!is.null(sites))
        p_inset <- p_inset + ggplot2::geom_point(data = sites,
          ggplot2::aes(x = .data$lon, y = .data$lat), colour = pd_pal("map_point")[1], size = 1.5)
      if (!is.null(ins$geometry))
        p_inset <- p_inset + ggplot2::coord_sf(expand = TRUE)
      p_inset <- p_inset + ggplot2::labs(title = m$boundary_name %||% NULL)

      if (pd_has("cowplot")) {
        # 引线：在 npc 坐标（0~1）里画，位置可在 config 里调
        seg <- data.frame(
          x  = c(m$line1_x  %||% 0.32, m$line2_x  %||% 0.30),
          y  = c(m$line1_y  %||% 0.72, m$line2_y  %||% 0.66),
          xe = c(m$line1_xe %||% 0.62, m$line2_xe %||% 0.56),
          ye = c(m$line1_ye %||% 0.44, m$line2_ye %||% 0.16))
        comp <- cowplot::ggdraw(p_main) +
          cowplot::draw_plot(p_inset,
                             x = m$inset_x %||% 0.60, y = m$inset_y %||% 0.36,
                             width = m$inset_w %||% 0.38, height = m$inset_h %||% 0.38) +
          ggplot2::geom_segment(data = seg,
            ggplot2::aes(x = .data$x, y = .data$y, xend = .data$xe, yend = .data$ye),
            inherit.aes = FALSE, linewidth = 0.4, colour = "grey20")
        # 仅为对齐论文图外观：尺寸走注册表 fig1_map（186×274mm）
        figs$composite <- pd_save_pdf(comp, "study_area_composite", "90",
                                      size = "fig1_map")
        pd_msg("[90] 已出拼图（主图 + 嵌图 + 2 条引线）")
      } else {
        pd_warn("未安装 cowplot → 无法拼嵌图与引线，已分别输出主图与嵌图")
        figs$inset <- pd_save_pdf(p_inset, "study_area_inset", "90", width_mm = 100, height_mm = 100)
      }
    } else pd_warn("嵌图读取失败: ", m$inset)
  } else {
    pd_msg("[90] 未指定嵌图边界（config$map$inset）→ 只出主图")
    pd_msg("     按你的要求，DEM 高程与河流图层不做。若要嵌图，把研究区边界的 GeoJSON 路径填进 config$map$inset。")
  }

  if (save) {
    pd_write_table(list(run_info = data.frame(
      item = c("底图", "嵌图", "采样点数", "比例尺/指北针", "说明"),
      value = c(basename(m$boundary),
                ifelse(is.null(m$inset) || is.na(m$inset), "未指定", basename(m$inset)),
                ifelse(is.null(sites), 0, nrow(sites)),
                ifelse(pd_has("ggspatial"), "有", "无（缺 ggspatial）"),
                "不联网、无 API 密钥；DEM 与河流未做（用户决定）"),
      stringsAsFactors = FALSE)), stem = "map_info", module = "90")
  }
  invisible(list(figures = figs, sites = sites, main = main_shp))
}
