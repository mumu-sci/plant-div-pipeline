# 00 · 数据输入契约（Data Contract）

本文件定义 `plant-div-pipeline` 唯一认可的输入格式。**任何新论文的数据，先整理成这里的 5 个文件，再进入分析流程。**
整理一次，后续所有模块零适配。

---

## 1. 目录约定

```
<论文项目>/
├─ data/                      ← 只放这 5 个文件（可另建 data/raw/ 存原始未整理数据）
│  ├─ 01_abundance.csv
│  ├─ 02_sample_meta.csv
│  ├─ 03_traits.csv
│  ├─ 04_species_list.csv
│  └─ 99_phylo.tre
├─ config/config.R            ← 由 config/config_template.R 复制修改
├─ code/                      ← 生成的调用脚本
├─ results/                   ← 每个模块一个结果表（.xlsx）
├─ figures/                   ← 每个模块一组 pdf 图
└─ logs/                      ← 运行日志（含每步的输入指纹）
```

**不建汇总总表**（用户明确要求：每模块一个表）。

---

## 2. 五个文件

### 2.1 `01_abundance.csv` — 多度矩阵
| 要求 | 说明 |
|---|---|
| 第一列名 | 必须为 `sample_id` |
| 行 | 每个样方一行；行数 = 样方数 |
| 列 | 除 `sample_id` 外全部是物种列，列名为**学名主键** |
| 数值 | 多度（重要值/盖度/个体数均可，但全表口径必须一致）；`NA` 一律视为 0 并在日志中记录替换数量 |
| 禁止 | 不允许有重复列名；不允许有全 0 列（会被自动剔除并记录） |

### 2.2 `02_sample_meta.csv` — 样方元数据
| 要求 | 说明 |
|---|---|
| 第一列名 | 必须为 `sample_id`，且与 `01_abundance.csv` **完全一一对应**（无多无少） |
| 因子列 | 任意个数、任意命名；在 `config.R` 的 `design$factors` 里声明 |
| 可选 | 协变量（连续型）、随机因子（如 Site）、时间因子（如 Season） |
| **响应列** | 多样性指数（`Shannon/Pielou/S/Simpson/F.Ric/…/PD/mntd/mpd/NTI/NRI`）+ **群落结构变量**（可选）都放这里。缺列时可由 `pd_enrich_meta` 从 `results/` 回填（见 §2.5） |
| **群落结构变量** | `Height`（株高，cm）/ `Coverage`（盖度，%）/ `Density`（密度，株·m⁻²）—— 别名 `HT/COV/DEN`、`height/coverage/density` 由 `pd_match_var` 解析 |
| | 声明在 `config$response$community`；12/52/60/43 都吃这组；**缺列时优雅跳过，不报错** |
| | ⚠️ skill 示例里这 3 列是【**模拟数据**】（`assets/simulate_community.R` 生成，首行 `#` 注明）；**新论文请填实测值** |
| | 单位写 `config$table$community_units`（缺则 `-`，不发明） |
| 注意 | 因子水平名不要含首尾空格；有序因子的顺序在 `config.R` 的 `ordered_levels` 里指定 |

> **写新论文时，因变量（响应变量）必须先和用户沟通再填**（SKILL.md 第 3 步）—— 不许代选。

### 2.3 `03_traits.csv` — 性状表（功能/降维模块需要）
| 要求 | 说明 |
|---|---|
| 第一列名 | 必须为 `species`，值为学名主键 |
| 列 | 每个性状一列。**建议用 ASCII 短名**（如 `SLA`、`Leaf_N`、`Seed_mass`），避免 TRY 长名带来的引号/编码问题 |
| 缺失 | 允许 `NA`；是否插补由用户决定（`21_impute.R`），**包不自动插补** |
| 重复 | 一个物种一行；重复学名会被报错拦下 |

### 2.4 `04_species_list.csv` — 物种对照表（建树/校名需要）
| 列名 | 说明 |
|---|---|
| `species` | 学名主键 |
| `genus` | 属名 |
| `family` | 科名 |
| `order` | **目名（可选，2026-09-25 新增）** —— 表 `s4`（物种名录）用它出第 4 列；缺则整列省略，不造数 |
| `species_cn` | 中文名（可选，仅供核对，**绝不作主键**） |

### 2.5 响应指数的两种来源（重要，2026-09-25）

