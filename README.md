# plant-div-pipeline · 植物多维度多样性分析代码包

**一句话**：把植物多样性论文的分析流程标准化——整理一次数据，说清科学问题，勾选方法，生成代码，确认后执行，交付结果表与 pdf 图。

> 适用范围：参照封丘植物多样性论文（物种 / 功能 / 谱系三个维度 × 季节 × 生境）建立，共 6 组 23 个模块。
> 设计目标是**换数据不改代码**：封丘只是"一组参数"，撂荒地、水生植物那几篇可直接复用。
>
> **交付物**：`results/*.xlsx`（每模块一张结果表）+ `figures/*.pdf`（图）+ **`tables/tables.docx`（论文表格）**。
> 论文表格**只做论文里实际存在的那几张表**（现共 12 张），不是每个分析都排一张三线表 —— 见 `references/04-paper-tables.md`。

---

## 1. 怎么用（三步）

### 第 1 步：整理数据（只做一次）
在新论文项目里建目录，把数据整理成 5 个文件（详见 `references/00-data-contract.md`）：

```
<论文项目>/
├─ data/
│  ├─ 01_abundance.csv     样方 × 物种 多度矩阵（首列 sample_id，列名=学名主键）
│  ├─ 02_sample_meta.csv   样方元数据（sample_id + 任意个分组因子/协变量）
│  ├─ 03_traits.csv        物种 × 性状（首列 species）      ← 功能/降维模块需要
│  ├─ 04_species_list.csv  species / genus / family / species_cn  ← 建树模块需要
│  └─ 99_phylo.tre         Newick 树（tip = 学名主键）
│  └─ 05_env_simulated.csv 环境/协变量表（可选；skill 自带这份是【模拟数据】）
├─ config/config.R         从本包 config/config_template.R 复制修改
├─ code/  results/  figures/  logs/  tables/  cache/
│                              tables/ ← tables.docx（论文表格）
│                              cache/  ← 模块级 .rds 缓存（改样式秒级重出图）
```

**学名主键规范**：学名，空格换下划线。例 `Melilotus officinalis ` → `Melilotus_officinalis`。
包会在读入时自动规范化（含去尾空格），并输出 `species_name_map` 供追溯。**中文名不能作主键**（封丘 150 个学名只对应 142 个中文名，`酢浆草`/`金狗尾`/`茜草`/`夏至草` 各有 2 个物种共用）。

### 第 2 步：改配置
只改 `config/config.R`，不动模块代码。要改的通常是：
- `design$factors` — 分组因子名（任意个，如 `c("Habitat","Season")`）
- `design$random` / `design$time` / `ordered_levels`（因子的固定顺序）
- `response$*` — 哪些列是 α / 功能 / 谱系指数
- `opts$alpha_test` — 组间比较方法（`anova_tukey` / `nonparam_srh` / `kruskal_dunn` / `lmm`）
- `opts$runs` + `runs_label` — 置换次数与标记（测试 199 / 正式 999）
- `plot$size` — `single`(90mm) / `double`(190mm)

### 第 3 步：跑
复制 `run/_TEMPLATE_run_all.R` 到 `<论文项目>/run/`，改 `PROJECT_DIR` 与模块开关，然后：
```r
setwd("<论文项目>")
source("run/run_all.R")
```
结果 → `results/`（每模块一个 xlsx）、图 → `figures/`（pdf）、日志 → `logs/`。

**运行前务必**：R 脚本开头有 `Sys.setlocale("LC_CTYPE","Chinese_China.utf8")`——中文路径在 C locale 下会解析失败（见踩坑库 A1）。

---

## 2. 模块清单

| 组 | 编号 | 模块 | 一句话 |
|---|---|---|---|
| 基础 | 00 / 01 | setup / 数据体检 | 环境、主题、导出工具；体检 + 四方物种对齐 + 方法推荐 |
| 多样性 | 10 / 11 | α / β 多样性 | Shannon、Pielou、S；Bray/Jaccard + turnover-nestedness 分解 |
| 统计 | 12 / 14 / 15 | 组间比较 / 混合模型 / 时间自相关 | ANOVA+Tukey 字母 · SRH+Nemenyi · KW+Dunn；LMM + R² 分解；DW 检验 + 差分 |
| 功能 | 20 / 21 | 功能多样性 / 性状插补 | dbFD（FRic/FEve/FDiv/FDis/RaoQ/CWM）+ 功能β；missForest |
| 谱系 | 30 / 31 / 32 | 建树 / PD·NTI·NRI / 系统发育信号 | 校名+建树+树可视化；Faith PD、MNTD/MPD、NTI/NRI；phyloSignal/Correlogram/lipaMoran |
| 群落与出图 | 40 / 41 / 50 / 51 / 60 / 90 | 排序与差异检验 / 方差分解 / PCA+HCPC / 热图 / 绘图 / 地图 | NMDS+PERMANOVA+ANOSIM+两两比较；varpart；PCA/HCPC；pheatmap；箱线图+拼图+pdf；研究区底图 |
| 约束排序/回归/相关 | 42 / 43 / 52 | DCA+RDA/CCA+envfit / 线性回归散点 / Spearman corrplot | 对应 Diversity 2023 Fig 7/8/6 |
| 论文表格 | 70 | 论文表格导出 | 12 张（T1/T2/T3/S1/S2 + t4/t5/t6/t7/t8 + s3/s4）→ `tables/tables.docx`；三线表 + Times New Roman |

