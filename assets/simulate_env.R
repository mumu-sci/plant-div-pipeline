# ============================================================
# simulate_env.R · 生成模拟环境数据 05_env_simulated.csv
#
# ⚠️ 这是【模拟数据，非实测】，只用于跑通 42_rda / 43_regression 的示例。
#    skill 里的数据全是模板，都不能进论文；换新论文请用实测环境数据
#    （表头模板见 assets/05_env_template.csv）。
#
# 构造口径（可复现：seed 固定）
#   输入  : data/02_sample_meta.csv 的 sample_id + 多样性指数（真实数据，不改）
#   输出  : data/05_env_simulated.csv
#   公式  : 在「土壤实测量级」上加与多样性指数相关的线性项 + 高斯噪声，
#           使 RDA / 线性回归能给出可解释结构（不是随便填随机数）。
#     pH  ~ 8.00 + 0.10 * scale(Season 秋=−1/春=0/夏=1)           + ε(0.15)
#     AK  ~ 240  + 2.00 * scale(Shannon)                          + ε(15)
#     AP  ~  50  + 1.50 * scale(Pielou)                           + ε(8)
#     AN  ~  26  + 0.004 * scale(PD)                              + ε(2.5)
#     SOM ~   9  + 0.80 * scale(Shannon)                          + ε(1.5)
#     SMC ~  16  + 0.60 * scale(Pielou)                           + ε(1.2)
#   量级参照 Diversity 2023 Table 4 的土壤实测范围，但【数值是构造的】。
#   scale() 用本数据集的均值/标准差标准化。
#
# 用法（在 skill 根目录）：
#   Rscript --vanilla assets/simulate_env.R
# ============================================================

Sys.setlocale("LC_CTYPE", "Chinese_China.utf8"); options(encoding = "UTF-8")

SEED <- 20260101
args <- commandArgs(trailingOnly = TRUE)
ROOT <- if (length(args) >= 1) args[1] else "."
meta_f <- file.path(ROOT, "data", "02_sample_meta.csv")
out_f  <- file.path(ROOT, "data", "05_env_simulated.csv")

if (!file.exists(meta_f)) stop("找不到 meta: ", meta_f)
mt <- utils::read.csv(meta_f, header = TRUE, check.names = FALSE,
                      stringsAsFactors = FALSE, fileEncoding = "UTF-8")
need <- c("sample_id", "Shannon", "Pielou", "PD", "Season")
miss <- setdiff(need, names(mt))
if (length(miss)) stop("meta 缺列: ", paste(miss, collapse = ", "))

z <- function(x) (x - mean(x, na.rm = TRUE)) / sd(x, na.rm = TRUE)
sh  <- z(mt$Shannon)
pie <- z(mt$Pielou)
pd  <- z(mt$PD)
sea <- c(Spring = 0, Summer = 1, Autumn = -1)[as.character(mt$Season)]
sea[is.na(sea)] <- 0

set.seed(SEED)
n <- nrow(mt)
env <- data.frame(
  sample_id = mt$sample_id,
  pH  = round(8.00 + 0.10 * sea             + rnorm(n, 0, 0.15), 3),
  AK  = round(240  + 2.00 * sh              + rnorm(n, 0, 15),   2),
  AP  = round( 50  + 1.50 * pie             + rnorm(n, 0, 8),    2),
  AN  = round( 26  + 0.004 * pd             + rnorm(n, 0, 2.5),  3),
  SOM = round(  9  + 0.80 * sh              + rnorm(n, 0, 1.5),  3),
  SMC = round( 16  + 0.60 * pie             + rnorm(n, 0, 1.2),  3),
  stringsAsFactors = FALSE
)

hdr <- paste0(
  "# 05_env_simulated.csv — 模拟环境数据（SIMULATED, NOT MEASURED）\n",
  "# 仅用于跑通 plant-div-pipeline 的 42_rda / 43_regression 示例，不可用于论文。\n",
  "# 生成器 assets/simulate_env.R，seed=", SEED, "；公式见该脚本注释。\n",
  "# 新论文请改用实测数据（表头模板：assets/05_env_template.csv）。\n")
writeLines(hdr, out_f)
utils::write.table(env, out_f, sep = ",", row.names = FALSE, append = TRUE,
                   quote = TRUE, fileEncoding = "UTF-8")

cat("written:", out_f, " (", nrow(env), " rows x", ncol(env), " cols )\n")
print(summary(env[, -1]))