| 来源 | 说明 |
|---|---|
| **A. 直接写在 `02_sample_meta.csv`** | 最常见。多样性/群落结构指数算好后作为列放进去 |
| **B. 由模块算出、落在 `results/*.xlsx`** | `10_alpha`（S/Shannon/**Simpson**/Pielou）、`20_fd`（F.Ric…）、`31_pd_nti_nri`（PD/mntd/mpd/**NTI**/**NRI**） |

B 的结果**不会自动进 meta** —— 不回填的话，写进 `config$response` 也永远进不了 12/52/60/43。
`pd_enrich_meta()`（`R/00_setup.R`，`opts$enrich_meta=TRUE` 默认开）会按 `sample_id` 把缺的响应列
从 `results/*.xlsx` 并进 meta，**只并内存、绝不改写 CSV**：

```log
[data] meta 缺列 Simpson ← 10_indices.xlsx:result（按 sample_id 对齐）
[data] meta 缺列 NTI     ← 31_runs999_final.xlsx:pd_nti_nri（按 sample_id 对齐）
```

> ⚠️ **`data/*.csv` 绝不回写** —— 封丘真实植物数据受 md5 校验保护（见 §6）。
> **2026-09-25 已加代码层硬门槛**：`pd_assert_not_data()` 拦 4 个写出口，`pd_verify_data_unchanged()` 交付前比对 md5。
> 仅剩的口子是绕过 `pd_*` 直接 `write.csv`，由交付校验兜底。

### 2.6 重要值（Importance Value, IV）怎么来的

`01_abundance.csv` 每格**应是样方级重要值**。skill 不算 IV（论文自己也是 Excel 先算好再进 R），
但这里记下常用公式，便于从原始调查表得到它：

```
RD = 该种株数   / 样方总株数      （relative density）
RC = 该种盖度   / 样方总盖度      （relative coverage）
RH = 该种平均高 / 样方总平均高    （relative height）
IV = f(RD, RC, RH)               （通常取三者平均）
```
来源：Plant and Soil 稿 2.4 节（与学位论文 3.6 节同）。

**原始调查表长什么样**（该稿的 `plant survey data.xlsx`）：
`中文名 | Latin Name | 中文属名 | Genus Name | 中文科名 | Family Name | Indicator | Plot 1..18`
其中 **`Indicator` 列三段堆叠**：`Number`（株数）/ `Height (cm)`（高度）/ `Coverage (%)`（盖度），
每段各物种一行。上式三项就是从这三段算出来的。

### 2.5 `99_phylo.tre` — 系统发育树
| 要求 | 说明 |
|---|---|
| 格式 | Newick（`ape::read.tree` 可读） |
| tip 标签 | 与 `species` 主键完全一致 |
| 要求 | **有枝长**（用于 PD/MNTD）；无枝长的树会被报错提示，需改用有枝长的树 |

---

## 3. 学名主键规范（最重要的一条）

主键 = **学名，空格全部换成下划线**。

```
规范化规则 normalize_species():
  1. 去掉首尾空白（含 \t）
  2. 内部连续空白 → 单个下划线
  3. 去掉多余下划线（连续下划线合并）
  4. 保留下划线原样（不再做其他替换）
```

示例：

| 原始写法（各处不一致） | 规范化后 |
|---|---|
| `Melilotus officinalis `（尾空格） | `Melilotus_officinalis` |
| `Cirsium arvense var. integrifolium ` | `Cirsium_arvense_var._integrifolium` |
| `Helianthus_tuberosus `（树 tip 尾空格） | `Helianthus_tuberosus` |

**所有模块入口都会调用 `normalize_species()`，并输出一份 `species_name_map.csv`（原始名 → 主键）用于追溯。**

### 为什么不用中文名作主键
封丘数据里 150 个学名只对应 142 个中文名 —— `酢浆草`、`金狗尾`、`茜草`、`夏至草` 各有 2 个不同物种共用同一中文名。
用中文名作主键会**静默合并物种**，多样性指数直接算错。

---

## 4. 数据体检（`01_data_health.R`）必查项

体检不通过 → 停止后续分析，先修数据。检查清单：

