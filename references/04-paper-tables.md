# 04 · 论文表格映射（tables.docx）

> **序号规则（2026-09-24 改）**：两篇论文的表并成**一套连续序号 `Table 1 … 8`**，**不再用 S 系列**。
> 内部键（`t1/t2/t3/t4/t5/t6/t7/t8/s1/s2/s3/s4`）是稳定 ID，只用于 config 与代码；**显示号按 `pd_run_paper_tables(which=)` 的顺序编**，想重排只改 `which` 的顺序。
>
> ★★ **出哪几张表必须先和用户沟通，不要默认全出**（用户 2026-09-25）。写进 `config$table$which`。
> 本文件列的是 skill **能出**的全部 12 张，不是每次都要出的清单 —— 按论文实际要的挑。
>
> | 显示号 | 内容 | 内部键 | 来源论文 |
> |---|---|---|---|
> | **Table 1** | 两两 ANOSIM + PERMANOVA | `t1` | EI Table 1 |
> | **Table 2** | PERMANOVA 主效应 | `t2` | EI Table 2 |
> | **Table 3** | 双因素 ANOVA F、p | `t3` | EI Table 3 |
> | **Table 4** | 性状 + 谱系信号 | `s1` | EI Table S1 |
> | **Table 5** | 多样性指数 mean±SD | `s2` | EI Table S2 ≈ Diversity Table 2 |
> | **Table 6** | 优势种重要值 | `t4` | Diversity Table 1 |
> | **Table 7** | Spearman 相关 p 矩阵 | `t5` | Diversity Table 3 |
> | **Table 8** | 环境因子解释力 | `t6` | Diversity Table 4 |


> **范围铁律**：只做论文里实际存在的 **5 个表**（正文 T1/T2/T3 + 附录 S1/S2）。
> **不是每个分析都做一张三线表。** 新分析时固定出这 5 类表，只换因子名/响应变量（改 `config$table`）。
>
> 数值一律从 `results/*.xlsx` 现有结果表搬运，**不重算、不发明**；缺源就跳过该表并说明。

格式基准（Manuscript.docx XML 实测）：
- 表样式 **「三线表2」**：无竖线、无网格、无底纹
- **Times New Roman 8pt**（`w:sz=16` 半磅），行距 `line=480 auto`
- 表居中、固定布局；首列分组名纵向合并
- 显著性：`*` `<0.05`、`**` `<0.01`、`***` `<0.001`（沿用 skill `pd_sig()`）
- **p 值写法（用户已定）**：`<0.001 ***` / `0.023 *` / `0.178`（不照抄论文的 `0***`）

---

## T1 · ANOSIM + PERMANOVA 两两比较（正文 Table 1）

**题注（论文原文）**
> ANOSIM and PERMANOVA pairwise comparisons results. The ANOSIM R value indicates inter-group differences, while the PERMANOVA F value represents the inter-group-to-intra-group differences ratio. The R2 value signifies the proportion of inter-group differences to total differences. The p-values for each pair indicate significance.

**论文结构** 20 行 × 7 列，两层表头，首列纵向合并：

| 列1（合并） | 列2 | ANOSIM R | ANOSIM p | PERMANOVA F | R² | p |
|---|---|---|---|---|---|---|
| Field road | Spring / Summer | 0.791 | 0.001 | 18.447 | 0.327 | 0.001 |
| （合并） | Spring / Autumn | … | | | | |
| （合并） | Summer / Autumn | | | | | |
| Hedgerow | Spring / Summer … ×3 | | | | | |
| Woodland | … ×3 | | | | | |
| Spring | Hedgerow / Filed road … ×3 | | | | | |
| Summer | … ×3 | | | | | |
| Autumn | … ×3 | | | | | |

分组顺序 = **先按生境内比季节（3 生境 × 3 对比 = 9 行），再按季节内比生境（3 季节 × 3 对比 = 9 行）**。

