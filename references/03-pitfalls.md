# 03 · 踩坑库（Pitfalls）

按"症状 → 原因 → 处置"记录。**封丘数据实测发现的坑标了「实测」**，新数据遇到同类问题可直接查。

---

## A. 编码与运行环境

### A1 ｜ R 脚本里的中文路径解析失败（实测）
**症状**：`Rscript` 跑含中文路径的脚本时报 `invalid input found on input connection`，或 `file.exists()` 返回 `FALSE` 但文件明明存在。
**更隐蔽的变体（实测）**：`Rscript script.R` 直接跑一个**内含中文路径字面量**的脚本时，
`list.files("D:/.../中文目录/R")` 会**返回 0 个文件且不报任何错**（不抛异常、不 warning），
看起来像"目录是空的"。同一段代码用启动器 + `source(..., encoding="UTF-8")` 跑就正常返回 19 个。
**判定方法**：凡是"该有东西却一个都没找到、又没报错"的情况，先怀疑编码，别先怀疑数据。
**原因**：R 启动时 `LC_CTYPE=C.UTF-8` 设置失败（该 locale 在本机不存在），回落到 `C` locale；`source()` 按本地编码解析脚本文件，UTF-8 的中文被拆坏。
**处置**：**始终用 ASCII 启动器**（脚本内只含 ASCII），第一行加
```r
Sys.setlocale("LC_CTYPE", "Chinese_China.utf8")
```
再 `source(".../含中文的脚本.R", encoding = "UTF-8")`。已验证 `file.exists()` / `read.csv()` 对中文路径无问题（`system.codepage=65001`）。
**附**：`Rscript -e "含中文的命令"` 经 Git Bash 传参同样会被破坏，复杂命令一律写成 .R 文件。

### A2 ｜ `Rprofile.site` 劫持工作目录（实测）
**症状**：`getwd()` 指向 `D:/R document/doctoral thesis`，找不到数据文件。
**原因**：`D:\R-4.5.2\etc\Rprofile.site` 第 1 行有 `setwd(...)`。
**处置**：`Rscript` 一律加 `--vanilla`；先 `cd` 到项目目录再跑；脚本放项目目录内（`/tmp` 下会空输出或段错误）。

### A3 ｜ excel 列名里的引号重复
**症状**：`readxl` 报 `New names: '酢浆草' -> '酢浆草...24'`。
**原因**：表里有重名列（同一中文名对应不同物种）。
**处置**：这是**真问题不是噪音** —— 说明该列名不能作主键。改用学名主键；如确实需要中文名，必须先确认重复项。

---

## B. 物种名匹配

### B1 ｜ 树 tip 标签带尾随空格（实测）
**症状**：PD/NTI/NRI 算出的物种数少于预期，或 `picante` 报物种不匹配，但肉眼看着名字是对的。
**原因**：`fq.n&mytree.txt` 的 tip 形如 `"Helianthus_tuberosus "`（尾部有空格），与多度矩阵列名不相等。
**处置**：读树后立刻 `tr$tip.label <- normalize_species(tr$tip.label)`（trim + 空白→下划线）。

### B2 ｜ 多度矩阵列名带尾随空格（实测）
**症状**：同上；`vegdist` 能跑但物种数偏多（同名被当成两个物种）。
**原因**：`"Melilotus officinalis "`、`"Cirsium arvense var. integrifolium "` 等带尾空格。
**处置**：读入后统一 `normalize_species(colnames())`，并检查规范化后是否产生重复（产生则报错）。

### B3 ｜ 五份数据四个物种数（实测）
封丘现状：树A 150 tips / 树B 148 tips / 物种名单 194 / 性状矩阵 148 / 多度矩阵 150。
**处置**：`01_data_health.R` 强制输出四表交集/差集清单；**不要**默不作声地取交集 —— 会静默丢样本或丢物种。

### B4 ｜ 中文名重复（实测）
`酢浆草` / `金狗尾` / `茜草` / `夏至草` 各有 2 个不同物种共用。
**处置**：中文名禁止作主键。`04_species_list.csv` 里保留 `species_cn` 仅作核对。

### B5 ｜ 变种名带 `var.`
`Cirsium arvense var. integrifolium`、`Cirsium arvense var. setosum` 同一物种的不同变种。
规范化后为 `Cirsium_arvense_var._integrifolium` / `..._setosum`，**两个不同主键**，不可合并。

---

## C. 功能性数据

### C1 ｜ 多度矩阵里的 `NA` 必须转 0（实测）
**症状**：`FD::dbFD` 或 `betapart` 报错/结果异常。
**原因**：导出时空白单元格变 `NA`。原始代码注释已提醒"注意把文件空值改为0"。
**处置**：`20_fd.R` 读入后 `NA → 0`，并在日志记录替换了多少个格子。

### C2 ｜ `Spe.N` 形式的匿名行列名（实测）
`trait-FD.csv`（188×5，性状 PCA 主轴）和 `abundance-FD.csv`（101×188）用 `Spe.1…Spe.188` 代替物种名。
**处置**：必须找到 `Spe.N → 学名` 的映射表并校验；映射表缺失时**报错停止**，不要凭行序猜。

### C3 ｜ 性状表口径混杂
`05-功能性状&功能多样性` 里同时存在：原始性状矩阵(148×38)、插补后矩阵、`log10` 矩阵、性状 PCA 主轴(188×5)、PCA 简名表(148×30)。
**处置**：明确规定 `03_traits.csv` 放**哪一版**，写进 `config.R`（`traits_variant`），并在结果表里记录来源。混用会导致 FD 指数与 PCA 结果不可比。

### C4 ｜ 木本/无性状物种被删除
`备注` sheet 记录了 `new` 表删除了木本植物和无性状物种。
**处置**：物种取舍是一级决策，**必须由用户确认**，包只报告"删了哪些、剩多少"。

---

## D. 统计口径

### D1 ｜ `cld(tuk1, alpah = 0.05)` 拼写错误（实测）
`multcomp::cld()` 的参数是 `alpha`。原代码写成 `alpah`，因为默认值恰好也是 0.05 所以没出事，但**一旦想改显著性水平就会静默失效**。
**处置**：包内统一用 `alpha`，并把显著性水平写进 `config.R`。