1. 五个文件是否存在；表维度、列名、缺失率
2. `sample_id` 在 meta 与 abundance 是否**完全一致**（列出差集）
3. **四表物种名对齐**：abundance / traits / species_list / tree 之间的交集与差集，**逐名列出**
4. 学名规范化后是否有重复（合并冲突）
5. 每个因子：水平数、每组合样本量（判断能否做交互项、两两比较、随机效应）
6. 因变量诊断：Shapiro-Wilk 正态性、Bartlett/Levene 方差齐性、离群点
7. 树是否有枝长；tip 数 vs abundance 物种数差异（有多少物种不在树里）

第 6 项的输出是**方法推荐（有科学依据）的依据** —— 见 `01-method-menu.md`。

---

## 5. 命名与编码纪律

- 所有文件 **UTF-8 无 BOM**（`readxl`/`read.csv(fileEncoding="UTF-8")` 均可正常读）
- 单元格内**不留首尾空格**（规范化会兜底，但日志会记录，尽量在源头修）
- 中文只出现在注释、`species_cn`、图标签；**代码与数据主键全走 ASCII + 拉丁学名**

---

## 6. `data/*.csv` 的 md5 约定（2026-09-25 已加代码层硬门槛）

**三道防线**：
| 层 | 位置 | 说明 |
|---|---|---|
| **① 写拦截（硬）** | `R/00_setup.R` 的 **`pd_assert_not_data()`** | 4 个写出口（`pd_write_table` / `pd_write_matrix` / `pd_save_pdf` / `pd_save_any`）**统一调用**；落盘路径解析后若在 `data/` 下 → **`stop()`**，不静默跳过 |
| **② 交付校验（硬）** | `pd_verify_data_unchanged()` | `pd_setup()` 开跑时记 `data/*.{csv,tre}` 的 md5 快照进 `.pd$data_md5`；第 10 步复核调用此函数比对，**变了就 `stop()`** |
| **③ 缓存失效键** | `pd_cached()` | 数据文件 md5 变了 → 缓存失效、自动重算（这条不是保护，是防脏缓存） |

> ⚠️ **①只拦 `pd_*` 出口**。你直接调 `write.csv("data/x.csv", …)` 仍不会被拦 —— 那属于绕过本包，
> 靠 ②在交付时兜底。**仍建议**对 `data/*.csv` 设 Windows 只读属性作第四道（右键 → 属性 → 只读；
> 注意换机器/拷贝后失效，所以不是唯一手段）。

**手动二次保险**（可选，出表脚本开头/结尾）：
```r
old <- tools::md5sum("data/02_sample_meta.csv")
# ...跑分析...
stopifnot(identical(old, tools::md5sum("data/02_sample_meta.csv")))
```

**模拟列的自证纪律**：`assets/simulate_*.R` 生成的列必须在 csv 首行加 `#` 注明「模拟数据，非实测」，
并在 `data/README.md` 写明；绝不与真实列混写、绝不回写真实文件。

---

## 2.3 `05_env_simulated.csv`（可选）— 环境/协变量表

供 **42_rda**（DCA/RDA/CCA + envfit）与 **43_regression**（线性回归）作解释变量用。

| 列 | 说明 |
|---|---|
| `sample_id` | 与 `02_sample_meta.csv` 的 `sample_id` 对齐（模块会 merge） |
| 其余列 | 环境变量（数值型）。列名写进 `config$opts$env`，模块只用声明过的列 |

- **哪些列是解释变量**由 `config$opts$env` 声明（默认 `c("pH","AK","AP","AN","SOM","SMC")`）
- 单位写进 `config$table$env_units`（供 `tables.docx` 的 t6）；**没有就留 `-`，不发明**
- **没有这张表时**：42/43 优雅跳过并打提示，不影响其他模块

> ⚠️ **skill 自带的 `data/05_env_simulated.csv` 是【模拟数据，非实测】**（文件名与文件首行注释都写了）。
> 生成器 `assets/simulate_env.R`（`seed=20260101`，构造公式在脚本注释里，可复现）。
> **新论文请用实测数据**填 `assets/05_env_template.csv` 的表头，并改 `config$files$env`。

---

## 附：skill 自带的 `data/` 是示例，不是你的数据

`data/` 里的 5 个植物数据文件 + 模拟环境表**都只是模板**（封丘那套也不例外），
用来跑通示例流程。**换新论文时请整个换成你自己的数据**，并在 `config/config.R`
里把 `files$*` 指到你的 `<论文项目>/data/`。