**数据来源**
| 论文列 | 源 | 源列 | 说明 |
|---|---|---|---|
| 列1 分组 | `40_ordination.xlsx:pairwise_anosim` | `stratum` | `direction="within_f1_compare_f2"`（生境内比季节）→ 列1 = 生境；`direction="within_f2_compare_f1"`（季节内比生境）→ 列1 = 季节 |
| 列2 对比 | 同上 | `group1`, `group2` | 拼成 `Spring / Summer` |
| ANOSIM R | 同上 | `R` | 三位小数 |
| ANOSIM p | 同上 | `p`（或 `p_adj`？**待定**） | p 格式 |
| PERMANOVA F / R² / p | `pairwise_permanova` | `F`, `R2`, `p` | ⚠️ **见下方问题 1** |

---

## T2 · PERMANOVA 主效应（正文 Table 2）

**题注（论文原文）**
> Explained variance proportion (R2), analysis of variance F-values, and p-values from PERMANOVA analysis for the effects of seasons, habitats, their interaction, and residuals on plant community dissimilarity.

**论文结构** 5 行 × 4 列，单层表头：

| （空） | R2 | F | P |
|---|---|---|---|
| Season | 0.217 | 31.04 | 0.001 |
| Habitat | 0.172 | 24.60 | 0.001 |
| Season * Habitat | 0.034 | 2.52 | 0.001 |
| Residual | 0.577 | - | - |

**数据来源**
| 论文列 | 源 | 源列 |
|---|---|---|
| 行名 | `40_ordination.xlsx:permanova` | `term`（Season / Habitat / 交互 / Residuals） |
| R2 | 同上 | `R2`（三位小数） |
| F | 同上 | `F`（两位小数） |
| P | 同上 | `p`（Residual 行置 `-`） |

---

## T3 · 双因素 ANOVA F、p（正文 Table 3）

**题注（论文原文）**
> Analysis of variance F-values, and p-values from Two-Way ANOVA for the effects of seasons, habitats, and their interaction on plant diversity indices.

**论文结构** 5 行 × 9 列，两层表头：

| （空） | Shannon | | FRic | | PD | | SES.MNTD | |
|---|---|---|---|---|---|---|---|---|
| | F | p | F | p | F | p | F | p |
| Season | 83.309 | 0*** | … | | | | | |
| Habitat | … | | | | | | | |
| Season * Habitat | 1.594 | 0.178 | … | | | | | |

**数据来源**
| 论文列 | 源 | 说明 |
|---|---|---|
| 4 个响应变量 | `config$table$vars`（默认 `Shannon, FRic, PD, SES.MNTD`） | 新分析可换 |
| 行名 Season / Habitat / Season * Habitat | `config$table$factors` | `12_anova_tukey.xlsx:summary` 的 `term` |
| F | `12_anova_tukey.xlsx:summary` | `F`（三位小数），按 `variable × term` 透视 |
| p | 同上 | `p`，格式化为 `<0.001 ***` |

---

## S1 · 性状 + 谱系信号（附录 Table S1）

**题注（论文原文）**
> Plant functional traits and their phylogenetic signals. Light Ellenberg, Moisture Ellenberg, Nitrogen Ellenberg, and pH Ellenberg represent the Ellenberg plant ecological indices, indicating plant adaptability and preference towards light, moisture, nitrogen content, and soil pH values. K and λ represent Blomberg's K and Pagel's λ values, respectively. p.K and p.λ indicate the significance of differences based on Blomberg's K test and Pagel's λ test, respectively. "*", "**", and "***" represent p-values of <0.05, <0.01, and <0.001, respectively.

**论文结构** 30 行 × 7 列，29 个性状：

| （性状名） | Unit | Mean value | K | p.K | λ | p.λ |
|---|---|---|---|---|---|---|
| Seed dry mass | mg | 17.544 | 0.109 | 0.023 * | 0.708 | 0.001 ** |
| Seed length | mm | 2.725 | 0.104 | 0.041 * | 0.612 | 0.001 ** |
| …（共 29 行） | | | | | | |

**数据来源**
| 论文列 | 源 | 说明 |
|---|---|---|
| 性状名 | `32_signal.xlsx:phylo_signal` 的 `trait` | |
| Unit | **不在数据里** | ⚠️ **见问题 2**：论文手写单位；config 配性状→单位字典 |
| Mean value | `20_traits_used.csv` 各性状列的均值 | ⚠️ **见问题 2**：口径需确认 |
| K / p.K | `32_signal.xlsx:phylo_signal` | 长表 `statistic == "K"` → `value` / `p` |
| λ / p.λ | 同上 | `statistic == "Lambda"` → `value` / `p` |

