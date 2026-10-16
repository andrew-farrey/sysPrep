# Tests for the NA-safe grouping helpers in R/utils-na-keys.R ----
# These are internal functions; testthat runs tests inside the package
# namespace, so they are called directly.

test_that("na_safe_group_id() groups rows normally when no key value is NA", {
  data <- tibble::tibble(fac = c(1, 1, 2), visit = c("A", "A", "A"))
  result <- na_safe_group_id(data, c("fac", "visit"))
  expect_equal(result[1L], result[2L])
  expect_false(result[1L] == result[3L])
})

test_that("na_safe_group_id() never merges two rows that both have a missing key value", {
  # Regression test for the real bug this helper exists to prevent:
  # dplyr::group_by()/`.by =` follow SQL's GROUP BY convention, where every
  # NA is treated as equal to every other NA, so several rows sharing a
  # missing Visit_ID silently collapsed into a single group even though
  # a missing value means the row's true identity is unknown, not
  # confirmed to match.
  data <- tibble::tibble(
    fac   = c(1, 1, 1, 1),
    visit = c(NA, NA, "V1", NA)
  )
  result <- na_safe_group_id(data, c("fac", "visit"))
  expect_length(unique(result), 4L)
})

test_that("key_has_na_mask() flags rows where any listed column is NA", {
  data <- tibble::tibble(fac = c(1, NA, 1), visit = c("A", "B", NA))
  result <- key_has_na_mask(data, c("fac", "visit"))
  expect_equal(result, c(FALSE, TRUE, TRUE))
})
