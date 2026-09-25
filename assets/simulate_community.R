# ============================================================
# simulate_community.R · 给 02_sample_meta.csv 追加模拟群落结构列
#
# ⚠️ 这是【模拟数据，非实测】，只用于跑通 12/52/60/43 吃 community 响应组的示例。
#    skill 里的数据全是模板，都不能进论文；换新论文请用实测的株高/盖度/密度。
#
# 追加列（末尾 3 列，不改写原有 15 列的任何值）：
#   Height   植物平均高度  cm
#   Coverage 植物总盖度    %
#   Density  植物密度      株·m⁻²
#
# 构造口径（可复现：seed = 20260101）
#   输入  : data/02_sample_meta.csv 的多样性指数（真实列，只读）
#   公式  : 在「群落结构量级」上加与多样性指数相关的线性项 + 高斯噪声，
#           使组间比较 / 相关 / 回归能给出可解释结构（不是随便填随机数）。
#     Height   ~  50 +  8 * scale(Shannon)              + ε(5)      # cm
#     Coverage ~  70 +  6 * scale(Pielou)               + ε(8)      # %
#     Density  ~ 100 + 10 * scale(S)                    + ε(12)     # 株·m⁻²
#   scale() 用本数据集的均值/标准差标准化；ε 用 rnorm。
#   量级参照温带非农生境草本群落的常见范围，但【数值是构造的】。
#
# 首行写 `#` 注释标明后 3 列是模拟列（pd_read_table 会自动 comment.char="#"）。
#
# 用法（在 skill 根目录）：
#   Rscript --vanilla assets/simulate_community.R
# ============================================================

Sys.setlocale("LC_CTYPE", "Chinese_China.utf8"); options(encoding = "UTF-8")

SEED <- 20260101
args <- commandArgs(trailingOnly = TRUE)
ROOT <- if (length(args) >= 1) args[1] else "."
META <- file.path(ROOT, "data", "02_sample_meta.csv")
if (!file.exists(META)) stop("找不到 ", META)

set.seed(SEED)
d <- read.csv(META, check.names = FALSE, stringsAsFactors = FALSE,
              comment.char = "#")          # 已有 # 注释也跳过
# 只在缺列时追加；重复跑不覆盖已生成的列（幂等）
if (!all(c("Height", "Coverage", "Density") %in% names(d))) {
  sc <- function(z) as.numeric(scale(as.numeric(z)))
  d$Height   <- round(pmax(5,  50 +  8 * sc(d$Shannon) + rnorm(nrow(d), 0, 5)),  1)
  d$Coverage <- round(pmin(100, pmax(1, 70 + 6 * sc(d$Pielou) + rnorm(nrow(d), 0, 8))), 1)
  d$Density  <- round(pmax(1, 100 + 10 * sc(d$S)     + rnorm(nrow(d), 0, 12)), 0)

  hdr <- paste0(
    "# Height/Coverage/Density 三列是【模拟数据，非实测】，由 assets/simulate_community.R 生成（seed=",
    SEED, "）。原有 15 列未改动。新论文请换成实测株高/盖度/密度。")
  con <- file(META, open = "wt", encoding = "UTF-8")
  writeLines(hdr, con)
  utils::write.csv(d, con, row.names = FALSE, quote = TRUE, fileEncoding = "UTF-8")
  close(con)
  cat("已追加模拟列 Height/Coverage/Density →", META, "\n")
} else {
  cat("Height/Coverage/Density 已存在，跳过（幂等）。\n")
}
cat("行数:", nrow(d), " 列数:", ncol(d), "\n")
