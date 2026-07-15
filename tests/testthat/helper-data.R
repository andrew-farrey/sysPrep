
# Test fixtures ----
# Shared data helpers for sysPrep tests.
# Loaded automatically by testthat before each test file.

# Minimal data frame with standard ESSENCE column names ----
make_essence_data <- function(n = 10L,
                               include_biosense    = TRUE,
                               include_pid         = TRUE,
                               include_patient_class = FALSE,
                               include_has_been    = TRUE,
                               include_geography   = TRUE) {

  set.seed(42L)

  facilities <- c(
    "Central Medical Center",
    "North County Hospital",
    "River Valley Medical"
  )

  d <- tibble::tibble(
    HospitalName  = sample(facilities, n, replace = TRUE),
    Hospital      = dplyr::case_when(
      HospitalName == "Central Medical Center" ~ 1001L,
      HospitalName == "North County Hospital"  ~ 1002L,
      TRUE                                     ~ 1003L
    ),
    Visit_ID      = sprintf("V%08d", seq_len(n)),
    FacilityType  = "Emergency Care",
    Date          = seq(as.Date("2023-01-01"), by = "day", length.out = n)
  )

  if (include_biosense) {
    d$C_BioSense_ID <- sprintf("BS%010d", seq_len(n))
  }

  if (include_pid) {
    d$C_Unique_Patient_ID <- sprintf("P%08d", seq_len(n))
  }

  if (include_patient_class) {
    d$c_patient_class <- sample(c("E", "I", "O"), n, replace = TRUE,
                                prob = c(0.7, 0.2, 0.1))
  }

  if (include_has_been) {
    d$HasBeenE        <- 1L
    d$HasBeenAdmitted <- sample(c(0L, 1L), n, replace = TRUE, prob = c(0.8, 0.2))
  }

  if (include_geography) {
    d$HospitalRegion <- dplyr::case_when(
      d$HospitalName == "Central Medical Center" ~ "KY_Jefferson",
      d$HospitalName == "North County Hospital"  ~ "KY_Kenton",
      TRUE                                       ~ "KY_Warren"
    )
    d$HospitalZip <- dplyr::case_when(
      d$HospitalName == "Central Medical Center" ~ "40201",
      d$HospitalName == "North County Hospital"  ~ "41011",
      TRUE                                       ~ "42101"
    )
    d$Region  <- sample(
      c("KY_Jefferson", "KY_Fayette", "TN_Davidson", "OTHER_REGION"),
      n, replace = TRUE, prob = c(0.5, 0.3, 0.1, 0.1)
    )
    d$ZipCode <- dplyr::if_else(d$Region == "OTHER_REGION", NA_character_, "40201")
  }

  d
}

# Data with known duplicates ----
make_data_with_dups <- function() {
  base <- make_essence_data(n = 10L)

  # standard duplicate: same hospital x Visit_ID, different Arrived_Date_Time
  dup_standard <- base[1L, ] |>
    dplyr::mutate(C_BioSense_ID = "BS_STANDARD_DUP")

  # visit_date_change: same Visit_ID, different C_BioSense_ID, Date + 1
  dup_date <- base[2L, ] |>
    dplyr::mutate(
      C_BioSense_ID = "BS_DATE_CHANGE_DUP",
      Date          = Date + 1L
    )

  # pid_change: same Visit_ID, different C_Unique_Patient_ID
  dup_pid <- base[3L, ] |>
    dplyr::mutate(C_Unique_Patient_ID = "P_PID_CHANGE_DUP")

  dplyr::bind_rows(base, dup_standard, dup_date, dup_pid)
}

# Data representing the ED-visit-immediately-followed-by-direct-admit data
# quality issue: same facility x Visit_ID, differing merge-relevant field
# values on each row (the scenario link_encounters()'s merge step exists to
# handle correctly) ----
make_readmit_merge_data <- function() {
  ed_row <- tibble::tibble(
    HospitalName           = "Central Medical Center",
    Hospital                = 1001L,
    Visit_ID                = "V00000001",
    FacilityType             = "Emergency Care",
    Date                     = as.Date("2023-01-01"),
    C_BioSense_ID            = "BS0000000001",
    C_Unique_Patient_ID      = "P00000001",
    HasBeenE                 = 1L,
    HasBeenAdmitted          = 0L,
    CCDD                     = "abdominal pain|R10.9",
    CCDDParsed               = "abdominal pain|R10.9",
    CCDDCategory_flat        = "GI;Pain",
    C_Death                  = "No",
    Discharge_Disposition    = "Discharged to home",
    DispositionCategory      = "Discharged"
  )

  direct_admit_row <- tibble::tibble(
    HospitalName           = "Central Medical Center",
    Hospital                = 1001L,
    Visit_ID                = "V00000001",
    FacilityType             = "Emergency Care",
    Date                     = as.Date("2023-01-01"),
    C_BioSense_ID            = "BS0000000002",
    C_Unique_Patient_ID      = "P00000001",
    HasBeenE                 = 0L,
    HasBeenAdmitted          = 1L,
    CCDD                     = "opioid overdose|T40.6",
    CCDDParsed               = "opioid overdose|T40.6",
    CCDDCategory_flat        = "Overdose;Toxicology",
    C_Death                  = "Yes",
    Discharge_Disposition    = "Expired",
    DispositionCategory      = "Died"
  )

  list(ed_data = ed_row, inpatient_admission_data = direct_admit_row)
}
