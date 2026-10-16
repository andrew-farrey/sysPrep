# Tests for the stage helpers in R/utils-link-stages.R ----
# These are internal functions; testthat runs tests inside the package
# namespace, so they are called directly. The stages are also exercised
# end to end by test-link_encounters.R.

test_that("split_patient_class_list() splits code form into single letters", {
  expect_identical(split_patient_class_list("EI"), list(c("E", "I")))
})

test_that("split_patient_class_list() splits label form on commas and trims", {
  expect_identical(
    split_patient_class_list("Emergency, Inpatient"),
    list(c("Emergency", "Inpatient"))
  )
})

test_that("split_patient_class_list() maps NA and empty values to a single NA", {
  expect_identical(
    split_patient_class_list(c(NA, "")),
    list(NA_character_, NA_character_)
  )
})

test_that("pair_mdt_timestamps() returns NA per class when MDT updates are unused", {
  pc_split <- list(c("E", "I"), "E")
  result <- pair_mdt_timestamps(
    data.frame(x = 1:2), pc_split, use_mdt = FALSE, mdt_col_str = NA_character_
  )
  expect_identical(result, list(c(NA_character_, NA_character_), NA_character_))
})

test_that("pair_mdt_timestamps() pairs each position with its timestamp", {
  ed <- data.frame(
    mdt = "{1};2026-06-19 16:00:06.000;|{2};2026-06-19 17:55:10.000;"
  )
  result <- pair_mdt_timestamps(
    ed, list(c("E", "I")), use_mdt = TRUE, mdt_col_str = "mdt"
  )
  expect_identical(
    result[[1L]],
    c("2026-06-19 16:00:06.000", "2026-06-19 17:55:10.000")
  )
})

test_that("pair_mdt_timestamps() warns once about unparseable updates", {
  ed <- data.frame(mdt = c("garbage", "{1};2026-06-19 16:00:06.000;"))
  expect_warning(
    pair_mdt_timestamps(
      ed, list("E", "E"), use_mdt = TRUE, mdt_col_str = "mdt"
    ),
    "1 row(s) had a non-empty",
    fixed = TRUE
  )
})

test_that("check_inpatient_admission_data() attributes its error to the caller", {
  caller <- function() check_inpatient_admission_data(NULL, is_missing = TRUE)
  err <- tryCatch(caller(), error = identity)
  expect_match(conditionMessage(err), "requires `inpatient_admission_data`")
  expect_identical(rlang::call_name(err$call), "caller")
})
