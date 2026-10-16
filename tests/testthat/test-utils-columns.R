# Tests for the column-resolution helpers in R/utils-columns.R ----
# These are internal functions; testthat runs tests inside the package
# namespace, so they are called directly.

test_that("resolve_col() finds column by exact name", {
  data   <- tibble::tibble(hospital_name = "A", visit_id = "V1")
  result <- resolve_col(data, rlang::sym("hospital_name"))
  expect_equal(rlang::as_string(result), "hospital_name")
})

test_that("resolve_col() finds column via snake_case normalization", {
  # Data has snake_case; user supplies PascalCase equivalent
  data   <- tibble::tibble(hospital_name = "A", visit_id = "V1")
  result <- resolve_col(data, rlang::sym("HospitalName"))
  expect_equal(rlang::as_string(result), "hospital_name")
})

test_that("resolve_col() aborts with informative message when column absent", {
  data <- tibble::tibble(hospital_name = "A")
  expect_error(
    resolve_col(data, rlang::sym("nonexistent_col")),
    "not found in data"
  )
})

test_that("resolve_col_optional() returns NULL when column is absent", {
  data   <- tibble::tibble(hospital_name = "A")
  result <- resolve_col_optional(data, rlang::sym("nonexistent_col"))
  expect_null(result)
})

test_that("resolve_col_optional() returns symbol when column is present", {
  data   <- tibble::tibble(hospital_name = "A", visit_id = "V1")
  result <- resolve_col_optional(data, rlang::sym("hospital_name"))
  expect_equal(rlang::as_string(result), "hospital_name")
})

test_that("resolve_facility_col() prefers Hospital over HospitalName when facility_col is missing and Hospital is present", {
  data   <- tibble::tibble(HospitalName = "A", Hospital = 1001L, Visit_ID = "V1")
  result <- resolve_facility_col(
    data, rlang::sym("HospitalName"), facility_col_missing = TRUE
  )
  expect_equal(rlang::as_string(result), "Hospital")
})

test_that("resolve_facility_col() falls back to HospitalName when Hospital is absent", {
  data   <- tibble::tibble(HospitalName = "A", Visit_ID = "V1")
  result <- resolve_facility_col(
    data, rlang::sym("HospitalName"), facility_col_missing = TRUE
  )
  expect_equal(rlang::as_string(result), "HospitalName")
})

test_that("resolve_facility_col() honors an explicitly supplied facility_col even when Hospital is present", {
  data   <- tibble::tibble(HospitalName = "A", Hospital = 1001L, Visit_ID = "V1")
  result <- resolve_facility_col(
    data, rlang::sym("HospitalName"), facility_col_missing = FALSE
  )
  expect_equal(rlang::as_string(result), "HospitalName")
})

test_that("resolve_facility_col_str() returns a string, preferring Hospital when missing", {
  data   <- tibble::tibble(HospitalName = "A", Hospital = 1001L, Visit_ID = "V1")
  result <- resolve_facility_col_str(
    data, rlang::sym("HospitalName"), facility_col_missing = TRUE
  )
  expect_identical(result, "Hospital")
})