### D2 ｜ 输出文件被覆盖（实测）
原代码把 `graph2ppt(p1, "NMDS1.pptx")` 写了两遍（两段代码块），后者覆盖前者。
**处置**：包内输出名一律带模块前缀与关键参数（如 `40_nmds_Season.pdf`），并在写入前检查同名文件。

### D3 ｜ 距离矩阵被当成 data.frame 的列（实测）
```r
beta.index <- data.frame(as.matrix(Bray), as.matrix(jaccard), as.matrix(sorensen))
```
把 180×180 距离矩阵按列展开，文件会被撑爆且无法解读。
**处置**：距离矩阵一律**单独存**（长表：`sample_i, sample_j, distance`），或存 `.rds`；绝不并入结果总表。

### D4 ｜ 正态性检验的 p 值判读方向
原代码注释写"p 要小于 0.05"表示正态 —— **写反了**，Shapiro-Wilk 是 p > 0.05 才不拒绝正态。
**处置**：包内 `01_data_health.R` 输出的诊断表里明确写 `normal_ok = (p > alpha)`，避免再次读反。

### D5 ｜ 多重比较校正方法不一致
原代码里同时出现 `bonferroni`、`BH`；ANOSIM 两两比较用 BH，而 Dunn 用 bonferroni。
**处置**：校正在 `config.R` 统一声明（默认 `BH`），结果表里记录所用方法。

### D6 ｜ 随机效应结构凭经验写死
`(1|Site)` 与 `(Season|Site)` 混用，未说明选择理由。
**处置**：`14_mixed_model.R` 提供 `random_structure` 选项（截距 / 随机斜率），并把 AIC/BIC 与收敛诊断写进结果表，让选择可核查。

---

## E. 图形与导出

### E1 ｜ `rel()` 相对字号在出版尺寸下失真
原代码大量用 `element_text(size = rel(1.2))`，图缩放到期刊物理尺寸后字号不可控。
**处置**：包内统一用 **pt 绝对字号** + 物理尺寸（默认双栏 190mm，可切单栏 90mm）。
**换算表**（论文 `theme_bw()` 隐含 base 11）：

| 论文 | 换算 | 本包 |
|---|---|---|
| `rel(1.2)` = 13.2pt（axis/legend/strip） | base_pt + 2 | 11pt（base_pt=9 时） |
| `rel(1.5)` = 16.5pt（plot.title） | base_pt + 5 | 14pt（base_pt=9 时） |

若并排比对后仍偏小，改 `config$plot$base_pt`（9→10/11），**不要把绝对 pt 写死进 `pd_theme`**。
多面板诊断图（QQ 等）用 `pd_theme(compact = TRUE)` 走紧凑字号防溢出。

### E2 ｜ 图标签语言
原代码图标签英文、注释中文；早期版本有中文图。
**处置**：默认英文（投稿用）；`config.R` 里 `plot$lang` 可切 `"zh"`（汇报用），中文需指定字体（Windows 用 `SimSun`/`Microsoft YaHei`），否则 pdf 里中文变方框。英文图字体 `plot$font_en`（Fig 5 论文用 Times New Roman）。

### E3 ｜ `export::graph2ppt` 的定位
用户已明确：**只要结果表 + pdf**，不再默认出 pptx。
`graph2ppt` 仅在需要"可编辑"时手工调用。
**本轮变化**：同类多图改为 R 内 `pd_compose()`（patchwork）合成 + `tag_levels` 打 `(a)(b)`，**不再走 PPTX 加标签**。

### E4 ｜ 论文 `expand = c(0, 0)` 会切掉 R 内加的 Tukey 字母
论文的 Tukey 字母是在 PPTX 里加的，且 `scale_y_continuous(limits=…, expand=c(0,0))` 把 y 轴顶死。
本包在 R 内写字母（更可复现），若照抄 `expand = c(0,0)` 字母会被切掉。
**处置**：`scale_y_continuous(expand = expansion(mult = c(0.05, 0.12)))` 给字母留头。

### E5 ｜ 论文 PDF 页宽含 PPTX 边距
论文 TIFF 内容 2126px ≈ 180mm，但 `Figure 3.pdf` 页宽 263mm —— 差额是 PPTX 幻灯片边距。
`config$plot$fig_size` 照抄 PDF 页尺寸会导致内容过满时，把 `fig3/fig4` 改成内容框尺寸 ≈180×125（config 一行）。

### E6 ｜ ggtree 环形树不要套 `pd_theme()`
`pd_theme()` 会注入网格线与坐标轴文字，**破坏 circular 布局**。ggtree 树图保持其自带空白主题。

### E7 ｜ 论文 Tukey 字母在 PPTX 加，本包在 R 内加
字号/位置不逐像素对齐，**风格族一致即可**。p 值来源仍须与主检验同源（不复刻原文对非正态数据用 `t.test` 的口径错误）。

### E9 ｜ 缓存纪律（模块级 .rds）
**目标**：改图样式后**秒级重出图**，不重跑检验/模拟。

**机制**：`pd_cached(stem, key, expr)` 包住**全部昂贵计算**：
`phyloCorrelogram`（**最慢 15–25 分钟**）/ `phyloSim` / `lipaMoran` / `MCMCglmm` ×变量 / `missForest` / `phylo.maker` / `ses.mntd`+`ses.mpd` / `metaMDS` / `adonis2` / 两两 PERMANOVA / 两两 ANOSIM。
**绘图总是重画** → 改 `pd_theme` / 配色 / 字号后重跑，计算走缓存、图立刻出。
`FIGURE_ONLY=TRUE` 时**额外跳过 `phyloCorrelogram`**（它不出图，跑了也是白烧时间）。

**失效键** = 数据文件 `tools::md5sum` + 影响统计的 `opts` 签名（`seed`/`runs`/`alpha_test`/`distance`/…）。
**样式参数不进键** → 改 theme/字号/配色不会触发重算（这是设计，不是 bug）。

| 开关 | 行为 | 何时用 |
|---|---|---|
| `opts$FORCE_RECALC = FALSE`（默认） | 命中缓存就用，否则算并写入 | 日常 |
| `opts$FORCE_RECALC = TRUE` | 无视缓存，重算并覆盖 | 换数据 / 换统计参数 / 怀疑缓存脏 |
| `opts$FIGURE_ONLY = TRUE` | 隐含 `FORCE_RECALC=FALSE`；分析全走缓存，只重画图 | **改样式后重出图** |

