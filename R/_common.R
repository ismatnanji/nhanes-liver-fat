# R/_common.R — shared setup sourced by every analysis notebook
library(dplyr)
library(ggplot2)

theme_set(theme_minimal(base_size = 12))

analytic <- readRDS(here::here("data", "processed", "analytic_sample.rds"))
