
# test-assign_facility_geography.R ----

test_that("assign_facility_geography() sets .facility_geography = TRUE for all rows", {
  data   <- make_essence_data(n = 10L)
  result <- suppressMessages(assign_facility_geography(data))
  expect_true(all(result$.facility_geography))
  expect_equal(nrow(result), 10L)
})

test_that("assign_facility_geography() overwrites region with hospital_region for all rows", {
  data        <- make_essence_data(n = 10L)
  result      <- suppressMessages(assign_facility_geography(data))
  data_clean  <- janitor::clean_names(data)
  expect_equal(result$region, data_clean$hospital_region)
})

test_that("assign_facility_geography() reassigns rows regardless of original Region value", {
  data <- make_essence_data(n = 20L)
  # make_essence_data includes OTHER_REGION rows in Region column
  data_clean <- janitor::clean_names(data)
  has_other  <- any(data_clean$region == "OTHER_REGION")
  expect_true(has_other)  # fixture should include at least one OTHER_REGION

  result <- suppressMessages(assign_facility_geography(data))
  # After reassignment, no OTHER_REGION should remain in region
  expect_false(any(result$region == "OTHER_REGION"))
  # All region values should match hospital_region
  expect_equal(result$region, result$hospital_region)
})

test_that("assign_facility_geography() adds original_region when preserve = TRUE", {
  data   <- make_essence_data(n = 10L)
  result <- suppressMessages(
    assign_facility_geography(data, preserve_original_geographies = TRUE)
  )
  expect_true("original_region" %in% names(result))
  # original_region should contain the pre-reassignment values
  data_clean <- janitor::clean_names(data)
  expect_equal(result$original_region, data_clean$region)
})

test_that("assign_facility_geography() skips zip gracefully when HospitalZip absent", {
  data <- make_essence_data(n = 5L) |>
    dplyr::select(-HospitalZip)
  expect_message(
    assign_facility_geography(data),
    "HospitalZip"
  )
  result <- suppressMessages(assign_facility_geography(data))
  # Region should still be reassigned
  expect_true(".facility_geography" %in% names(result))
  data_clean <- janitor::clean_names(data)
  expect_equal(result$region, data_clean$hospital_region)
})

test_that("assign_facility_geography() clean_names = FALSE returns data frame with expected columns", {
  data   <- make_essence_data(n = 5L)
  result <- suppressMessages(assign_facility_geography(data, clean_names = FALSE))
  expect_s3_class(result, "data.frame")
  expect_true(".facility_geography" %in% names(result))
})

test_that("assign_facility_geography() informs when Region column absent", {
  data <- make_essence_data(n = 5L) |> dplyr::select(-Region)
  expect_message(
    assign_facility_geography(data),
    "Region geography skipped"
  )
})

test_that("assign_facility_geography() informs when HospitalRegion absent", {
  data <- make_essence_data(n = 5L) |> dplyr::select(-HospitalRegion)
  expect_message(
    assign_facility_geography(data),
    "HospitalRegion"
  )
})

test_that("assign_facility_geography() informs when ZipCode absent", {
  data <- make_essence_data(n = 5L) |> dplyr::select(-ZipCode)
  expect_message(
    assign_facility_geography(data),
    "ZipCode"
  )
})

test_that("assign_facility_geography() warns when no geography can be processed", {
  data <- make_essence_data(n = 5L) |>
    dplyr::select(-Region, -ZipCode)
  expect_warning(
    suppressMessages(assign_facility_geography(data)),
    "No geography types could be processed"
  )
})

test_that("assign_facility_geography() informs on empty data frame input", {
  data <- dplyr::filter(make_essence_data(n = 5L), FALSE)
  expect_message(
    assign_facility_geography(data),
    "No rows"
  )
})

test_that("assign_facility_geography() verbose = FALSE suppresses informational messages", {
  data <- make_essence_data(n = 10L)
  expect_no_message(assign_facility_geography(data, verbose = FALSE))
})

test_that("assign_facility_geography() warns on no geography processed regardless of verbose", {
  data <- make_essence_data(n = 5L) |>
    dplyr::select(-Region, -ZipCode)
  expect_warning(
    suppressMessages(assign_facility_geography(data, verbose = FALSE)),
    "No geography types could be processed"
  )
})