---

## S2 · 多样性指数 mean±SD（附录 Table S2）

**题注（论文原文）**
> Plant species, functional, and phylogenetic diversity indices (mean ± standard deviation) by seasons and habitats.

**论文结构** 10 行 × 6 列，首列纵向合并：

| 生境（合并） | Season | Shannon | FRic | PD | SES.MNTD |
|---|---|---|---|---|---|
| Filed road | Spring | 2.55±0.27 | 30.31±12.64 | 2243.27±340.30 | -0.86±0.30 |
| （合并） | Summer | 2.09±0.26 | … | | |
| （合并） | Autumn | … | | | |
| Hedgerow | Spring / Summer / Autumn | | | | |
| Woodland | Spring / Summer / Autumn | | | | |

**论文此表无 Tukey 字母 → 不加。**

**数据来源**
| 论文列 | 源 | 说明 |
|---|---|---|
| 生境 / 季节 | `12_anova_tukey.xlsx:group_means` 的 `cell` | `cell` 格式 `"Season | Habitat"`（`paste(f1, f2, sep=" | ")`）→ 拆开重排为 生境×季节 |
| 4 列指标 | `config$table$vars` | 同 T3 |
| 数值 | `group_means` 的 `mean`, `sd` | 拼 `x.xx±x.xx`（两位小数） |

---

## 已定口径（用户拍板，2026-09-24）

> 本节取代早先的「待拍板 2 个问题」。执行时**直接按此办**，不再重新纠结。

| 项 | 决定 | 依据 |
|---|---|---|
| **T1 的 PERMANOVA 两两比较** | **补一个分层两两 PERMANOVA**（`pd_pairwise_permanova` 加 `strata`，口径与现有分层 ANOSIM 完全一致），输出 `40_ordination.xlsx:pairwise_permanova_strat` | 用户选 (a)。检验方法不变，只换分层方式；使 T1 的 18 行齐整（生境内比季节 9 + 季节内比生境 9），与 ANOSIM 侧一一对应 |
| **S1 的 Mean value** | = `20_traits_used.csv`（或 `03_traits.csv`）**该性状列在全部物种上的均值** | 已实测：29 个性状中 **28 个与论文逐位一致** |
| **S1 的 Unit** | 从 `results/trait_name_map.csv` 的 TRY 长名括号解析（如 `Seed dry mass (mg)` → `mg`）；`config$table$trait_units` 可覆盖；**没有就留 `-`，不发明** | 原数据确实带单位 |
| **Leaf_width** | **照数据：2.175 cm**（TRY 原单位 cm），**不做 ×10 换算** | 用户选「照数据」。论文写 21.75 mm 是做了 cm→mm 换算；其余 28 个均沿用 TRY 原单位 |
| **T2 的 F 小数位** | **2 位**（如 `31.04`），照论文 | 论文里 T2 的 F 是 2 位，T1/T3 的 F 是 3 位（`18.447`/`83.309`）——按论文分别保留 |
| **S2 的行序** | 跟 `config$design$ordered_levels`（不追论文的 Filed road 在前） | 用户选「跟 config 顺序」 |
| **p 值格式** | `lt001`：`<0.001 ***` / `0.023 *` / `0.178`（**不照抄**论文的 `0***`） | 用户选规范写法 |
| **S2 的 Tukey 字母** | **不加** | 论文 S2 此表本无字母 |
| **缺源处理** | 该表跳过，并在日志/`tables_register` 标 `skipped: source missing`；**不造数、不留空壳** | 科研数据绝对诚实 |

### 实测溯源（S1 Mean value 口径验证）
对 `03_traits.csv`（148 物种）取列均值，与论文 Table S1 的 Mean value 比对：

