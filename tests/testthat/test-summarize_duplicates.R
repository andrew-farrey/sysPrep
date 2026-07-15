
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
  expect_true(all(c("hospital_name", "visit_id") %in% names(result$duplicate_ids)))
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
