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

test_that("restore_input_names() renames normalized columns back and leaves added columns", {
  original <- c("Hospital Name", "Visit_ID")
  cleaned  <- c("hospital_name", "visit_id")
  result <- restore_input_names(
    tibble::tibble(hospital_name = "A", visit_id = "V1", .episode_id = "x"),
    input_name_map(original, cleaned)
  )
  expect_identical(names(result), c("Hospital Name", "Visit_ID", ".episode_id"))
})

test_that("finish_names() normalizes with clean_names = TRUE and restores with FALSE", {
  map <- input_name_map(c("Visit_ID"), c("visit_id"))
  expect_identical(
    names(finish_names(tibble::tibble(Visit_ID = 1), TRUE, map)), "visit_id"
  )
  expect_identical(
    names(finish_names(tibble::tibble(visit_id = 1), FALSE, map)), "Visit_ID"
  )
})

test_that("capture_col_sym() returns NULL, a symbol, or aborts on anything else", {
  f <- function(col = NULL) capture_col_sym(rlang::enquo(col))
  expect_null(f())
  expect_null(f(NULL))
  expect_identical(f(Hospital), rlang::sym("Hospital"))
  expect_identical(f("Hospital"), rlang::sym("Hospital"))
  expect_error(f(c(a, b)), "must be an unquoted column name")
})

test_that("dedupe() and summarize_duplicates() abort clearly on a non-name facility_col", {
  expect_error(dedupe(essence_raw, facility_col = c(a, b)), "unquoted column name")
  expect_error(
    summarize_duplicates(essence_raw, facility_col = Hospital + 1),
    "unquoted column name"
  )
})