环境变量也可控（生成脚本读 `FORCE_RECALC` / `FIGURE_ONLY`）：
```bash
FORCE_RECALC=TRUE Rscript gen_all.R     # 强制重算
FIGURE_ONLY=TRUE  Rscript gen_all.R     # 只重画图
```

**缓存位置**：`paths$cache`（默认 `cache/`，与 `results/` `figures/` 平级），每模块一个 `<stem>.rds`。
**何时必须 `FORCE_RECALC=TRUE`**：换数据文件、改 `opts$runs`/`alpha_test`/`distance`/`seed` 等统计参数、升级 R/包版本后。
**缓存不可用时**（读失败）：自动重算并 `pd_warn`，不会静默给错结果。

### E8 ｜ 同类多图必须合成一张，散件不落地
**规则**：同一类型的多张图（交互图×N、Venn×N、MCMC 迹×N、phylo4d 套图、逐性状循环图）一律合成**一张**文件，不再散落几十个 PDF。

**例外（3 条）**：
1. **树图变体各自成文件** —— 写论文时挑一张，拼在一起反而没法挑
2. **论文图可裁** —— Fig3/4/5 拼成 4 面板、S3/S4 拼成 2 面板，投稿前裁开（与树同理）
3. **真冗余必消** —— 同一信息只出现一次（PCA 只画一遍；scree 归 Fig6；子集图如 `90_study_area_main` 删）

**实现分两路**：
- ggplot 集合 → `pd_compose()`（patchwork + `tag_levels="a"` 打 `(a)(b)`）
- base/grid 图形集合 → `pd_combine_pdfs()`（`pdftools::pdf_combine` 文件级合并；patchwork 收不到 grob）
  合并后按 `plot$save_singles` 决定是否删散件：`FALSE`（默认）= 只留合并图；`TRUE` = 两者都留，便于逐图检查

**base 图形合并后无 (a)(b) 标签** —— 用 `main=` 带小标题（如 `"barplot"` / 性状名）区分。

**跨模块胶水**（放 `00_setup.R`，靠 `.pd$last_*` 传对象，不硬耦合模块）：
- `pd_run_stats_panel()` → `stats_tests_panel.pdf`（ANOSIM + Venn + MCMC 混拼）
- `pd_run_diagnostics()` → `01_data_diagnostics.pdf`（QQ + impute，跨 01/21）

---

## F. 长任务纪律

- 置换检验（`adonis2`/`anosim`/`ses.mntd`）与 `phyloSim` 是耗时大户。**跑之前先给用户：替代方案 + 时间预估。**
- 测试用 `perm = 199`，正式用 `perm = 999` 或更高；两者结果表文件名要区分（`_test` / `_final`），避免误引。

---

## G. 验证阶段（封丘数据实跑）新增的坑

### G1 ｜ 学名两套体系：只有 101/150 能字面匹配（实测，**最重要**）
封丘数据里，多度矩阵/树用的是调查学名（`Aster_hispidus`、`Artemisia_lavandulifolia`、`Echinochloa_crus-galli`），
功能性状表用的是 TRY 库匹配到的学名（`Afroaster_hispidus`、`Artemisia_abrotanum`、`Echinochloa_oryzoides`）。
同一属、不同种加词 —— 典型的**性状数据库按属/近缘种匹配**留下的痕迹。
**后果**：四方物种交集只有 101 个，FD 与谱系信号只在 101 个物种上算得出来。
**处置**：`01_data_health.R` 输出 `suspect_synonyms` sheet（同属不同种加词清单），**只报告不改名**。
必须先由作者确认"这个学名是不是真的对应那个物种"，再决定是否人工统一。

### G2 ｜ 大小写异常（实测）
性状表里出现 `CAPSELLA_BURSA-PASTORIS`（全大写）。规范化时**不要**自动改大小写（属名首字母大写、种加词小写），
否则无法区分"数据录入错误"和"作者有意为之"。只报告。

### G3 ｜ 多度数据是连续重要值，不是个体计数（实测）
封丘多度矩阵的值形如 `1.75 / 0.5 / 0.42`（重要值/盖度），`vegan::rarefy()` 会报
`function accepts only integers (counts)`。
**处置**：`10_alpha.R` 先判断是否整数计数；非整数则跳过稀释并说明。
`Shannon/Simpson/Pielou` 对非整数仍可计算（vegan 按比例处理），但**必须意识到这是"重要值多样性"而非"个体多样性"**，
写文章时要讲清楚。

### G4 ｜ `multcomp::cld()` 的结果对象没有 rownames（实测）
字母在 `cl$mcletters$Letters`（`names()` 才是分组名），不是 `cl$Letters`，也不是 `rownames(cl)`。
写错会导致 `merge(..., by="cell")` 报 `'by' must specify a uniquely valid column`。

### G5 ｜ `vegan::varpart()` 只接受 2~4 个解释表（实测）
想算"单个集合单独解释量"不能只传一个表（报 `needs two to four explanatory tables`）。
**处置**：单独解释量改用 `lm(向量)` 或 `capscale(群落 ~ X, distance=)` + `RsquareAdj`；
`varpart` 只用来出 fractions / indfract（唯一量、共同量）。

### G6 ｜ `functional.betapart.core()` 要求每个群落物种数 > 性状数（实测）
封丘：群落物种数 11~34，性状 37 个 → 全部群落不满足，报一长串
`community XXX must contain at least 38 species`。
**处置**：`20_fd.R` 先算 `min(rowSums(pa))`，不满足就**跳过并给出可操作建议**（先对性状做 PCA 降维再算）。
注意 `dbFD` 的 FRic 不受此限（它内部会把性状降到"物种数−1"维）。

### G7 ｜ FD 指数与"性状输入"强绑定（实测）
同一批样方，用 37 个原始性状算出的 FRic 与原文（用 5 个性状 PCA 主轴）算出的 F.Ric：
中位数 8.8 vs 27.9，相关系数 r = 0.62。
**FDiv r=0.69、FEve r=0.61、RaoQ r=0.82** —— 方向一致但数值不可比。
**处置**：`opts$trait_input` 必须显式声明并写进结果表；跨章节比较 FD 值前先确认性状输入一致。

