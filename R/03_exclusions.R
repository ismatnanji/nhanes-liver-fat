# R/03_exclusions.R
# Defines the analytic sample: adults 20+ with a reliable liver scan and
# no current viral hepatitis. Records how many people each step removes.

library(dplyr)

analysis <- readRDS(here::here("data", "processed", "analysis.rds"))

# ---- Exclusion steps --------------------------------------------------------
s0 <- analysis
s1 <- s0 |> filter(age >= 20)
s2 <- s1 |> filter(scan_status == 1)                 # complete exam
s3 <- s2 |> filter(!is.na(cap), n_valid >= 10)       # usable CAP, >= 10 valid measures
s4 <- s3 |> filter(!(preg %in% 1))                   # not pregnant
s5 <- s4 |> filter(!(hbsag %in% 1), !(hcv_rna %in% 1))  # no current HBV/HCV infection

# ---- Flow table --------------------------------------------------------------
flow <- tibble(
  step = c("Liver elastography records (LUX_L)",
           "Aged 20 or older",
           "Complete elastography exam",
           "Usable CAP with >= 10 valid measurements",
           "Not pregnant",
           "No current hepatitis B or C infection"),
  n = sapply(list(s0, s1, s2, s3, s4, s5), nrow)
) |>
  mutate(excluded = lag(n) - n)

print(flow)

# ---- Save --------------------------------------------------------------------
analytic <- s5
saveRDS(analytic, here::here("data", "processed", "analytic_sample.rds"))
write.csv(flow, here::here("output", "exclusion_flow.csv"), row.names = FALSE)

message("Analytic sample: ", nrow(analytic), " participants")
