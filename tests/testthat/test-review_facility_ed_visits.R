
# test-review_facility_ed_visits.R ----

test_that("review_facility_ed_visits() returns a tibble", {
  data <- make_essence_data(n = 20L)
  result <- suppressMessages(review_facility_ed_visits(data))
  expect_s3_class(result, "data.frame")
})

test_that("review_facility_ed_visits() honors an explicitly supplied facility_col over the Hospital preference", {
  data <- make_essence_data(n = 20L)
  result <- suppressMessages(
    review_facility_ed_visits(
      data, facility_col = HospitalName, return_format = "all"
    )
  )
  expect_true("hospital_name" %in% names(result))
})

test_that("review_facility_ed_visits() outlier flag columns are present", {
  data <- make_essence_data(n = 20L)
  result <- suppressMessages(
    review_facility_ed_visits(data, return_format = "all")
  )
  expect_true(all(
    c(".outlier_low", ".outlier_high", ".outlier_flag") %in% names(result)
  ))
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
  small_row <- dplyr::filter(result, hospital == 2005L)
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
  small_row <- dplyr::filter(result, hospital == 2005L)
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
  small_row <- dplyr::filter(result, hospital == 2005L)
  expect_true(small_row$.outlier_flag)
})

test_that("review_facility_ed_visits() group_by_type = TRUE returns expected columns", {
  data <- make_essence_data(n = 30L)
  result <- suppressMessages(
    review_facility_ed_visits(data, group_by_type = TRUE, return_format = "all")
  )
  expect_true(all(
    c(".outlier_low", ".outlier_high", ".outlier_flag") %in% names(result)
  ))
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

test_that("review_facility_ed_visits() informs when facility types are combined without group_by_type", {
  data <- make_essence_data(n = 20L) |>
    dplyr::mutate(
      FacilityType = rep(c("Emergency Care", "Urgent Care"), length.out = 20L)
    )
  expect_message(
    review_facility_ed_visits(data, group_by_type = FALSE),
    "Outlier detection across all facility types combined"
  )
})

test_that("review_facility_ed_visits() informs when no facilities remain after processing", {
  data <- dplyr::filter(make_essence_data(n = 1L), FALSE)
  expect_message(
    review_facility_ed_visits(data),
    "No facilities in data"
  )
})

test_that("review_facility_ed_visits() clean_names = FALSE returns a data frame without error", {
  data <- make_essence_data(n = 20L)
  result <- suppressMessages(
    review_facility_ed_visits(data, clean_names = FALSE)
  )
  expect_s3_class(result, "data.frame")
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
test_that("review_facility_ed_visits() clean_names = FALSE keeps the input's column names", {
  data <- make_essence_data(n = 20L)
  result <- suppressMessages(
    review_facility_ed_visits(
      data, return_format = "all", clean_names = FALSE
    )
  )
  expect_true("Hospital" %in% names(result))
  expect_true("FacilityType" %in% names(result))
  expect_false("facility_type" %in% names(result))
  expect_true(".outlier_flag" %in% names(result))
})

make_dropout_data <- function() {
  steady <- tibble::tibble(
    HospitalName = "Steady", Hospital = 1L, FacilityType = "Emergency Care",
    Date = rep(as.Date("2026-01-01") + 0:29, each = 10L)
  )
  dropout <- tibble::tibble(
    HospitalName = "Dropout", Hospital = 2L, FacilityType = "Emergency Care",
    Date = rep(as.Date("2026-01-01") + 0:9, each = 10L)
  )
  others <- lapply(3:6, function(i) {
    tibble::tibble(
      HospitalName = paste0("Other", i), Hospital = i,
      FacilityType = "Emergency Care",
      Date = rep(as.Date("2026-01-01") + 0:29, each = 10L)
    )
  })
  dplyr::bind_rows(c(list(steady, dropout), others))
}

test_that("visits_per_day divides by the pull's days, so a mid-pull dropout scores lower", {
  result <- suppressMessages(
    review_facility_ed_visits(
      make_dropout_data(), date_col = Date, return_format = "all"
    )
  )
  steady  <- dplyr::filter(result, hospital == 1L)
  dropout <- dplyr::filter(result, hospital == 2L)
  expect_equal(steady$visits_per_day, 10)
  expect_equal(dropout$visits_per_day, 100 / 30)
  # the days the facility actually sent data are still reported
  expect_equal(dropout$n_days, 10L)
})

test_that("a mid-pull dropout is flagged as a low outlier under method = 'iqr'", {
  result <- suppressMessages(
    review_facility_ed_visits(
      make_dropout_data(), date_col = Date, method = "iqr"
    )
  )
  expect_equal(result$hospital, 2L)
  expect_equal(result$.outlier_direction, "low")
})

test_that(".outlier_method records which criterion fired, not the requested method", {
  # One facility far above 19 near-identical ones is caught by both criteria
  counts <- c(rep(100L, 19L), 400L)
  data <- dplyr::bind_rows(lapply(seq_along(counts), function(i) {
    tibble::tibble(
      HospitalName = paste0("F", i), Hospital = i,
      FacilityType = "Emergency Care", Date = as.Date("2026-01-01")
    )[rep(1L, counts[i]), ]
  }))
  result <- suppressMessages(
    review_facility_ed_visits(data, method = "both", return_format = "all")
  )
  flagged <- dplyr::filter(result, .outlier_flag)
  expect_true(all(
    flagged$.outlier_method %in% c("percentile", "iqr", "percentile+iqr")
  ))
  expect_equal(
    dplyr::filter(result, hospital == 20L)$.outlier_method, "percentile+iqr"
  )
  only_pct <- suppressMessages(
    review_facility_ed_visits(data, method = "percentile", return_format = "all")
  )
  expect_true(all(
    only_pct$.outlier_method[only_pct$.outlier_flag] == "percentile"
  ))
  expect_true(all(is.na(only_pct$.outlier_method[!only_pct$.outlier_flag])))
})

test_that("outlier_method_label() treats a missing threshold as not firing", {
  expect_equal(
    outlier_method_label(
      x = c(1, 50, 100), pct_low = 5, pct_high = 90,
      iqr_low = NA_real_, iqr_high = NA_real_
    ),
    c("percentile", NA, "percentile")
  )
})