| 结果 | 数量 | 说明 |
|---|---|---|
| 逐位一致 | 28 / 29 | 如 Seed dry mass `17.544`、Leaf thickness `0.207`、Plant height `1.153` |
| 舍入级差 ≤0.01 | 3 个 | Leaf_length `69.381` vs `69.371`、Leaf_water `4.915` vs `4.914`、Leaf_P `0.106` vs `0.107` |
| **单位换算差 ×10** | 1 个 | **Leaf_width**：算得 `2.175`（cm）vs 论文 `21.750`（mm）→ 已定照数据 |

→ **结论：Mean value = 性状列均值的口径成立。** 另两处微差是论文显示位舍入，不是口径问题。

---
---

# 第二批表（Diversity 2023, 15, 9922）—— t4 / t5 / t6

> 来源：`D:\01-Academic\01-小论文春夏秋SCI\12-diversity 接收后\diversity-2495217\manuscript.v6.docx` 的 Table 1 / 3 / 4。
> **约束**：只补 skill 缺的表；同类表以 skill 现有 `T1/T2/T3/S1/S2` 为准（Times 8pt 三线表 + `<0.001 ***`）；**skill 的变量（Season/Habitat）优先**，论文的土壤因子名与土层结构不照搬。

## 不补的表

| Diversity 表 | 为什么不补 |
|---|---|
| **Table 2**（7 指数 mean±SD × 季节） | **skill 的 `s2` 已是这类表**。`s2` 在 `factor_mode="single"` 下自动变成「按季节」，无需新表 |
| **Table 1 的「按季节分列」结构** | 结构保留，但列名由 skill 的分组因子决定（见 t4） |
| **Table 4 的「3 个土层」分组结构** | skill 的环境表无土层维度 → 压成单组 3 列（见 t6） |

---

## t4 · 优势种重要值（← Diversity Table 1）

**题注（论文原文）**
> Seasonal variation in dominant plant species importance values. Species listed in this table are dominant plant species with average importance values greater than 1%, classified using the Angiosperm Phylogeny Group IV (APG IV) classification system.

**论文结构** 15 行 × 5 列，**两层表头**，首列无合并（但 Species/Family 跨表头行 vMerge）：

| Species（vMerge） | Family（vMerge） | Importance Values（gridSpan=3） | | |
|---|---|---|---|---|
| | | Spring | Summer | Autumn |
| Chenopodium serotinum | Amaranthaceae | 42.52% | 19.51% | 0.32% |
| …（13 个种） | | | | |

- 数值为**百分数字符串**（`42.52%`），两位小数
- **无显著性标注**

**skill 适配（列名不照搬论文）**
| 论文列 | skill 列 | 说明 |
|---|---|---|
| Species | 同 | 学名 |
| Family | 同 | 取 `04_species_list.csv` 的 `family`；缺则留 `-`（不发明） |
| Spring / Summer / Autumn | **`table$t4_group` 的各水平** | 默认 `"Season"` → `Spring/Summer/Autumn`；用户可改 `"Habitat"` → `Woodland/Hedgerow/Filed road` |

**数值口径（需你确认）**：
- skill 的 `01_abundance.csv` 每格是**样方级重要值**（非个体计数，见 pitfalls G3）
- 每组的种 IV = **该组样方该种 IV 的均值**，再按组内合计归一成 `%`
- 入选条件 = **全数据平均 IV > `table$iv_threshold`（默认 1%）**，与论文口径同
- 数据来源：`dat$abundance` + `dat$meta`（**表构建内轻量汇总**，不建分析模块）

---

## t5 · Spearman 相关 p 矩阵（← Diversity Table 3）

**题注（论文原文）**
> The significance of the Spearman correlation analysis of each diversity index. Significance results are indicated by asterisks: "*", p < 0.05; "**", p < 0.01; "***", p < 0.001.

**论文结构** 8 行 × 8 列（7 指数），**对角留空**：

|  | Shannon | Simpson | Pielou | Margalef | PD | NTI | NRI |
|---|---|---|---|---|---|---|---|
| Shannon | | 0 *** | 0.023 * | … | | | |
| …（7 行） | | | | | | | |

- 单元格 = **p 值 + 星号**（论文写 `0 ***`；**本包用 `<0.001 ***`**，已定）

