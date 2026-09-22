# Alcohol, Diet, and Hepatic Steatosis in US Adults (NHANES 2021–2023)

## Overview
Alcohol intake and metabolic risk factors are the two main drivers of fatty
liver disease, and in many people they coexist. This project examines how
alcohol consumption, dietary composition, and metabolic measures relate to
liver fat in US adults, using transient elastography data from the National
Health and Nutrition Examination Survey (NHANES).

The emphasis is on transparent, reproducible regression modelling: every step
from raw data download to final model is scripted and documented.

## Questions
1. How is liver fat (controlled attenuation parameter, CAP) associated with
   alcohol intake, BMI, lipids, and liver enzymes?
2. Does the association between alcohol and liver fat depend on dietary
   composition (e.g. fat or sugar intake)?
3. Which factors best predict steatosis, defined by established CAP cutoffs?

## Data
Public NHANES August 2021–August 2023 files from the CDC/NCHS:
demographics, liver elastography, alcohol use, dietary recall, body measures,
biochemistry, and lipids. Data are downloaded by script and not stored in
this repository.

## Methods (in progress)
- Linear regression with interaction terms
- Model diagnostics and variable transformations
- Model selection
- Logistic regression for steatosis status
- Survey-weighted models using the `survey` package

## Reproducing the analysis
1. Clone the repository and open `nhanes-liver-fat.Rproj`
2. Run `R/01_download.R` to download the raw data
3. Run `R/02_clean_merge.R` to build the analysis dataset
4. Render the notebooks in `analysis/`

## Limitations
- Cross-sectional design: results describe associations, not causation.
- Alcohol intake and diet are self-reported.
- Unweighted models describe the sample; population-level estimates
  require the survey-weighted models.

## Author
Ismat — [https://github.com/ismatnanji] · [ismat.nanjis@gmail.com]
