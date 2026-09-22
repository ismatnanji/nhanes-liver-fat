# R/02_clean_merge.R
# Merges the raw NHANES 2021–2023 files onto the liver elastography table,
# selects analysis variables, and recodes NHANES missing-value codes.

library(dplyr)

raw_dir <- "data/raw"
out_dir <- "data/processed"
read_raw <- function(tbl) readRDS(file.path(raw_dir, paste0(tbl, ".rds")))

tables <- c("LUX_L", "DEMO_L", "ALQ_L", "DR1TOT_L",
            "BMX_L", "BIOPRO_L", "TRIGLY_L", "HDL_L",
            "HEPBD_L", "HEPC_L")
raw_list <- setNames(lapply(tables, read_raw), tables)

# ---- 1. Check the join key -------------------------------------------------
for (t in tables) {
  if (anyDuplicated(raw_list[[t]]$SEQN)) stop("Duplicate SEQN values in ", t)
}

# ---- 2. Merge: LUX_L is the spine -------------------------------------------
merged <- raw_list$LUX_L |>
  left_join(raw_list$DEMO_L,   by = "SEQN") |>
  left_join(raw_list$ALQ_L,    by = "SEQN") |>
  left_join(raw_list$DR1TOT_L, by = "SEQN") |>
  left_join(raw_list$BMX_L,    by = "SEQN") |>
  left_join(raw_list$BIOPRO_L, by = "SEQN") |>
  left_join(raw_list$TRIGLY_L, by = "SEQN") |>
  left_join(select(raw_list$HDL_L, -WTPH2YR), by = "SEQN") |>
  left_join(raw_list$HEPBD_L, by = "SEQN") |>
  left_join(raw_list$HEPC_L,  by = "SEQN")

stopifnot(nrow(merged) == nrow(raw_list$LUX_L))

dup_cols <- grep("\\.(x|y)$", names(merged), value = TRUE)
if (length(dup_cols) > 0) {
  warning("Column name clashes after joining: ", paste(dup_cols, collapse = ", "))
}

saveRDS(merged, file.path(out_dir, "merged_full.rds"))

# ---- 3. Select and rename analysis variables -------------------------------
vars <- c(
  id              = "SEQN",
  # survey design and weights
  psu             = "SDMVPSU",
  strata          = "SDMVSTRA",
  wt_mec          = "WTMEC2YR",
  wt_phleb        = "WTPH2YR",
  wt_fast         = "WTSAF2YR",
  wt_diet         = "WTDRD1",
  # demographics
  sex             = "RIAGENDR",
  age             = "RIDAGEYR",
  race_eth        = "RIDRETH3",
  educ            = "DMDEDUC2",
  pir             = "INDFMPIR",
  preg            = "RIDEXPRG",
  # liver scan
  scan_status     = "LUAXSTAT",
  n_valid         = "LUANMVGP",
  cap             = "LUXCAPM",
  cap_iqr         = "LUXCPIQR",
  stiffness       = "LUXSMED",
  stiff_iqr_ratio = "LUXSIQRM",
  # body measures
  bmi             = "BMXBMI",
  waist           = "BMXWAIST",
  # biochemistry (non-fasting)
  alt             = "LBXSATSI",
  ast             = "LBXSASSI",
  ggt             = "LBXSGTSI",
  trig            = "LBXSTR",
  glucose         = "LBXSGL",
  chol            = "LBXSCH",
  # lipids
  hdl             = "LBDHDD",
  trig_fast       = "LBXTLG",
  ldl             = "LBDLDLN",
  # alcohol questionnaire
  alq_ever        = "ALQ111",
  alq_freq        = "ALQ121",
  alq_drinks      = "ALQ130",
  alq_heavy_days  = "ALQ142",
  alq_daily_hist  = "ALQ151",
  # diet (day 1 recall)
  diet_status     = "DR1DRSTZ",
  kcal            = "DR1TKCAL",
  protein_g       = "DR1TPROT",
  carb_g          = "DR1TCARB",
  sugar_g         = "DR1TSUGR",
  fiber_g         = "DR1TFIBE",
  fat_g           = "DR1TTFAT",
  sfa_g           = "DR1TSFAT",
  mufa_g          = "DR1TMFAT",
  pufa_g          = "DR1TPFAT",
  chol_diet_mg    = "DR1TCHOL",
  choline_mg      = "DR1TCHL",
  caffeine_mg     = "DR1TCAFF",
  alcohol_g       = "DR1TALCO",

  # viral hepatitis
  hbsag   = "LBDHBG",   # hepatitis B surface antigen (current HBV infection)
  hcv_ab  = "LBDHCI",   # hepatitis C antibody, confirmed (past or current)
  hcv_rna = "LBXHCR"    # hepatitis C RNA (current HCV infection)
)
missing_vars <- setdiff(vars, names(merged))
if (length(missing_vars) > 0) {
  stop("Variables not found (check with nhanesCodebook): ",
       paste(missing_vars, collapse = ", "))
}

analysis <- merged |> select(all_of(vars))   # named vector = select + rename

# ---- 4. Recode NHANES missing-value codes -----------------------------------
analysis <- analysis |>
  mutate(
    across(c(alq_ever, alq_daily_hist, educ), ~ replace(.x, .x %in% c(7, 9), NA)),
    across(c(alq_freq, alq_heavy_days),       ~ replace(.x, .x %in% c(77, 99), NA)),
    alq_drinks = replace(alq_drinks, alq_drinks %in% c(777, 999), NA),
    sex        = factor(sex, levels = c(1, 2), labels = c("Male", "Female"))
  )

# Approximate drinking days per year for each ALQ121/ALQ142 category
freq_days <- c(`0` = 0, `1` = 365, `2` = 286, `3` = 182, `4` = 104,
               `5` = 52, `6` = 30, `7` = 12, `8` = 9, `9` = 4.5, `10` = 1.5)

analysis <- analysis |>
  mutate(
    # Legitimate skips: never-drinkers and past-year abstainers drank zero
    alq_drinks     = case_when(alq_ever == 2 | alq_freq == 0 ~ 0, TRUE ~ alq_drinks),
    alq_heavy_days = case_when(alq_ever == 2 | alq_freq == 0 ~ 0, TRUE ~ alq_heavy_days),
    alq_freq       = case_when(alq_ever == 2 ~ 0, TRUE ~ alq_freq),

    # Convert backwards-coded categories into real quantities
    drink_days_yr  = unname(freq_days[as.character(alq_freq)]),
    heavy_days_yr  = unname(freq_days[as.character(alq_heavy_days)]),
    drinks_week    = drink_days_yr * alq_drinks / 52,

    # Keep dietary values only from reliable recalls
    across(kcal:alcohol_g, ~ replace(.x, !(diet_status %in% 1), NA))
  )

saveRDS(analysis, file.path(out_dir, "analysis.rds"))

message("Saved analysis dataset: ", nrow(analysis), " rows x ",
        ncol(analysis), " columns")
summary(analysis)