**skill 适配**
| 论文 | skill |
|---|---|
| 7 指数（Margalef/Simpson/…） | **`config$table$vars`**（默认 `Shannon, FRic, PD, SES.MNTD`）→ **4×4** 矩阵 |
| p 值 | `52_spearman.xlsx:p_matrix` |
| 格式 | `pd_fmt_p(stars=TRUE, style="lt001")` → `<0.001 ***` / `0.023 *` / `0.178` |
| 脚注 | `"*", "**", "***" represent p-values of <0.05, <0.01, and <0.001, respectively.` |

---

## t6 · 环境因子解释力（← Diversity Table 4）

**题注（论文原文）**
> Values of soil environmental factors and their explanatory power for changes in plant communities. Monte Carlo permutation test analysis was conducted to determine the significance of soil environmental factors on plant community changes across 0–10 cm, 10–20 cm, and 0–20 cm soil layers. M ± SD represents the mean ± standard deviation of soil environmental factors in 12 plots. R2 represents the proportion of variation in plant community changes explained by the soil environmental factors. Significance levels are indicated as follows: "*", p < 0.05; "**", p < 0.01.

**论文结构** 8 行 × 11 列，**两层表头**（3 个土层 × 3 列）：

| Soil Factors（vMerge） | Unit（vMerge） | 0–10 cm（gridSpan=3） | | | 10–20 cm | | | 0–20 cm | | |
|---|---|---|---|---|---|---|---|---|---|---|
| | | M ± SD | R² | p | M ± SD | R² | p | M ± SD | R² | p |
| pH | - | 8.13 ± 0.06 | 0.501 | 0.036 * | … | | | | | |

**skill 适配（无土层维度 → 压成 5 列）**
| 论文列 | skill 列 | 说明 |
|---|---|---|
| Soil Factors | **Env Factor** | 行名 = `config$opts$env`（默认 `pH, AK, AP, AN, SOM, SMC`） |
| Unit | 同 | `config$table$env_units` 字典；**没有就留 `-`，不发明** |
| M ± SD | 同 | 该环境变量**全部样方**的均值 ± 标准差 |
| R² | 同 | `envfit` 的 R² |
| p | 同 | `envfit` 的 p + 星号（`lt001`） |

> **土层分组不照搬**：skill 的环境表 `05_env_simulated.csv` 只有一层。若新论文有分层，把各层做成 `opts$env` 里的多个列（如 `SOM_0_10`、`SOM_10_20`），表仍是「一列变量一行」。

**⚠️ 论文疑似笔误（不照抄）**：Table 4 的 AN 0–20 cm 写 `2740 ± 2.47`，按 0–10 cm（`28.33 ± 2.31`）与 10–20 cm（`26.47 ± 3.05`）推应为 `27.40 ± 2.47`。**本包按真数据算，不复制这个数。**

**脚注**：`"*", "**", and "***" represent p-values of <0.05, <0.01, and <0.001, respectively.`

---

## 第二批表 · 已定口径

| 项 | 决定 |
|---|---|
| 格式 | 全部跟 skill 现有 `T1/T2/T3/S1/S2`：**Times New Roman 8pt 三线表** + `pd_fmt_p(style="lt001")`。**不跟** MDPI 的 Palatino 10pt / `0 ***` |
| t4 分组列 | 由 `config$table$t4_group` 决定（默认 `"Season"`），**不写死**春夏秋 |
| t4 数值口径 | 组内样方 IV 均值 → 归一成 `%`；入选阈值 `table$iv_threshold`（默认 1%）—— **待用户确认** |
| t5 变量 | `config$table$vars`（4 个），**不是**论文那 7 个 |
| t6 | 无土层分组；M±SD 按全数据；Unit 缺则 `-` |
| 缺源 | 同第一批：跳过 + 登记 `skipped`，不造数 |

---

# 第三批表（硕士论文）—— t7

## t7 · RDA Monte-Carlo 置换（← 硕士论文表 7-1）

**论文表结构**（`…\03-毕业论文\论文稿件\盲审后*.docx`）：
题注（中文原文）：「土壤环境因子对黄淮平原植物群落组成的定量分析（Monte-Carlo 置换检验）。RDA1、RDA2 代表环境因子与植物群落数据在第一和第二 RDA 轴上的相关性，R² 表示统计拟合优度，p 为显著性水平（p < 0.05 表示差异显著）。*、**、*** 分别表示 p < 0.05、p < 0.01、p < 0.001。」