### G8 ｜ `V.PhyloMaker` 的 GBOTB 数据要显式载入并传参（实测）
`V.PhyloMaker::phylo.maker()` 的默认参数 `tree = GBOTB.extended` 在包命名空间里取不到，
直接调用报 `object 'GBOTB.extended' not found`。v1 的数据对象是 `GBOTB.extended` + `nodes.info.1`。
**处置**：`utils::data()` 载入到环境，然后 `phylo.maker(sp.list=, tree=, nodes=, scenarios=)` 显式传入。
（封丘实跑：v1 建树成功，149 tips，52.7 s。）

### G9 ｜ 谱系指数与"用哪棵树"强绑定（实测）
同一批样方：PD 与原文 **r = 1.0000**（135/180 差 < 1，说明口径完全一致）；
但 mntd r = 0.92、mpd r = 0.85（max|差| 152 / 263）。
**推断**：原文的 mntd/mpd 可能来自另一棵树（`fq&mytree.NNN.tre`，148 tips）或不同加权口径。
（后续已查明：原文那两列是 `obs.z` 标准化效应量，不是原始 MNTD/MPD —— 见 G12。）
**处置**：`31_pd_nti_nri.R` 把"树文件名 + tips 数 + 零模型 + 加权 + 置换次数"全部写进 `run_info` sheet。

### G10 ｜ 反复重跑会产生时间戳副本
`pd_write_table` / `pd_save_pdf` 检测到同名文件时会改存带时间戳的新文件（不静默覆盖）。
调试期会累积很多副本，**交付前记得清理 results/figures 里的历史文件**。

### G11 ｜ 物种名/分类字段里的"不可见字符"（实测，隐蔽）
`04_species_list.csv` 里 `Erysimum_cheiranthoides` 的 family 是 `\u00A0Brassicaceae`
—— 前导的是 **U+00A0 NO-BREAK SPACE（不间断空格）**，不是普通空格。
- **为什么危险**：R 的 `trimws()` 默认只认 `[ \t\r\n]`，**不认 U+00A0**。
  物种名里一旦混进它，`%in%` / `match()` 会静默失败（不报错、只是匹配不上）。
- **触发点**：`V.PhyloMaker2::phylo.maker()` 用严格字符串相等比较「属+科」与巨树，
  family 带 NBSP 时会误报 `Taxonomic classification not consistent between sp.list and tree`。
- **同类字符**：U+2000~200A（EN/EM/THIN/HAIR SPACE）、U+202F 窄 NBSP、U+205F、
  U+3000 全角空格、U+200B 零宽空格、U+FEFF BOM。
- **处置**：`normalize_species()` 已覆盖上述全部字符（零宽类删除、空格类转普通空格）；
  `pd_strip_invisible()` 用于 genus/family 等不转下划线的文本列；
  `pd_scan_invisible()` 在 `01_data_health` §(a3) 每次体检自动扫描并写入
  `01_health.xlsx` 的 `invisible_chars` sheet。**扫描 + 清理照做，但数据源该修还是要修。**

### G12 ｜ 换建树工具/情景对谱系结论的实际影响（实测）
用同一份 150 种名单、`V.PhyloMaker2`（S3）重建树，与项目现有 `99_phylo.tre` 逐样方比对：

| 对照项 | 结果 |
|---|---|
| tip 标签 | 150 / 150 **完全一致** |
| 总枝长 | 7041.5 vs 6992.5（差 0.7%） |
| Robinson-Foulds | 22 / 294 → **归一化 0.075**（拓扑近乎相同） |
| PD | r = 0.9996（相对差中位 0.015%） |
| MNTD / MPD 观测值 | r = 0.9999 / 1.0000 |
| NTI / NRI | r = 0.9922 / 0.9750 |
| 聚集·随机·发散 判读 | NTI 178/180（98.9%）、NRI 173/180（96.1%） |

**结论**：换工具对**结论层面无影响**，翻转只发生在 \|z\| 距阈值 2 不足 0.35 的边缘样方。
150 种里有 35 种（23.3%）不在巨树中、按属级拼接，这是拓扑差异的主要来源，但影响可忽略。
→ 意味着**不必长期纠结用哪棵树**；但树文件名/工具/情景仍必须写进结果表 `run_info`。


---

## H. 第二批（Diversity 2023 补齐）实测踩坑

### H1 ｜ RDA 必须 Hellinger 变换（实测口径）
**症状**：RDA 第一轴被极少数长尾物种拉满，envfit 的 R² 低得离谱。
**原因**：原始多度/重要值跨 2~3 个数量级，欧氏距离被大值主导。
**处置**：**`vegan::decostand(ab, "hellinger")` 再进 `rda()`**。CCA 对此不敏感，但 RDA 敏感。
口径必须写进 `42_rda.xlsx:run_info`（本包写 `多度变换 = Hellinger`）。

### H2 ｜ envfit 与 RDA 必须同口径（同一批样方 + 同一套解释变量）
**症状**：envfit 的 R² 之和 > RDA 的约束惯量占比，解释不通。
**原因**：envfit 拿了全数据、RDA 因缺值删行；或两边解释变量集不同。
**处置**：同一 `merge` 后的表同时喂给 `rda()` 与 `envfit()`（本包 `pd_env_join` 一次性对齐）。

### H3 ｜ `corrplot` 的两个坑（实测）
1. **`method` 没有 `"mixed"`** —— 只有 `circle/square/ellipse/number/shade/color/pie`。
   混合布局（下三角数字、上三角圆）要走 **`corrplot::corrplot.mixed(lower=, upper=)`**。
   传 `method="mixed"` → `Error in match.arg(method)`。
2. **`diag` 是字符 `"n"/"l"/"u"`，不是 TRUE/FALSE**。
   传 `diag=FALSE` → `'arg' must be NULL or a character vector`（`match.arg` 撞上逻辑值）。
   隐藏对角线用 **`diag = "n"`**。

