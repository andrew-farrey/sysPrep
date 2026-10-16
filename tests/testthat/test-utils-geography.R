# Tests for the geography helpers in R/utils-geography.R ----
# These are internal functions; testthat runs tests inside the package
# namespace, so they are called directly.

test_that("resolve_geography_output_col() returns NULL when new_col is NULL", {
  data   <- tibble::tibble(hospital_name = "A")
  result <- resolve_geography_output_col(
    new_col      = NULL,
    data         = data,
    overwrite    = FALSE,
    reserved_col = ".out_of_state",
    arg_name     = "new_region_col"
  )
  expect_null(result)
})