**出表口径**：题注译成**英文**（skill 现有 9 张题注全英文，保持一致）；格式同其他表（Times New Roman 8pt 三线表）。

| 列 | 来源（`results/42_rda.xlsx:envfit`） | 显示格式 | 论文实测 |
|---|---|---|---|
| Env Factor | `env` | 纯列名（`pH/SMC/AK/AP/AN/SOM/XN`） | 论文是「土壤含水量 (SMC)」中英混排 → **照 skill 纯列名** |
| RDA1 | `RDA1` ← `ef$vectors$arrows[,1]` | **5 位小数** | `-0.07964`（5 位） |
| RDA2 | `RDA2` ← `ef$vectors$arrows[,2]` | **5 位小数** | `-0.99682`（5 位） |
| R² | `R2`（= envfit `r²`） | **4 位小数** | `0.5795`（4 位） |
| p | `p` | `pd_fmt_p(style="lt001")` → `<0.001 ***` / `0.005 **` | 论文写 `0.000 ***` / `0.005 **` —— **保持 skill 口径** |

**★ 关键口径（pitfalls H11）**：
- RDA1/RDA2 是 **`ef$vectors$arrows` 的单位长度方向余弦**（`RDA1² + RDA2² = 1`，逐行验过）
- **不是** `mod$CCA$biplot`（那是图上箭头坐标，长度∝拟合优度，平方和 ≠ 1）
- **不是** `summary(mod)$biplot`（vegan ≥2.6 已移除该返回值）

**与 t6 的差异**（故新表，不改 t6）：

| | t6 | t7 |
|---|---|---|
| 列 | Env Factor / Unit / M±SD / R² / p | Env Factor / RDA1 / RDA2 / R² / p |
| M±SD | 有 | **无** |
| 轴坐标 | 无 | **有（方向余弦）** |
| 数据源 | `42_*:envfit` + `files$env` 全表 M±SD | `42_*:envfit` 的 `RDA1/RDA2/R2/p` |

**内部键 / 显示号**：键 `t7`；`which` 默认加在末位 → 显示号 **Table 9**（前 8 张顺序不动）。

## 第三批表 · 已定口径

| 项 | 决定 |
|---|---|
| t7 RDA1/RDA2 | `ef$vectors$arrows` 单位长度方向余弦，5 位小数 |
| t7 R² | envfit `r²`，4 位小数 |
| t7 p | skill 口径 `<0.001 ***`（**不照抄**论文的 `0.000 ***`） |
| t7 题注 | 译英文；中文原题注存本文件作对照 |
| t7 列名 | 纯列名，无单位列（单位见 t6） |
| 缺源 | 同上：跳过 + 登记 `skipped`，不造数 |

---

# 第四批表（Plant and Soil 投稿版）—— t8 / s3 / s4

> 来源：`D:\01-Academic\03-小论文不同干扰植物多样性\09-Plant and Soil\01-投稿文件\Supplementary file 1.docx`
> （*Effects of mowing and herbicide application on plant diversity in non-agricultural habitats*）
> **三种都是纯版式扩展**，不改统计口径、不动前 9 张表（回归验收：T1–T9 逐格一致）。
> 论文用 Month（Apr.–Oct. 6 档）与干扰方式 CK/HM/HW/LM/LW/M+W；**skill 用 `design$time`（Season）与 `factors[1]`（Habitat）**，不搬 Month/干扰。

## t8 · 「时间 × 分组」mean±SD（← 论文 Table S3–S6）

**论文版式**（4 张表同构）：
| 论文表 | 表头（逐字） | 行 |
|---|---|---|
| Table S3 | `Indicators \| Month \| CK \| HM \| HW \| LM \| LW \| M+W` | HT/COV/DEN × 6 月 = 19 行 |
| Table S4 | `Month \| CK \| HM \| HW \| LM \| LW \| M+W` | Shannon × 6 月 = 7 行 |
| Table S5 | `Month \| CK \| HM \| HW \| LM \| LW \| M+W` | PD × 6 月 = 7 行 |
| Table S6 | `Indicators \| Month \| CK \| HM \| HW \| LM \| LW \| M+W` | NRI/NTI × 6 月 = 13 行 |