### H4 ｜ `stat_chull` 不是 ggplot2 导出函数
**症状**：`'stat_chull' is not an exported object from 'namespace:ggplot2'`。
**处置**：手算凸包再 `geom_polygon`：
```r
hull <- do.call(rbind, lapply(split(sp, sp$grp), function(d) d[chull(d$x, d$y), ]))
geom_polygon(data = hull, aes(x, y, fill = grp), alpha = 0.10, colour = NA)
```

### H5 ｜ `pd_capture_plot` 要裸表达式，不是 function(){}
它内部 `substitute(expr)` + `eval(e, envir = parent.frame())`。
传 `function(){...}` 会 eval 出函数对象，`!is.function(obj)` 跳过绘制 → **出一张空 PDF**。
直接传 `corrplot::corrplot(...)` 这样的调用。

### H6 ｜ `config$table$vars` 是论文名，结果表是实际列名
**症状**：T3/S2/t5 里 FRic、SES.MNTD 列全 `-`。
**原因**：`table$vars` 写论文显示名（`FRic` / `SES.MNTD`），而 meta 与 `12_*:summary` 里是
`F.Ric` / `mntd` —— 直接 `==` 匹配取不到值。
**处置**：`pd_table_vars()` 走 `pd_match_var` 做别名解析，**查找用实际名、表头用显示名**。

### H7 ｜ `pd_run_tests` 的 `vars` 决定 `12_*.xlsx` 有什么（已放宽默认，2026-09-25）
**症状**：`12_anova_tukey.xlsx:summary` 里没有 FRic/PD/mntd → T3/S2/t8 相应列空、报「无源」。
**原默认**（易踩）：`vars = c(response$alpha, response$community)` —— 漏掉 func/phylo。
**现默认**（2026-09-25 起）：`response` 的**全部四组**（alpha/func/phylo/community）。
```r
pd_run_tests(CONFIG, dat)          # 现在默认就测全响应组，T3/S2/t8 有源
pd_run_tests(CONFIG, dat, vars = c("Shannon","PD"))   # 也可显式指定
```
若用旧版本脚本显式传了 `vars`，仍以传入为准。

### H8 ｜ `list()` 末项尾逗号 = 空参，`parse()` 不报错但 `eval` 炸
**症状**：`Error in list(...) : argument 60 is empty`，但 `parse()` 通过。
**原因**：R 的 `list()` 不允许 trailing comma（Python 允许）。
**处置**：删末项尾逗号。排查用 `as.list(parse(f)[[1]])` 逐元素看。

### H9 ｜ `read.csv` 默认不跳 `#` 注释
**症状**：带 `#` 说明行的 CSV（如 `05_env_simulated.csv` 的「模拟数据」自证块）被当数据读进来。
**处置**：`pd_read_table` 已自动检测首行 `#` 并设 `comment.char = "#"`。自写脚本请手动加。

### H10 ｜ R 的交互项名是 `:` 不是 `*`（实测，会让表静默缺行）
**症状**：`permanova_model="interaction"` / `include_interaction=TRUE` 都开了，
但 `tables.docx` 的 Table 2 只有 Season / Habitat / Residual —— **交互行不见了**；
Table 3 的交互行 F、p 全是 `-`。
**原因**：`adonis2()` 与 `summary(aov())` 的 term 名是 **`Habitat:Season`（冒号）**，
而取值代码写的是 `grep("\*", trm)` / `term == "Season * Habitat"`（星号）→ 永不匹配。
**处置**：查找时同时收 `:` 与 `*`：
```r
grep("[*:]", trm)                       # T2 找交互行
inter_terms <- c("Season * Habitat", "Habitat * Season",
                 "Season:Habitat", "Habitat:Season")   # T3 的 pick
```
显示名另做规范化（`:` 形 → 论文的 `Season * Habitat`）。
**判定方法**：表里该有的行/列全是 `-`，但源 xlsx 里确实算出来了 —— 先怀疑 **term 名形不匹配**，别先怀疑算错。

### H11 ｜ RDA 得分三套口径别混（实测；vegan ≥2.6 的 `summary()` 不返回得分）
**症状**：按老代码写 `summary(mod)$biplot` / `$sites` / `$species` → 全是 `NULL`，
表里的 RDA1/RDA2 全 `NA`，图上物种点不出现。
**原因**：vegan 2.6 起 `summary.cca()` 只返回 `call/tot.chi/cont/...`，
**不再返回 `sites`/`species`/`biplot`** —— 要改用 `vegan::scores()`。
**三套得分（各派各用场，别互换）**：
| 来源 | 长度 | 用途 |
|---|---|---|
| `vegan::scores(mod, display="bp")` ≡ `mod$CCA$biplot` | ∝ 拟合优度（平方和 ≠ 1） | **图上箭头**（原文 `ii$biplot`） |
| `ef$vectors$arrows`（envfit） | **单位长度**（平方和 = 1） | **表 7-1 的 RDA1/RDA2**（论文核对：pH `(-0.07964, -0.99682)` 平方和=1） |
| `vegan::scores(mod, display="species"/"sites")` | 视 scaling | 物种点 / 样方点 |
**处置**：
```r
bp  <- vegan::scores(mod, display = "bp", choices = 1:2)      # 图箭头
sp  <- vegan::scores(mod, display = "species", choices = 1:2) # 物种点（可 ×rda_sp_scale）
st  <- vegan::scores(mod, display = "sites",   choices = 1:2) # 样方点
tbl <- ef$vectors$arrows[, 1:2]                                # 表 7-1 的方向余弦
```
**顺带**：论文表 7-1 的 p 写 `0.000 ***`，skill 的 `pd_fmt_p("lt001")` 出 `<0.001 ***` —— **保持 skill 口径**，不照抄 `0.000`。

**生物含义别画错（用户 2026-09-25 纠正）**：
- **物种 = 点**（粉方块 `#F37A70`），**不画箭头**；**环境因子才画箭头**（`#3182BD`）
- **物种名只在种数少时标**（`plot$rda_sp_label_max`，默认 30）—— 硕士论文 47 种标了；
  skill 示例上百种若也标名会糊成一团，**只画点不标名**
- **样方点与物种点一般是二选一**（用户 2026-09-25 拍板）：样方多时物种点会糊成一团。
  `plot$rda_biplot_show = "sites" | "species" | "both"`；`"both"` 仅样方<40 且物种<30 才采纳，
  否则自动降级回 `"sites"`。**做之前和别的分析问题一起问用户，不代选。**

