# Data Processing and Data Dictionary

This document records how the analysis dataset is built from raw NHANES files, and what every column in it means. It reflects the state of the scripts as of September 2026.

---

## 1. Overview

| Step | Script | Input | Output |
|---|---|---|---|
| 1 | `R/01_download.R` | CDC NHANES website | 8 raw files in `data/raw/` |
| 1b | `R/01b_variable_inventory.R` | `data/raw/*.rds` | `output/variable_inventory.csv` |
| 2 | `R/02_clean_merge.R` | `data/raw/*.rds` | `data/processed/merged_full.rds` and `data/processed/analysis.rds` |
| 3 | `R/03_exclusions.R` | `data/processed/analysis.rds` | `data/processed/analytic_sample.rds` and `output/exclusion_flow.csv` |

- **Survey cycle:** NHANES August 2021 – August 2023 (file suffix `_L`)
- **Analysis dataset (`analysis.rds`):** 7,199 rows (one per person with a liver elastography record) × 55 columns
- **People with a usable CAP value:** 6,699
- **Analytic sample (`analytic_sample.rds`):** 5,227 participants after exclusions (see section 7)

Data files are not stored on GitHub. Running the scripts in order rebuilds everything.

---

## 2. Step 1: Downloading the raw data

`R/01_download.R` downloads ten NHANES tables with the `nhanesA` package and saves each as an `.rds` file.

| File | Contents | Rows | Who is included |
|---|---|---|---|
| `DEMO_L` | Demographics, survey design variables, weights | 11,933 | Everyone enrolled in the cycle |
| `BMX_L` | Body measures | 8,860 | Everyone who attended the exam |
| `DR1TOT_L` | Day-1 dietary recall totals | 8,860 | Everyone who attended the exam |
| `HDL_L` | HDL cholesterol | 8,068 | Exam participants with a blood draw |
| `LUX_L` | Liver elastography (CAP, liver stiffness) | 7,199 | Exam participants aged 12+ |
| `BIOPRO_L` | Standard biochemistry profile | 7,199 | Exam participants aged 12+ |
| `ALQ_L` | Alcohol use questionnaire | 6,337 | Adults 18+ |
| `TRIGLY_L` | Fasting triglycerides and LDL | 3,996 | Morning fasting subsample only |
| `HEPBD_L` | Hepatitis B core antibody and surface antigen | [n] | Exam participants aged 6+ |
| `HEPC_L` | Hepatitis C antibody and RNA | [n] | Exam participants aged 6+ |

**Decisions made in this step:**

- **Numeric codes, not text labels** (`translated = FALSE`). Values stay as NHANES codes (e.g. `1`/`2` for sex; `777`/`999` for "refused"/"don't know"). This makes missing-value codes visible so they can be handled explicitly in step 2.
- **`.rds` format** keeps column types and variable labels.
- **Rerunnable:** files that already exist are skipped, and a failed download produces a warning without stopping the script.
- **Provenance:** `data/raw/download_log.txt` records the download date, `nhanesA` version, and R version.

---

## 3. Step 1b: Variable inventory

`R/01b_variable_inventory.R` lists every variable in the eight raw files with its label, type, number and percentage missing, and number of unique values. The result is saved as `output/variable_inventory.csv`, which serves as the full dictionary of the raw data.

Some CDC labels are Latin-1 encoded (e.g. "µg/dL"). The script converts only the labels that are not valid UTF-8 before writing the CSV as UTF-8.

---

## 4. Step 2: Merging and cleaning

`R/02_clean_merge.R` does four things.

### 4.1 Check the join key

Every table uses `SEQN` (respondent sequence number) as the participant ID. The script stops if any table has a duplicated `SEQN`.

### 4.2 Merge

- **The spine is `LUX_L`.** The outcome (CAP) comes from the liver scan, so the dataset should contain everyone with a scan record: no more, no fewer.
- **All other tables are attached with `left_join()`** on `SEQN`. A left join keeps every row of the spine. People missing from another table get `NA` for that table's columns instead of being dropped.
- **Why not `inner_join()`:** an inner join keeps only people present in *every* table. The fasting triglyceride table alone would cap the sample at 3,996 and throw away over half of the CAP data.
- **Column clash fixed:** `WTPH2YR` (blood-draw weight) appears in both `BIOPRO_L` and `HDL_L`. It is removed from `HDL_L` before joining so there is only one copy.
- **Check:** the script confirms the merged data still has exactly 7,199 rows, and warns if any `.x`/`.y` duplicate columns appear.

The full merge (7,199 rows × 295 columns) is saved as `data/processed/merged_full.rds`, so any variable not selected below can still be retrieved later.

