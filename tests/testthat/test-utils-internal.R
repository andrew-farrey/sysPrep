
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