**轴解释率分母别写错（实测）**：
- 原文 `var_exp <- eig[1:2] / tot.chi * 100` —— 占**总惯量**
- 写成 `eig / sum(eig)`（占约束部分）会把 1.7% 显示成 37.9%，虚高 20 倍

**`permutest` 的 p 取不到（实测）**：
`as.data.frame(pt$tab)` 默认 `check.names=TRUE` 会把 `Pr(>F)` 改名成 `Pr..F..` → `"Pr(>F)" %in% names()` 恒 FALSE，副标题的 p 静默缺失。
→ 加 `check.names = FALSE`，或用 `grep("^Pr", names(tb))` 兜底。

---

## I. 第三批（Plant and Soil 投稿版吸收）实测踩坑

### H12 ｜ 箱线图显著性标注：>4 组必须用字母，≤4 组才用括号（用户 2026-09-25 规则）
**用户原话**：「以后像这种大于 4 个分组的，统一标注显著性字母，而不是括号。4 个以内的可以考虑用这种括号显示」
**规则**：
| x 轴组数 | 标注方式 | 理由 |
|---|---|---|
| **> 4** | **显著性字母（CLD）** | 6 组两两全比 = 15 条括号，挤成一团看不清 |
| **≤ 4** | 括号（可接受/推荐） | 3–4 组只有 3–6 条括号，可读 |
**实现**：`opts$sig_label = NULL`（默认）→ 按分组数自动选；显式写了就尊重用户、不自动。
`R/60_plots.R` 的 `pd_run_plots_one` 里判定，日志会说明原因。

**★ 双因素一律 letters**：x 轴是 `f1×f2` 组合（`pd_boxplot_combo`），括号模式只在 f1 水平间比较
（`pd_boxplot_bracket`）—— 硬选 bracket 会把 combo 横轴降级成 f1 横轴，**版式不能因标注而变**。

**★ 论文原做法不吸收**（同类分析以 skill 为准）：
Plant and Soil 稿的箱线图是 `ggpubr::stat_compare_means(method="t.test", label="p.format", hide.ns=TRUE)`
+ 只比 CK vs 其他 5 对 + 总检验 Kruskal。三样都**不进 skill**：
- `p.format` 精确 p → skill 用字母/星号
- `t.test` 两两 → 与主检验口径矛盾（`anova_tukey` 应配 Tukey HSD），skill 已弃用
- 「只比对照」→ skill 用两两全比 `combn(lv, 2)`
（另注：论文自己也不一致 —— 代码写 `hide.ns=TRUE` 但成图上 0.2/0.98 等不显著值照样显示。）

### H13 ｜ `60_plots` 的「补跑 Tukey 字母」会覆盖 `12_<method>.xlsx`（踩过两次，已修）
**症状**：T3/S2/t8 报「FRic/PD/SES.MNTD 在 `12_*:summary` 里没有」，
但明明刚跑过 `pd_run_tests` 全响应变量 —— 打开 `results/` 发现 `12_anova_tukey.xlsx` 只剩 4 个变量。
**根因**（两个叠加）：
1. `60_plots` 出论文图时若缺字母会补跑 `pd_run_tests(vars = got_vars)`，
   而 `pd_run_tests` 默认 `stem = method` → **写回 `12_anova_tukey.xlsx`，把规范表覆盖成子集**。
2. 判断「已有哪些字母」用了 `tests$letters` —— **那个表没有 `variable` 列**（只有 `cells` 有），
   → `have_lt` 恒为空 → **补跑每次都触发**，白跑且必然覆盖。
**处置**（2026-09-25 已修，两处都要改）：
```r
# ① pd_run_tests 加 stem 参数；补跑用独立 stem
pd_run_tests(..., vars = got_vars, stem = paste0(method, "_letters"))
# ② have_lt 从 tests$cells 取（同 letters_all 的口径），别用 tests$letters
have_lt <- if (!is.null(letters_all) && nrow(letters_all) && "variable" %in% names(letters_all))
             unique(as.character(letters_all$variable)) else character(0)
```
**教训**：任何「补跑/顺带跑」都不许写规范结果文件 —— 要么 `save=FALSE`，要么换 stem。
规范文件名只由**用户显式调用**的那个入口写。

### H14 ｜ 响应指数算完在 `results/`，不回填就永远进不了响应集（已加 `pd_enrich_meta`）
**症状**：把 `Simpson`/`NTI`/`NRI` 写进 `config$response`，但 12/52/60/43 里它们全都缺席。
**根因**：`pd_load_data` 只读 `data/02_sample_meta.csv`，而 10/20/31 是算完写 `results/*.xlsx` 的，
**不回填** → meta 里没这几列 → `vars %in% names(dat$meta)` 全被滤掉。
而 `02_sample_meta.csv` 是封丘真实植物数据（**有 md5 校验，绝不许改写**），不能直接加列。
**处置**：`pd_enrich_meta()`（`R/00_setup.R`）—— 按 `sample_id` 从 `results/*.xlsx` 把缺的响应列并进 meta，
**只并内存、绝不写回 CSV**。`opts$enrich_meta = FALSE` 可关掉。
```log
[data] meta 缺列 Simpson ← 10_indices.xlsx:result（按 sample_id 对齐）
[data] meta 缺列 NTI     ← 31_runs999_final.xlsx:pd_nti_nri（按 sample_id 对齐）
```
**安全阀**：`row_id` 之类的假 key 必须真的对得上 `sample_id` 才并（`if (!any(idv %in% key)) next`）。

---

## J. 第四批（skill 优化审查）实测踩坑 —— 2026-09-25

> 本轮用 skill-optimizer + 三路科学性审查查出 74 条问题，下列是**已实测复核**并修掉的坑。
> 每条都标了「实测证据」，不是推测。