### 4.3 Select and rename

52 variables are selected from the full merge and given readable names (see the data dictionary in section 5).

**Not selected:**

- SI-unit duplicates (mmol/L versions of mg/dL variables)
- Lab comment codes
- Fish/shellfish items
- Individual vitamins, minerals, and fatty acids
- The binge-drinking detail questions ALQ170/270/280 (about 63% missing)

**Triglycerides:** the main variable is the **non-fasting** value from the biochemistry profile (`trig`, available for most of the sample). The **fasting** value (`trig_fast`) exists only for the fasting subsample and is kept for sensitivity analyses.

### 4.4 Recode

**NHANES missing-value codes → `NA`** (all codes verified against the CDC codebooks):

| Variables | Codes set to `NA` | Meaning |
|---|---|---|
| `alq_ever`, `alq_daily_hist`, `educ` | 7, 9 | Refused, don't know |
| `alq_freq`, `alq_heavy_days` | 77, 99 | Refused, don't know |
| `alq_drinks` | 777, 999 | Refused, don't know |

**Alcohol skip pattern → zeros.** The questionnaire skips follow-up questions for people who don't drink:

- `alq_ever = 2` (never had a drink) → skipped to the end of the section
- `alq_freq = 0` (didn't drink in the past year) → skipped drinks-per-day and heavy-drinking questions

These people drank zero, so the skipped values are set to `0`, not left as `NA`. Otherwise every non-drinker would be dropped from alcohol models.

**Backwards-coded frequency variables → real quantities.** `alq_freq` and `alq_heavy_days` are coded 0 = never, 1 = every day, … 10 = 1–2 times a year. The numbers are not a scale and must not be used as numeric predictors. They are converted to approximate days per year:

| Code | Category | Days/year used |
|---|---|---|
| 0 | Never in the last year | 0 |
| 1 | Every day | 365 |
| 2 | Nearly every day | 286 |
| 3 | 3 to 4 times a week | 182 |
| 4 | 2 times a week | 104 |
| 5 | Once a week | 52 |
| 6 | 2 to 3 times a month | 30 |
| 7 | Once a month | 12 |
| 8 | 7 to 11 times in the last year | 9 |
| 9 | 3 to 6 times in the last year | 4.5 |
| 10 | 1 to 2 times in the last year | 1.5 |

These are chosen midpoints. Other reasonable values would change individual numbers slightly, but not the ranking of drinkers.

**Unreliable dietary recalls → `NA`.** All dietary variables (`kcal` through `alcohol_g`) are set to `NA` unless `diet_status = 1` (reliable recall).

**Sex** is converted to a factor (`Male`, `Female`).

---

## 5. Data dictionary: `data/processed/analysis.rds`

"Who has it" describes who was eligible for the measurement. Anyone outside that group is `NA`.

### Identifiers and survey design

| Column | NHANES variable | Description | Who has it |
|---|---|---|---|
| `id` | SEQN | Respondent sequence number (participant ID) | Everyone |
| `psu` | SDMVPSU | Masked variance pseudo-PSU (survey design) | Everyone |
| `strata` | SDMVSTRA | Masked variance pseudo-stratum (survey design) | Everyone |
| `wt_mec` | WTMEC2YR | 2-year exam (MEC) weight | Everyone |
| `wt_phleb` | WTPH2YR | 2-year blood-draw weight | Blood-draw participants |
| `wt_fast` | WTSAF2YR | 2-year fasting subsample weight | Fasting subsample |
| `wt_diet` | WTDRD1 | Day-1 dietary recall weight | Dietary recall participants |

**Weights rule of thumb:** use the weight for the smallest subsample that any variable in the model comes from. Examples:

- Exam-only model (CAP, BMI, age) → `wt_mec`
- Model with any blood value → `wt_phleb`
- Model with `trig_fast` or `ldl` → `wt_fast`
- Model with dietary variables → `wt_diet`

### Demographics

| Column | NHANES variable | Description | Values | Who has it |
|---|---|---|---|---|
| `sex` | RIAGENDR | Sex | Factor: Male, Female | Everyone |
| `age` | RIDAGEYR | Age at screening (years) | Numeric | Everyone |
| `race_eth` | RIDRETH3 | Race/Hispanic origin | Numeric codes; see `nhanesCodebook("DEMO_L", "RIDRETH3")` | Everyone |
| `educ` | DMDEDUC2 | Highest education level | 1 = Less than 9th grade, 2 = 9–11th grade, 3 = High school/GED, 4 = Some college/AA, 5 = College graduate or above | Adults 20+ |
| `pir` | INDFMPIR | Ratio of family income to poverty | Numeric; see codebook for top-coding | Most participants |
| `preg` | RIDEXPRG | Pregnancy status at exam | 1 = Pregnant, 2 = Not pregnant, 3 = Cannot ascertain | Females 20–44 |

### Liver elastography (outcome)

| Column | NHANES variable | Description | Units / values | Who has it |
|---|---|---|---|---|
| `scan_status` | LUAXSTAT | Elastography exam status | 1 = Complete (6,280), 2 = Partial (514), 3 = Ineligible (201), 4 = Not done (204) | Everyone |
| `n_valid` | LUANMVGP | Number of complete measurements from final wand | Count | Scanned participants |
| `cap` | LUXCAPM | **Median CAP (liver fat)** — main outcome | dB/m | 6,699 participants |
| `cap_iqr` | LUXCPIQR | CAP interquartile range (measurement variability) | dB/m | Scanned participants |
| `stiffness` | LUXSMED | Median liver stiffness (fibrosis indicator) | kPa | Scanned participants |
| `stiff_iqr_ratio` | LUXSIQRM | Stiffness IQR / median (measurement reliability) | Ratio | Scanned participants |

### Body measures

| Column | NHANES variable | Description | Units | Who has it |
|---|---|---|---|---|
| `bmi` | BMXBMI | Body mass index | kg/m² | Exam participants |
| `waist` | BMXWAIST | Waist circumference | cm | Exam participants |

### Biochemistry (non-fasting blood)

| Column | NHANES variable | Description | Units | Who has it |
|---|---|---|---|---|
| `alt` | LBXSATSI | Alanine aminotransferase (ALT) | IU/L | Blood-draw participants |
| `ast` | LBXSASSI | Aspartate aminotransferase (AST) | IU/L | Blood-draw participants |
| `ggt` | LBXSGTSI | Gamma-glutamyl transferase (GGT) | IU/L | Blood-draw participants |
| `trig` | LBXSTR | **Triglycerides, non-fasting** (main triglyceride variable) | mg/dL | Blood-draw participants |
| `glucose` | LBXSGL | Glucose, non-fasting | mg/dL | Blood-draw participants |
| `chol` | LBXSCH | Total cholesterol | mg/dL | Blood-draw participants |

### Lipids

| Column | NHANES variable | Description | Units | Who has it |
|---|---|---|---|---|
| `hdl` | LBDHDD | Direct HDL cholesterol | mg/dL | Blood-draw participants |
| `trig_fast` | LBXTLG | Triglycerides, fasting (sensitivity analyses) | mg/dL | Fasting subsample |
| `ldl` | LBDLDLN | LDL cholesterol, NIH equation 2 | mg/dL | Fasting subsample |

### Alcohol (questionnaire)

| Column | NHANES variable | Description | Values | Who has it |
|---|---|---|---|---|
| `alq_ever` | ALQ111 | Ever had at least one drink of alcohol | 1 = Yes, 2 = No | Adults 18+ |
| `alq_freq` | ALQ121 | How often drank alcohol, past 12 months | Categories 0–10 (**backwards-coded; do not use as numeric**, use `drink_days_yr`). Never-drinkers set to 0. | Adults 18+ |
| `alq_drinks` | ALQ130 | Average drinks per drinking day, past 12 months | 1–14; 15 = "15 or more" (top-coded). Non-drinkers set to 0. | Adults 18+ |
| `alq_heavy_days` | ALQ142 | How often had 4+ (women) / 5+ (men) drinks in a day, past 12 months | Categories 0–10 (**backwards-coded**, use `heavy_days_yr`). Non-drinkers set to 0. | Adults 18+ |
| `alq_daily_hist` | ALQ151 | Ever a period of drinking 4+/5+ drinks almost every day | 1 = Yes, 2 = No | Adults 18+ who ever drank |

### Alcohol (derived)

| Column | Derived from | Description | Units |
|---|---|---|---|
| `drink_days_yr` | `alq_freq` | Approximate drinking days per year (table in section 4.4) | Days/year |
| `heavy_days_yr` | `alq_heavy_days` | Approximate heavy-drinking days per year | Days/year |
| `drinks_week` | `drink_days_yr × alq_drinks / 52` | **Approximate drinks per week** (main alcohol exposure) | Drinks/week |

`drinks_week` is an underestimate for anyone top-coded at 15 drinks per day.

### Diet (day-1 24-hour recall)

All values are totals for the recall day, and are `NA` unless `diet_status = 1`.

| Column | NHANES variable | Description | Units |
|---|---|---|---|
| `diet_status` | DR1DRSTZ | Dietary recall status | 1 = Reliable, 2 = Not reliable, 4 = Breast milk, 5 = Not done |
| `kcal` | DR1TKCAL | Energy | kcal |
| `protein_g` | DR1TPROT | Protein | g |
| `carb_g` | DR1TCARB | Carbohydrate | g |
| `sugar_g` | DR1TSUGR | Total sugars | g |
| `fiber_g` | DR1TFIBE | Dietary fiber | g |
| `fat_g` | DR1TTFAT | Total fat | g |
| `sfa_g` | DR1TSFAT | Saturated fatty acids | g |
| `mufa_g` | DR1TMFAT | Monounsaturated fatty acids | g |
| `pufa_g` | DR1TPFAT | Polyunsaturated fatty acids | g |
| `chol_diet_mg` | DR1TCHOL | Dietary cholesterol | mg |
| `choline_mg` | DR1TCHL | Total choline | mg |
| `caffeine_mg` | DR1TCAFF | Caffeine | mg |
| `alcohol_g` | DR1TALCO | Alcohol from recall (independent check on questionnaire intake) | g |

### Viral hepatitis

Used only for exclusions (section 7).

| Column | NHANES variable | Description | Values | Who has it |
|---|---|---|---|---|
| `hbsag` | LBDHBG | Hepatitis B surface antigen (marker of current HBV infection) | 1 = Positive, 2 = Negative | Exam participants 6+ with a blood sample |
| `hcv_ab` | LBDHCI | Hepatitis C antibody, confirmed (past or current HCV infection) | See `nhanesCodebook("HEPC_L", "LBDHCI")` | Exam participants 6+ with a blood sample |
| `hcv_rna` | LBXHCR | Hepatitis C RNA (marker of current HCV infection) | 1 = Positive, 2 = Negative | Tested only in antibody-positive participants |
---

## 6. Known limitations

- **Survey design:** NHANES is a complex survey. Unweighted models describe the sample, not the US population. Population estimates need the `survey` package with `psu`, `strata`, and the appropriate weight.
- **Cross-sectional design:** results are associations, not causal effects.
- **Self-report:** alcohol intake and diet are self-reported. A single-day recall is a noisy measure of usual diet.
- **Non-fasting triglycerides** vary with the last meal. Key results should be checked in the fasting subsample using `trig_fast`.
- **Alcohol quantities** are approximations from categorical answers (see section 4.4).
- **Hepatitis exclusion** removes only confirmed current infections. Participants without hepatitis test results are kept, so a small number of undetected infections may remain.
---

## 7. Analytic sample (`R/03_exclusions.R`)

The analytic sample is defined by applying these exclusions in order:

| Step | n | Excluded |
|---|---|---|
| Liver elastography records (LUX_L) | 7,199 | — |
| Aged 20 or older | 6,064 | 1,135 |
| Complete elastography exam | 5,277 | 787 |
| Usable CAP with ≥ 10 valid measurements | 5,276 | 1 |
| Not pregnant | 5,276 | 0 |
| No current hepatitis B or C infection | **5,227** | 49 |

The same table is saved as `output/exclusion_flow.csv`.

**Decisions and rationale:**

- **Age 20+.** Education (`educ`) is only collected from age 20, and the alcohol questionnaire from 18. Starting at 20 keeps every covariate available.
- **Complete exams only.** Partial exams (`scan_status = 2`) are excluded, even when they produced a CAP value.
- **At least 10 valid measurements.** This removed only one person, so the rule is nearly redundant with the complete-exam requirement. It is kept as an explicit quality check.
- **CAP IQR cutoff not applied.** A CAP IQR < 40 dB/m rule would have removed 2,534 scanned participants, and its use is debated in the literature.
- **Stiffness reliability rule not applied.** The IQR/median ≤ 0.30 rule applies to liver stiffness, not CAP. Apply it in any analysis with `stiffness` as the outcome.
- **Pregnancy.** This removed nobody: all 41 pregnant participants were ineligible for the scan. The step documents the check.
- **Viral hepatitis.** Participants with current infection (`hbsag = 1` or `hcv_rna = 1`) are excluded, as other causes of liver disease are standard exclusions in steatosis studies. Participants without test results are kept.
- **Missing covariates are not excluded here.** Missing alcohol, lab, or diet values are handled model by model, so each model uses every participant with complete data for its own variables.
---

## 8. Rebuilding the data

```r
source("R/01_download.R")              # downloads raw files (skips existing ones)
source("R/01b_variable_inventory.R")   # optional: regenerates the variable inventory
source("R/02_clean_merge.R")           # builds merged_full.rds and analysis.rds
source("R/03_exclusions.R")            # builds analytic_sample.rds and exclusion_flow.csv
```
