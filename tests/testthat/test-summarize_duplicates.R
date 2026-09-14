
# test-summarize_duplicates.R ----
test_that("summarize_duplicates() returns a list with three components", {
  data <- make_data_with_dups()
  result <- summarize_duplicates(data)
  expect_named(result, c("duplicate_ids", "by_facility", "overall"))
})

test_that("summarize_duplicates() overall counts are correct", {
  data <- make_data_with_dups()
  result <- summarize_duplicates(data)
  # We added 3 duplicate rows to 10 base rows
  expect_equal(result$overall$n_total_rows, 13L)
  expect_equal(result$overall$n_duplicated_visit_ids, 3L)
  expect_equal(result$overall$n_excess_rows, 3L)
})

test_that("summarize_duplicates() duplicate_ids contains correct pairs", {
  data <- make_data_with_dups()
  result <- summarize_duplicates(data)
  expect_equal(nrow(result$duplicate_ids), 3L)
  expect_true(all(c("hospital", "visit_id") %in% names(result$duplicate_ids)))
})

test_that("summarize_duplicates() by_facility is sorted by n_excess_rows desc", {
  data <- make_data_with_dups()
  result <- summarize_duplicates(data)
  expect_true(all(diff(result$by_facility$n_excess_rows) <= 0L))
})

test_that("summarize_duplicates() has class essence_dup_summary", {
  data <- make_data_with_dups()
  expect_s3_class(summarize_duplicates(data), "essence_dup_summary")
})

test_that("print.essence_dup_summary() dispatches and returns invisibly", {
  data   <- make_data_with_dups()
  result <- summarize_duplicates(data)
  # cli_h1() routes to stderr in non-interactive sessions; check dispatch
  # and invisible return rather than stdout content
  expect_no_error(print(result))
  expect_identical(result, withVisible(print(result))$value)
})

test_that("summarize_duplicates() works with no duplicates", {
  data <- make_essence_data(n = 5L)
  result <- summarize_duplicates(data)
  expect_equal(result$overall$n_duplicated_visit_ids, 0L)
  expect_equal(nrow(result$duplicate_ids), 0L)
})

test_that("summarize_duplicates() never counts rows sharing a missing visit_id as duplicates of each other", {
  # Regression test: grouping directly on facility_col/visit_col follows
  # dplyr's SQL-style GROUP BY convention, treating every NA as equal to
  # every other NA, so three rows with no Visit_ID used to be reported as
  # 2 unique visits / 1 duplicated pair instead of 4 genuinely distinct
  # (if unidentified) visits.
  data <- tibble::tibble(
    Hospital = c(1001L, 1001L, 1001L, 1001L),
    Visit_ID = c(NA, NA, "V1", NA)
  )
  expect_message(summarize_duplicates(data), "missing")
  result <- suppressMessages(summarize_duplicates(data))
  expect_equal(result$overall$n_unique_visits, 4L)
  expect_equal(result$overall$n_duplicated_visit_ids, 0L)
  expect_equal(nrow(result$duplicate_ids), 0L)
})

test_that("summarize_duplicates() honors an explicitly supplied facility_col over the Hospital preference", {
  data <- make_data_with_dups()
  result <- summarize_duplicates(data, facility_col = HospitalName)
  expect_true(all(c("hospital_name", "visit_id") %in% names(result$duplicate_ids)))
})