### I1 ｜ `multcomp::cld` 的 `level` 是【显著性水平】，不是置信水平 🔴 最严重
**症状**：Tukey 字母**过度拆分**，把无差异的组标成不同字母 —— 凭空造出不存在的显著差异。
**根因**：`cld(tk, level = 1 - alpha)`。multcomp 源码：
```r
function (object, level = 0.05, decreasing = FALSE, ...)
    signif <- (object$test$pvalues < level)      # level 就是显著性水平
```
默认 `level = 0.05`；传 `1 - 0.05 = 0.95` 让几乎所有比较都"显著"。
**实测**：三组 p = 0.93 / 0.98 / 0.98（真实无差异）
| 传入 | 字母 |
|---|---|
| `level = 0.05` | `A=a  B=a  C=a` ✅ |
| `level = 0.95` | `A=b  B=a  C=ab` ❌ |
**处置**：`cld(tk, level = alpha, ...)`。
**影响面**：12 的字母列 → T3/s2/t8 表、所有箱线图字母。
**别踩**：`multcomp` 的 `level` 与 `confint` 的 `level`（置信水平）**语义相反**，同名不同义。

### I2 ｜ `dunn.test` 默认给单侧半 p，且 `altp=TRUE` 时槽位改名
**症状**：Dunn 显著性虚高（等效双侧 α=0.10）。
**根因**：`dunn.test(..., altp = FALSE)` 返回 `p = Pr(Z >= |z|)`，包自己打印
**`"Reject Ho if p ≤ FDR/2"`** —— 拿它跟 α=0.05 判星就等于双侧 α=0.10。
**实测**：同数据 altp=FALSE 得 0.0009，altp=TRUE 得 0.0018（正好 2 倍）。
**⚠️ 二次坑**：`altp = TRUE` 时返回槽位**改名**：
| altp | 槽位 |
|---|---|
| `FALSE` | `P` / `P.adjusted` |
| `TRUE` | **`altP` / `altP.adjusted`** |
旧代码取 `d$P.adjusted` 会得到 `NULL` → 报 "non-numeric argument"。
**处置**：`dunn.test(..., altp = TRUE)`，取值用 `d$altP.adjusted %||% d$P.adjusted`。

### I3 ｜ `rcompanion::nemenyiTest` 不存在 → SRH 的事后比较永远跑不出来
**症状**：「SRH + Nemenyi」路线看着有事后比较，实际永远是空的。
**根因**：该函数**不在 rcompanion 导出表**（实测 `getNamespaceExports("rcompanion")` 里没有，
含 nemenyi 的导出为空），调用必报错被 `tryCatch` 吞掉只留警告。
**处置**：优先 `PMCMRplus::kwAllPairsNemenyiTest`；都没有就**明确降级并警告**
（「SRH 只出主效应、无事后比较」），**不再静默**。
**教训**：`tryCatch(..., error = function(e) NULL)` 吞掉错误时，一定要 `pd_warn` 说清降级了什么。

### I4 ｜ `glmm.hp` 返回元素名与列名都和预期不符 → R² 分解永远静默失败
**症状**：`r2_decomposition` 表恒空。
**根因**：glmm.hp 1.0.0 返回元素是 `hierarchical.partitioning`，不是 `h.part`：
```
names(h) = r.squaredGLMM | hierarchical.partitioning | variables | type
```
`h$h.part` 为 NULL → "undefined columns selected" → 被 tryCatch 吞。
**二次坑**：`as.data.frame(h)[, 1]` 取到的是 **`Unique`** 列，不是 `Individual`。
列名实为 `Unique | Average.share | Individual | I.perc(%)`。
**处置**：按**列名**取 `Individual`，标签写明是「对**边际 R²** 的独立贡献」。

### I5 ｜ `anova(lmerTest)` 无 Residuals 行 → `eta2` 不是 eta²
**症状**：效应量列恒加和为 1，系统性高估。
**根因**：`anova(lmer())` 的行名只有固定效应（实测 `g`），**没有 Residuals**。
`eta = SS / sum(SS)` 的分母只有固定效应 SS 之和 → 既非 η² 也非 partial η²。
**实测**：SS 比例加和 = 1。
**处置**：partial η² = `SS / (SS + SS_resid)`，`SS_resid = sigma(m)^2 * (n - rank(X))`；
算不出就如实降级为 `ss_share_fixed`（**别再叫 eta2**）。

### I6 ｜ MCMCglmm 不接受 lme4 的 `(1|Site)` 语法
**症状**：照文档配 `random = "~ Habitat + (1|Site)"` → **`"invalid substring arguments"`**，整模块跑不通。
**根因**：MCMCglmm 用的是自己的公式语法：
| 意图 | MCMCglmm 写法 | lme4 写法 |
|---|---|---|
| 随机截距 | `~ Site` | `(1|Site)` |
| Site 下随机斜率 | `~ us(Habitat):Site` | `(Habitat|Site)` |
| 截距 + 斜率 | `~ Site + us(Habitat):Site` | `(1|Site) + (Habitat|Site)` |
**顺带**：`(1|Site)` 本来就**只是随机截距**，不是"随机斜率"（注释写错了）。
**处置**：示例改合法式；`pd_mcmc_n_raneff` 检测到 `|` 就报警。

### I7 ｜ 时间自相关检测了但下游不消费
**症状**：15 模块跑出 DW 检验 + 一阶差分列，但 12/14/43/52 **无一使用**，检测结果不影响任何推断。
**处置**：对检出变量补 **`nlme::lme(..., correlation = corAR1())` 对照**（`p_corAR1` vs `p_noAR1` + AIC）；
缺 nlme 就明确警告「尚未被下游消费」。**原有输出保留不动**。

### I8 ｜ 随机结构双入口容易悄悄分叉
**症状**：14 读 `opts$random_structure`，15/16 读 `design$random` —— 两个独立键，改一个忘另一个，
模块间随机结构不一致。
**处置**：`opts$random_structure` 为**唯一公式入口**；`NULL` 时按 `design$sampling` + `design$random` 推导。

### I9 ｜ `alpha_test = "auto"` 不自动
**症状**：写 "auto" 无条件落 `anova_tukey`；`pd_run_tests` 的 `health` 形参**全函数未用**；
01 算出的 Shapiro/Bartlett/Levene 结论没人消费 → 前提不满足也不降级。
**处置**：新增 `pd_pick_test_method()`，按【残差正态 + 组间方差齐】选参/非参族；health 有就优先消费。

