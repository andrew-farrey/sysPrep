
# test-assign_treating_geography.R ----
test_that("assign_treating_geography() reassigns out-of-state Region", {
  data <- make_essence_data(n = 10L)
  result <- assign_treating_geography(data, geography = "region")
  # Out-of-state rows should now have KY_ regions
  expect_true(all(
    stringr::str_starts(result$region, "KY_") | is.na(result$region)
  ))
})

test_that("assign_treating_geography() leaves in-state visits unchanged", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(Region = "KY_Jefferson", ZipCode = "40201")
  result <- assign_treating_geography(data)
  expect_false(any(result$.out_of_state))
})

test_that("assign_treating_geography() handles OTHER_REGION", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(
      Region  = "OTHER_REGION",
      ZipCode = NA_character_
    )
  result <- assign_treating_geography(data, geography = "region")
  expect_true(all(result$.out_of_state))
  expect_false(any(result$region == "OTHER_REGION", na.rm = TRUE))
})

test_that("assign_treating_geography() handles site-prefixed unknown residence (e.g. KY_UNKNOWN)", {
  # Regression test: "KY_UNKNOWN" carries the site prefix, so a naive
  # str_starts(region, "KY_") check alone would misclassify it as in-state
  # and leave it unreassigned -- this must be caught explicitly.
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(
      Region  = "KY_UNKNOWN",
      ZipCode = NA_character_
    )
  result <- assign_treating_geography(data, geography = "region")
  expect_true(all(result$.out_of_state))
  expect_false(any(result$region == "KY_UNKNOWN", na.rm = TRUE))
})

test_that("assign_treating_geography() preserve_original_geographies adds columns", {
  data <- make_essence_data(n = 5L)
  result <- assign_treating_geography(
    data,
    geography                     = "region",
    preserve_original_geographies = TRUE
  )
  expect_true("original_region" %in% names(result))
})

test_that("assign_treating_geography() skips zip gracefully when HospitalZip absent", {
  data <- make_essence_data(n = 5L) |>
    dplyr::select(-HospitalZip, -ZipCode)
  expect_message(
    assign_treating_geography(data, geography = c("region", "zip")),
    "Zip geography skipped"
  )
})

test_that("assign_treating_geography() accepts non-KY site prefix", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(Region = "OH_Hamilton")
  result <- assign_treating_geography(data, site = "OH", geography = "region")
  expect_false(any(result$.out_of_state))
})

test_that("assign_treating_geography() informs when HospitalRegion absent and skips region", {
  data <- make_essence_data(n = 5L) |> dplyr::select(-HospitalRegion)
  # Use default geography = c("region","zip") so zip still works after
  # region is skipped -- avoids a "no geography" warning swallowing the message
  expect_message(
    assign_treating_geography(data),
    "HospitalRegion"
  )
})

test_that("assign_treating_geography() informs when HospitalZip absent but ZipCode present", {
  data <- make_essence_data(n = 5L) |> dplyr::select(-HospitalZip)
  # Use default geography = c("region","zip") so region still works
  expect_message(
    assign_treating_geography(data),
    "HospitalZip"
  )
})

test_that("assign_treating_geography() aborts when Region column absent", {
  data <- make_essence_data(n = 5L) |> dplyr::select(-Region)
  expect_error(
    assign_treating_geography(data),
    "`Region`"
  )
})

test_that("assign_treating_geography() warns when no geography can be processed", {
  data <- make_essence_data(n = 5L) |>
    dplyr::select(-HospitalRegion, -HospitalZip)
  expect_warning(
    suppressMessages(assign_treating_geography(data)),
    "No geography types could be processed"
  )
})

test_that("assign_treating_geography() preserve_original_geographies adds original_zip_code", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(Region = "OTHER_REGION", ZipCode = "40202")
  result <- suppressMessages(
    assign_treating_geography(
      data,
      geography                     = c("region", "zip"),
      preserve_original_geographies = TRUE
    )
  )
  expect_true("original_zip_code" %in% names(result))
})

test_that("assign_treating_geography() informs on empty data frame input", {
  data <- dplyr::filter(make_essence_data(n = 5L), FALSE)
  expect_message(
    assign_treating_geography(data),
    "No rows"
  )
})

test_that("assign_treating_geography() clean_names = FALSE returns data frame", {
  data   <- make_essence_data(n = 5L)
  result <- suppressMessages(assign_treating_geography(data, clean_names = FALSE))
  expect_s3_class(result, "data.frame")
})

test_that("assign_treating_geography() verbose = FALSE suppresses informational messages", {
  data <- make_essence_data(n = 10L)
  expect_no_message(assign_treating_geography(data, verbose = FALSE))
})

test_that("assign_treating_geography() warns on no geography processed regardless of verbose", {
  data <- make_essence_data(n = 5L) |>
    dplyr::select(-HospitalRegion, -HospitalZip)
  expect_warning(
    suppressMessages(assign_treating_geography(data, verbose = FALSE)),
    "No geography types could be processed"
  )
})
