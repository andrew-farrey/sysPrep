
# test-utils-internal.R ----
# Tests for unexported helpers: resolve_col() and resolve_col_optional().
# Accessed via ::: since these are internal functions.

test_that("resolve_col() finds column by exact name", {
  data   <- tibble::tibble(hospital_name = "A", visit_id = "V1")
  result <- sysPrep:::resolve_col(data, rlang::sym("hospital_name"))
  expect_equal(rlang::as_string(result), "hospital_name")
})

test_that("resolve_col() finds column via snake_case normalization", {
  # Data has snake_case; user supplies PascalCase equivalent
  data   <- tibble::tibble(hospital_name = "A", visit_id = "V1")
  result <- sysPrep:::resolve_col(data, rlang::sym("HospitalName"))
  expect_equal(rlang::as_string(result), "hospital_name")
})

test_that("resolve_col() aborts with informative message when column absent", {
  data <- tibble::tibble(hospital_name = "A")
  expect_error(
    sysPrep:::resolve_col(data, rlang::sym("nonexistent_col")),
    "not found in data"
  )
})

test_that("resolve_col_optional() returns NULL when column is absent", {
  data   <- tibble::tibble(hospital_name = "A")
  result <- sysPrep:::resolve_col_optional(data, rlang::sym("nonexistent_col"))
  expect_null(result)
})

test_that("resolve_col_optional() returns symbol when column is present", {
  data   <- tibble::tibble(hospital_name = "A", visit_id = "V1")
  result <- sysPrep:::resolve_col_optional(data, rlang::sym("hospital_name"))
  expect_equal(rlang::as_string(result), "hospital_name")
})

test_that("resolve_facility_col() prefers Hospital over HospitalName when facility_col is missing and Hospital is present", {
  data   <- tibble::tibble(HospitalName = "A", Hospital = 1001L, Visit_ID = "V1")
  result <- sysPrep:::resolve_facility_col(
    data, rlang::sym("HospitalName"), facility_col_missing = TRUE
  )
  expect_equal(rlang::as_string(result), "Hospital")
})

test_that("resolve_facility_col() falls back to HospitalName when Hospital is absent", {
  data   <- tibble::tibble(HospitalName = "A", Visit_ID = "V1")
  result <- sysPrep:::resolve_facility_col(
    data, rlang::sym("HospitalName"), facility_col_missing = TRUE
  )
  expect_equal(rlang::as_string(result), "HospitalName")
})

test_that("resolve_facility_col() honors an explicitly supplied facility_col even when Hospital is present", {
  data   <- tibble::tibble(HospitalName = "A", Hospital = 1001L, Visit_ID = "V1")
  result <- sysPrep:::resolve_facility_col(
    data, rlang::sym("HospitalName"), facility_col_missing = FALSE
  )
  expect_equal(rlang::as_string(result), "HospitalName")
})

test_that("resolve_facility_col_str() returns a string, preferring Hospital when missing", {
  data   <- tibble::tibble(HospitalName = "A", Hospital = 1001L, Visit_ID = "V1")
  result <- sysPrep:::resolve_facility_col_str(
    data, rlang::sym("HospitalName"), facility_col_missing = TRUE
  )
  expect_identical(result, "Hospital")
})

test_that("dedupe() groups by Hospital, not HospitalName, when a facility rename creates mismatched names for the same Hospital ID", {
  # Regression test for the real production failure this preference exists
  # to prevent: two rows sharing the same Hospital ID but differing in
  # HospitalName (e.g. a mid-period facility rename/rebrand) used to
  # survive a HospitalName-keyed dedupe as two "distinct" facilities,
  # producing a duplicate (hospital, visit) pair downstream wherever
  # Hospital is the real key (e.g. a database unique index).
  data <- tibble::tibble(
    HospitalName      = c("Old Facility Name", "New Facility Name"),
    Hospital          = c(1001L, 1001L),
    Visit_ID          = c("V00000001", "V00000001"),
    Arrived_Date_Time = as.POSIXct(c("2023-01-01 08:00:00", "2023-01-01 09:00:00"))
  )
  result <- dedupe(data, order_by = Arrived_Date_Time, keep = "last")
  expect_equal(nrow(result), 1L)
  expect_equal(result$hospital_name, "New Facility Name")
})

test_that("resolve_geography_output_col() returns NULL when new_col is NULL", {
  data   <- tibble::tibble(hospital_name = "A")
  result <- sysPrep:::resolve_geography_output_col(
    new_col      = NULL,
    data         = data,
    overwrite    = FALSE,
    reserved_col = ".out_of_state",
    arg_name     = "new_region_col"
  )
  expect_null(result)
})
