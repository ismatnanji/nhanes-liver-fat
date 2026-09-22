# R/01b_variable_inventory.R
# Builds an inventory of every variable in the raw NHANES files:
# label, type, missingness, and number of unique values.

library(nhanesA)

files <- list.files("data/raw", pattern = "\\.rds$", full.names = TRUE)

describe_table <- function(f) {
  tbl <- sub("\\.rds$", "", basename(f))
  d   <- readRDS(f)

  # Labels stored with the data by nhanesA
  labels <- vapply(d, function(col) {
    lab <- attr(col, "label")
    if (is.null(lab)) NA_character_ else as.character(lab)[1]
  }, character(1))

  # Fall back to the CDC metadata if labels weren't stored
  if (all(is.na(labels))) {
    web <- nhanesAttr(tbl)$labels
    if (!is.null(names(web))) {
      labels <- unname(as.character(web[names(d)]))
    } else if (length(web) == ncol(d)) {
      labels <- as.character(web)
    }
  }

  bad <- !validUTF8(labels)
  labels[bad] <- iconv(labels[bad], from = "latin1", to = "UTF-8")

  data.frame(
    table       = tbl,
    variable    = names(d),
    label       = labels,
    class       = vapply(d, function(x) class(x)[1], character(1)),
    n_missing   = vapply(d, function(x) sum(is.na(x)), integer(1)),
    pct_missing = round(100 * vapply(d, function(x) mean(is.na(x)), numeric(1)), 1),
    n_unique    = vapply(d, function(x) length(unique(x)), integer(1)),
    row.names   = NULL
  )
}

inventory <- do.call(rbind, lapply(files, describe_table))

dir.create("output", showWarnings = FALSE)
write.csv(inventory, "output/variable_inventory.csv", row.names = FALSE, fileEncoding = "UTF-8")

message("Variables per table:")
print(table(inventory$table))
message("Variables with no label: ", sum(is.na(inventory$label)))