---

## 3. 六条使用纪律（来自这个包的设计约定）

1. **物种主键只认学名**（下划线）。中文名可见于结果表，但不参与匹配。
2. **缺数据只报告、不动手**：不自动建树、不自动插补、不自动改学名，只列缺口等确认。
3. **统计口径不锁死**：每个模块保留可选方法，由你按数据与科学问题拍板（包会给有依据的推荐）。
4. **结果可回溯**：每个统计量都能指回结果表的具体 sheet 与行；运行日志记录输入指纹与全部警告。
5. **输出精简**：每模块一个结果表 + pdf 图 + `tables/tables.docx`；不出汇总总表、默认不出 pptx/tif；距离矩阵单独存。
6. **拼图冗余必消，其余不删**：散图若已并入复合图 → 复合图落地后可删散图（`plot$save_singles=TRUE` 可留）；**未并入复合图的图、历史输出一律不删**，新图写新文件/新文件夹。

---

## 4. 缺包怎么办

包的每个模块在缺包时**不报错退出**，而是打印安装命令并继续。
当前环境（R 4.5.2）已装：vegan、betapart、FD、picante、car、multcomp、dunn.test、rcompanion、lme4、lmerTest、emmeans、lmtest、ggpubr、ape、ggtree、treeio、tidytree、V.PhyloMaker、FactoMineR、factoextra、pheatmap、patchwork、cowplot、ggbeeswarm、scales、RColorBrewer、ggsci、export、ragg、svglite、sf、terra、ggspatial、rnaturalearth、tidyverse、**flextable、officer、readxl、openxlsx、pdftools** 等。

未装（按需安装）：
```r
install.packages(c("glmm.hp", "MCMCglmm", "missForest", "phylosignal", "phylobase",
                   "flextable", "officer", "readxl", "openxlsx", "pdftools"))
remotes::install_github(c("helixcn/plantlist", "jinyizju/V.PhyloMaker2"))
# 校验：
sapply(c("flextable","officer","readxl","openxlsx","pdftools"), requireNamespace, quietly = TRUE)
```
- `glmm.hp` → 14 模块的 R² 分解
- `missForest` → 21 模块
- `phylosignal` + `phylobase` → 32 模块
- `plantlist` + `V.PhyloMaker2` → 30 模块（有 `V.PhyloMaker` v1 作备选）
- **`flextable` + `officer` + `readxl`** → **70 论文表格 `tables.docx`**（缺则跳过表格，不影响图）
- **`openxlsx`** → 写 `results/*.xlsx`；**`pdftools`**（或系统 `qpdf`）→ 合并 base 图形散件

---

## 5. 文档索引

| 文件 | 内容 |
|---|---|
| `SKILL.md` | 给 AI 的工作流与提问协议 |
| `references/00-data-contract.md` | 输入契约与学名主键规范 |
| `references/01-method-menu.md` | 科学问题→模块；模块→方法选项与推荐规则 |
| `references/02-module-specs.md` | 23 个模块的函数签名、输入输出、验收要点 |
| `references/03-pitfalls.md` | 踩坑库（含封丘实测 12+ 条） |
| `references/04-paper-tables.md` | **论文表格映射**：12 张表逐列来源、三线表格式、p/mean±SD 规则、已定口径 |
| `references/05-skill-review.md` | **skill-optimizer 审查结论**（模式判断 / 安全与依赖 / 优先级 / 不改动项 / 额外建议） |
| `config/config_template.R` | 配置模板（含 `design$sampling`、`table$which`、`opts$env` 等） |
| `VALIDATION.md` | **真实数据验证记录**（三轮复验 + 换建树工具对比） |
| `assets/` | `simulate_env.R` / `simulate_community.R`（模拟数据生成器，seed + 构造公式可复现）、`05_env_template.csv`、`project_skeleton`（新项目骨架）。⚠️ 此处是**脚本与模板**，不是「输出资源」——命名沿用，未拆 `scripts/` 以免断引用 |
| `run/_TEMPLATE_run_all.R` | 调用脚本模板（21 个 RUN 开关） |
| `code/` | **生成产物目录**（第 5 步把 `NN_模块名.R` 调用脚本写这里，函数体不复制） |
| `data/` | **示例数据（模板，都不能进论文）**，含 `05_env_simulated.csv`（模拟环境）。**永不改写**——`pd_assert_not_data()` 硬门槛 |
