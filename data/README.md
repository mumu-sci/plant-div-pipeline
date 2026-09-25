# data/ — 示例数据（模板，不可用于论文）

**这个目录里的所有文件都是示例/模板，用于跑通 plant-div-pipeline 的示例流程，都不能直接进论文。**

| 文件 | 来源 | 说明 |
|---|---|---|
| `01_abundance.csv` | 封丘样方数据 | 样方 × 物种 多度/重要值矩阵（首列 `sample_id`） |
| `02_sample_meta.csv` | 同上 + **模拟列** | 样方元数据 + 分组因子（`Site`/`Habitat`/`Season`）+ 多样性指数（前 15 列真实）+ **Height/Coverage/Density（⚠️ 后 3 列模拟）** |
| `03_traits.csv` | TRY 匹配的性状表 | 物种 × 性状（首列 `species`） |
| `04_species_list.csv` | 物种名录 | `species / genus / family / species_cn` |
| `99_phylo.tre` | Newick 树 | tip = 学名主键 |
| **`05_env_simulated.csv`** | **模拟生成** | **⚠️ 环境数据是【模拟的，非实测】**，只用于跑通 `42_rda` / `43_regression` |

## 关于 `02_sample_meta.csv` 的后 3 列（Height / Coverage / Density）

- **SIMULATED, NOT MEASURED** —— 不是实测株高/盖度/密度
- 生成器：`assets/simulate_community.R`（`seed = 20260101`，构造公式写在该脚本注释里，可复现）
- **原有 15 列（封丘真实数据）未被改写**；只在末尾追加这 3 列
- 文件首行有 `#` 注释标明（`pd_read_table` 自动跳过）
- 用途：让 `12/52/60/43` 能吃 `response$community` 这组响应变量
- 新论文请换成实测的株高/盖度/密度

## 关于 `05_env_simulated.csv`

- **SIMULATED, NOT MEASURED** —— 不是实测土壤数据
- 生成器：`assets/simulate_env.R`（`seed = 20260101`，构造公式写在该脚本注释里，可复现）
- 变量量级参照已发表论文的土壤实测范围，但**数值是构造出来的**
- 文件首行也有同样的 `#` 注释说明

## 新论文怎么用

1. 复制本目录的文件名结构到你的 `<论文项目>/data/`
2. 换成你自己的实测数据（五文件契约见 `references/00-data-contract.md`）
3. 环境数据用实测值填 `assets/05_env_template.csv` 的表头
4. 群落结构变量（株高/盖度/密度）用实测值填 meta 的 `Height/Coverage/Density` 列
5. 改 `config/config.R` 的 `files$*` 指到你的数据