### I10 ｜ `strata` 参数名误导（它不是受限置换）
**症状**：`pd_pairwise_anosim/permunova` 的 `strata` 看着像 vegan 的受限置换，实际**只是把数据切成子集**。
**处置**：加别名 `subset_by`，注释写明「不是受限置换」。
**真正的受限置换**：`opts$restrict_perm` → `permute::how(blocks = ...)`（见 `pd_perm_ctrl`）。
**取舍**：自由置换是生态学主流，**默认不改**；实测 E2 本示例数据自由 vs 受限 0 翻转（效应太强、p 触底）。

### I11 ｜ FRic 的 S > T 约束只事后告警
**症状**：性状多（如 37 个）时多数样方 FRic = NA，结果表大面积缺失 —— 算完才告警，来不及。
**处置**：**事前预检** `min(nsp) > ncol(tr)`；不满足自动把 `dbFD(m=)` 降到 `min(nsp)-1`，并提示减性状。

### I12 ｜ PERMANOVA 显著可能是离散度差异，不查 betadisper 分不清
**处置**：PERMANOVA 前补 `vegan::betadisper` + `permutest`，结果进 `40_ordination.xlsx`；
显著时警告「可能来自离散度差异而非位置差异」。

### I13 ｜ 主检验是 lmm 时，括号 p 却来自 aov
**症状**：`pd_pairwise_p` 对 `lmm` 也走 `aov(y ~ g) + glht` —— 忽略随机结构，
与「括号 p 必须与主检验同源」自相矛盾。
**处置**：lmm 路线改用 `emmeans::emmeans(... ) |> pairs()` 拟合同一混合模型。

### I14 ｜ DCA 梯度长度算法不是业界标准
**症状**：可能**错选 RDA/CCA**（4.2 SD 的梯度可能量出 2 出头）。
**根因**：旧写法逐条抄别人代码 `max(dca$rproj[, 1:4])` —— 取 4 轴最大值、**不减 min**。
业界标准（ter Braak / Lepš & Šmilauer / Canoco）= **第 1 轴物种得分的极差（max−min，SD 单位）**。
**二次坑**：DCA 跑在 **Hellinger 后**的矩阵上，而 3/4 SD 阈值是按未变换标定的，会压缩梯度。
**处置**：`range(scores(dca, display="species", choices=1))` + DCA 用**未 Hellinger** 多度。
`opts$dca_gradient = "range1" | "legacy_max4"`（后者可复现旧口径）。

### I15 ｜ `metaMDS(autotransform=TRUE)` 静默标准化，与检验不同口径
**根因**：vegan 源码 `metaMDSdist`：`autotransform=TRUE` 时 max>50 自动开方、max>9 自动 **Wisconsin 双标准化**，全程静默。
而 PERMANOVA/ANOSIM 用的是**原始矩阵**的距离 → **NMDS 图与检验表不同口径**，解释会打架。
**处置**：默认 `autotransform = FALSE`（`opts$mds_autotransform`）；为 TRUE 时打日志提示口径不一致。

### I16 ｜ `vegdist("jaccard")` 默认是定量 Jaccard
**根因**：不传 `binary=TRUE` 时给的是 **Ružička 定量 Jaccard**，与常写的定性 Jaccard 数值不同
（实测两口径最大差 0.48）。
**处置**：`opts$jaccard_binary = TRUE`（默认）→ `binary = TRUE`；Methods 需写明口径。

### I17–I19 ｜ 三处多检验零校正
| 位置 | 检验族 | 处置 |
|---|---|---|
| I17 `52_spearman` | k(k−1)/2 个相关 | 上三角 `p.adjust(,"BH")` 再进 t5 星表（`opts$spearman_p_adjust`） |
| I18 `43_regression` | y×env 几十个 lm | `p.adjust` 后再判星；**且按 R² 挑 top-4 画图 = 胜者诅咒**，故保留 `sig_raw` 供对照（`opts$reg_p_adjust`） |
| I19 `32_phylo_signal` | 5 统计量 × N 性状 | 按**每个统计量一族** BH 校正（`opts$signal_p_adjust`） |

### I20 ｜ `stats::anova(aov)` 是 Type I 顺序平方和
**症状**：不平衡设计下 F/p/eta² 随公式项序变化。
**处置**：`opts$anova_type = "III"`（默认）→ `car::Anova(type=3)` + `contr.sum` 对比；
`"I"` = 旧口径可复现。

### I21–I22 ｜ 口径必须写进 run_info，别靠记
Simpson = **1−D（Gini-Simpson）**，不是 D 也不是 1/D ｜ Pielou = H'/lnS ｜
`N_total = rowSums` 在重要值数据下**不是个体数** ｜ PD 是 Faith's PD 且 `include.root=TRUE` ｜
`mntd.obs.p` 是**单尾秩 p** ｜ NTI = −ses.mntd 的 z ｜ `abundance_weighted=TRUE` + 多度是 IV →
**IV 加权版，与文献 PA 版不可比**。
**处置**：10 / 31 的 `run_info` sheet 全部写明。

### I23–I25 ｜ 其他实现坑
| # | 坑 | 处置 |
|---|---|---|
| I23 | V.PhyloMaker2 的 **S3** 无文献依据、骨架树静默选 TPL | run_info 记 scenario + 引 Jin & Qian (2019) |
| I24 | `phyloSignal(method="1")` 靠**部分匹配** `methods`；`reps` 吃默认 | 显式传 `methods="all", reps=` |
| I25 | MCMCglmm 先验每项一律 `diag(1)`，多维项维度不够 | 按项解析：`~X`→1 维、`~us(F):G`→`nlevels(F)` 维 |

### I26 ｜ `mntd/mpd` 到底是 SES 还是原始值，无校验
**症状**：config 用 `mntd/mpd`，`table$vars` 用 `SES.MNTD`，靠别名映射；
若数据放的是**原始 MNTD**，会被当 SES 标注。
**处置**：`pd_load_data` 校验 SES 类列应「均值≈0、sd 在合理范围」，不像就报警。

### I27 ｜ `pd_write_matrix` 无覆盖护栏
**症状**：距离矩阵重跑被静默覆盖，与 pitfalls D2「不静默覆盖」自相矛盾
（`pd_write_table` / `pd_save_pdf` 都有时间戳副本机制，唯独它没有）。
**处置**：补同名护栏对齐。
