
# test-review_facility_ed_visits.R ----

test_that("review_facility_ed_visits() returns a tibble", {
  data <- make_essence_data(n = 20L)
  result <- suppressMessages(review_facility_ed_visits(data))
  expect_s3_class(result, "data.frame")
})

test_that("review_facility_ed_visits() outlier flag columns are present", {
  data <- make_essence_data(n = 20L)
  result <- suppressMessages(
    review_facility_ed_visits(data, return_format = "all")
  )
  expect_true(all(c(".outlier_low", ".outlier_high", ".outlier_flag") %in%
                  names(result)))
})

test_that("review_facility_ed_visits() return_format = 'all' returns all facilities", {
  data <- make_essence_data(n = 20L)
  result <- suppressMessages(
    review_facility_ed_visits(data, return_format = "all")
  )
  expect_equal(nrow(result), dplyr::n_distinct(data$HospitalName))
})

test_that("review_facility_ed_visits() visits_per_day present with date_col", {
  data <- make_essence_data(n = 20L)
  result <- suppressMessages(
    review_facility_ed_visits(data, date_col = Date, return_format = "all")
  )
  expect_true("visits_per_day" %in% names(result))
})

test_that("review_facility_ed_visits() return_format = 'outliers_only' returns <= n facilities", {
  data <- make_essence_data(n = 20L)
  n_facilities <- dplyr::n_distinct(data$HospitalName)
  result <- suppressMessages(review_facility_ed_visits(data))
  expect_lte(nrow(result), n_facilities)
})

test_that("review_facility_ed_visits() .outlier_direction = 'low' for low outliers", {
  # 4 large facilities + 1 tiny one -> clear low outlier via IQR (IQR = 0)
  big   <- lapply(1:4, function(i) {
    make_essence_data(n = 20L) |>
      dplyr::mutate(HospitalName = paste0("Big_", i), Hospital = 2000L + i)
  })
  small <- make_essence_data(n = 1L) |>
    dplyr::mutate(HospitalName = "Small_1", Hospital = 2005L)
  data  <- dplyr::bind_rows(c(big, list(small)))
  result <- suppressMessages(
    review_facility_ed_visits(data, method = "iqr", return_format = "all")
  )
  small_row <- dplyr::filter(result, hospital_name == "Small_1")
  expect_true(small_row$.outlier_low)
  expect_equal(small_row$.outlier_direction, "low")
})

test_that("review_facility_ed_visits() method = 'iqr' flags IQR-based outlier", {
  big   <- lapply(1:4, function(i) {
    make_essence_data(n = 20L) |>
      dplyr::mutate(HospitalName = paste0("Big_", i), Hospital = 2000L + i)
  })
  small <- make_essence_data(n = 1L) |>
    dplyr::mutate(HospitalName = "Small_1", Hospital = 2005L)
  data  <- dplyr::bind_rows(c(big, list(small)))
  result <- suppressMessages(
    review_facility_ed_visits(data, method = "iqr", return_format = "all")
  )
  small_row <- dplyr::filter(result, hospital_name == "Small_1")
  expect_true(small_row$.outlier_flag)
})

test_that("review_facility_ed_visits() method = 'both' flags union of methods", {
  big   <- lapply(1:4, function(i) {
    make_essence_data(n = 20L) |>
      dplyr::mutate(HospitalName = paste0("Big_", i), Hospital = 2000L + i)
  })
  small <- make_essence_data(n = 1L) |>
    dplyr::mutate(HospitalName = "Small_1", Hospital = 2005L)
  data  <- dplyr::bind_rows(c(big, list(small)))
  result <- suppressMessages(
    review_facility_ed_visits(data, method = "both", return_format = "all")
  )
  small_row <- dplyr::filter(result, hospital_name == "Small_1")
  expect_true(small_row$.outlier_flag)
})

test_that("review_facility_ed_visits() group_by_type = TRUE returns expected columns", {
  data <- make_essence_data(n = 30L)
  result <- suppressMessages(
    review_facility_ed_visits(data, group_by_type = TRUE, return_format = "all")
  )
  expect_true(all(c(".outlier_low", ".outlier_high", ".outlier_flag") %in%
                  names(result)))
  expect_equal(nrow(result), dplyr::n_distinct(data$HospitalName))
})

test_that("review_facility_ed_visits() verbose = FALSE suppresses informational messages", {
  data <- make_essence_data(n = 20L)
  expect_no_message(review_facility_ed_visits(data, verbose = FALSE))
})

test_that("review_facility_ed_visits() warns on missing date_col regardless of verbose", {
  data <- make_essence_data(n = 20L)
  expect_warning(
    review_facility_ed_visits(data, date_col = Fake_Date_Column, verbose = FALSE),
    "not found in data"
  )
})

test_that("review_facility_ed_visits() .outlier_flag is TRUE iff .outlier_low or .outlier_high", {
  big   <- lapply(1:4, function(i) {
    make_essence_data(n = 20L) |>
      dplyr::mutate(HospitalName = paste0("Big_", i), Hospital = 2000L + i)
  })
  small <- make_essence_data(n = 1L) |>
    dplyr::mutate(HospitalName = "Small_1", Hospital = 2005L)
  data  <- dplyr::bind_rows(c(big, list(small)))
  result <- suppressMessages(
    review_facility_ed_visits(data, method = "iqr", return_format = "all")
  )
  expected_flag <- result$.outlier_low | result$.outlier_high
  expect_equal(result$.outlier_flag, expected_flag)
})