**skill 出表**（`pd_table_t8`）：

| 项 | 论文 | skill |
|---|---|---|
| 行 | `Month` | **`cfg$design$time` 的水平**（Season：Spring/Summer/Autumn） |
| 列 | 干扰方式 6 水平 | **`pd_design_factors(cfg)[1]` 的水平**（Habitat：Woodland/Hedgerow/Filed road） |
| 单元格 | `mean±SD` | `pd_fmt_mean_sd()` |
| 多指标 | 指标名纵向堆叠、只写首行 | 同（`merge_v(j=1)`） |
| 指标集 | S3=HT/COV/DEN；S6=NRI/NTI | **`table$t8_vars`** |
| 数据源 | — | `results/12_<method>.xlsx:group_means`（与 s2 同源，**只重排不重算**） |

**实测输出**（180 样方封丘示例）：
```
Indicator | Season | Woodland      | Hedgerow      | Filed road
Height    | Spring | 57.74±5.60    | 58.45±4.51    | 52.82±7.67
          | Summer | 51.42±5.01    | 49.89±6.84    | 42.62±7.87
          | Autumn | 49.37±7.01    | 48.13±5.88    | 37.12±8.05
Coverage  | Spring | 74.16±7.29    | 74.09±7.76    | 72.22±9.12
          | ...
```

**内部键 / 显示号**：键 `t8`；`which` 末位 → **Table 10**。
**降级**：单因素设计 → 跳过 + 提示改用 s2；`t8_vars` 都不在 `group_means` 里 → 跳过，不造数。

## s3 · 并排双栏基线描述（← 论文 Table S1）

**论文版式**：`Indicators (Unit) | Values | Indicators (Unit) | Values`（9 行 × 4 列，16 个指标并排）
中文原题注：「植被与土壤因子本底值（平均值 ± 标准差，n = 18）」
论文指标：Vegetation coverage/height/density、Species、Shannon、Pielou、**Simpson**、Phylogenetic diversity、NTI、NRI、Soil pH、SOM、SMC、AN、AP、AK

**skill 出表**（`pd_table_s3` + `pd_baseline_stats`）：
- 全体样地**合并**（不分组）的 `mean±SD` → 拆左右两栏
- 指标名带单位：`Height (cm)`；**单位未知就不带括号**（不发明单位）
- 指标集 = `table$s3_vars`，缺省 = `response` 四组 + `opts$env`
- 数据源：响应变量 ← `dat$meta`；环境变量 ← `files$env`

**内部键 / 显示号**：键 `s3`；→ **Table 11**。

## s4 · 物种名录（← 论文 Table S2）

**论文版式**：`Latin name | Genus | Family | Order`（47 种）
中文原题注：「研究区植物物种名录」+ 注「物种及其分类信息依据被子植物 APG IV 分类系统」

**skill 出表**（`pd_table_s4`）：
| 论文列 | skill 来源 | 缺失时 |
|---|---|---|
| Latin name | `04_species_list.csv:species` | **整表跳过**（必需列） |
| Genus | `:genus` | 该列填 `-` |
| Family | `:family` | 该列填 `-` |
| Order | `:order`（**2026-09-25 新增可选列**） | **整列省略**，并提示加列 |

**不自动从 V.PhyloMaker2 树里猜 Order** —— 「缺数据只报告不动手」。
**内部键 / 显示号**：键 `s4`；→ **Table 12**。

## 第四批表 · 已定口径

| 项 | 决定 |
|---|---|
| 时间维 | 用 `design$time`（Season），**不搬论文的 Month 6 档** |
| 列序 | 用 `design$ordered_levels`，**不搬 CK/HM/HW/LM/LW/M+W** |
| t8 数值 | 与 s2 同源 `group_means`，只重排不重算 |
| s3 单位 | 只用 `table$community_units` / `table$env_units` 里已声明的；缺则不带括号 |
| s4 Order | 缺列就省略，不造数 |
| 题注 | 英文（与前 9 张一致）；中文原题注存本文件作对照 |
| 缺源 | 跳过 + 登记 `skipped`，不造数 |


