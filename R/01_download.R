# R/01_download.R
# Downloads the NHANES August 2021–August 2023 files used in this project
# and saves each one as an .rds file in data/raw/.

library(nhanesA)

tables <- c(
  demo   = "DEMO_L",    # demographics + survey design variables
  liver  = "LUX_L",     # transient elastography (CAP, liver stiffness)
  alc    = "ALQ_L",     # alcohol use questionnaire
  diet   = "DR1TOT_L",  # day-1 dietary recall totals
  body   = "BMX_L",     # body measures (BMI, waist)
  biopro = "BIOPRO_L",  # standard biochemistry (ALT, AST, GGT)
  trig   = "TRIGLY_L",  # triglycerides (fasting subsample)
  hdl    = "HDL_L",     # HDL cholesterol
  hepb   = "HEPBD_L",   # hepatitis B core antibody + surface antigen
  hepc   = "HEPC_L"     # hepatitis C antibody + RNA
)

raw_dir <- "data/raw"
dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)

for (tbl in tables) {
  out_file <- file.path(raw_dir, paste0(tbl, ".rds"))

  if (file.exists(out_file)) {
    message("Skipping ", tbl, " (already downloaded)")
    next
  }

  message("Downloading ", tbl, " ...")
  dat <- tryCatch(
    nhanes(tbl, translated = FALSE),
    error = function(e) {
      warning("Failed to download ", tbl, ": ", conditionMessage(e))
      NULL
    }
  )

  if (!is.data.frame(dat) || nrow(dat) == 0) next

  saveRDS(dat, out_file)
  message("  saved ", nrow(dat), " rows x ", ncol(dat), " columns")
}

# Record when and how the data were pulled
writeLines(
  c(paste("Downloaded:", Sys.time()),
    paste("nhanesA version:", as.character(packageVersion("nhanesA"))),
    paste("R version:", R.version.string)),
  file.path(raw_dir, "download_log.txt")
)
