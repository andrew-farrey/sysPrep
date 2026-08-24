
# test-assign_treating_geography.R ----
test_that("assign_treating_geography() writes region_hybrid by default, leaving region untouched", {
  data <- make_essence_data(n = 10L)
  result <- suppressMessages(assign_treating_geography(data, new_zip_col = NULL))

  # region_hybrid reflects HospitalRegion for out-of-state rows, and the
  # original region value (which is always KY_-prefixed in the fixture) for
  # in-state rows -- so it should always be KY_-prefixed
  expect_true(all(
    stringr::str_starts(result$region_hybrid, "KY_") | is.na(result$region_hybrid)
  ))

  # region itself must be completely unmodified -- still contains the
  # original out-of-state/OTHER_REGION values the fixture generated
  expect_equal(result$region, data$Region)
})

test_that("assign_treating_geography() leaves in-state visits unchanged", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(Region = "KY_Jefferson", ZipCode = "40201")
  result <- suppressMessages(assign_treating_geography(data))
  expect_false(any(result$.out_of_state))
})

test_that("assign_treating_geography() handles OTHER_REGION", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(
      Region  = "OTHER_REGION",
      ZipCode = NA_character_
    )
  result <- suppressMessages(assign_treating_geography(data, new_zip_col = NULL))
  expect_true(all(result$.out_of_state))
  expect_false(any(result$region_hybrid == "OTHER_REGION", na.rm = TRUE))
  # source column is untouched by default
  expect_true(all(result$region == "OTHER_REGION"))
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
  result <- suppressMessages(assign_treating_geography(data, new_zip_col = NULL))
  expect_true(all(result$.out_of_state))
  expect_false(any(result$region_hybrid == "KY_UNKNOWN", na.rm = TRUE))
})

test_that("assign_treating_geography() preserve_original_geographies has no effect in default (new-column) mode", {
  data <- make_essence_data(n = 5L)
  result <- suppressMessages(
    assign_treating_geography(
      data,
      new_zip_col                   = NULL,
      preserve_original_geographies = TRUE
    )
  )
  # No original_region column -- region itself is already untouched, so
  # preserving it separately would be redundant
  expect_false("original_region" %in% names(result))
})

test_that("assign_treating_geography() preserve_original_geographies adds original_region in overwrite mode", {
  data <- make_essence_data(n = 5L)
  result <- suppressMessages(
    assign_treating_geography(
      data,
      new_region_col                = "region",
      new_zip_col                   = NULL,
      overwrite                     = TRUE,
      preserve_original_geographies = TRUE
    )
  )
  expect_true("original_region" %in% names(result))
})

test_that("assign_treating_geography() new_zip_col = NULL skips zip entirely", {
  data <- make_essence_data(n = 5L)
  result <- suppressMessages(assign_treating_geography(data, new_zip_col = NULL))
  expect_false("zip_code_hybrid" %in% names(result))
})

test_that("assign_treating_geography() new_region_col = NULL skips region entirely", {
  data <- make_essence_data(n = 5L)
  result <- suppressMessages(assign_treating_geography(data, new_region_col = NULL))
  expect_false("region_hybrid" %in% names(result))
  expect_true("zip_code_hybrid" %in% names(result))
})

test_that("assign_treating_geography() aborts when new_region_col collides with an existing column and overwrite = FALSE", {
  data <- make_essence_data(n = 5L)
  expect_error(
    assign_treating_geography(data, new_region_col = "region", new_zip_col = NULL),
    "overwrite"
  )
})

test_that("assign_treating_geography() overwrite = TRUE allows overwriting region in place", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(Region = "OTHER_REGION")
  result <- suppressMessages(
    assign_treating_geography(
      data,
      new_region_col = "region",
      new_zip_col    = NULL,
      overwrite      = TRUE
    )
  )
  expect_false(any(result$region == "OTHER_REGION"))
})

test_that("assign_treating_geography() aborts when new_region_col collides with the .out_of_state marker column", {
  data <- make_essence_data(n = 5L)
  expect_error(
    assign_treating_geography(data, new_region_col = ".out_of_state", new_zip_col = NULL),
    "\\.out_of_state"
  )
})

test_that("assign_treating_geography() skips zip gracefully when HospitalZip absent", {
  data <- make_essence_data(n = 5L) |>
    dplyr::select(-HospitalZip, -ZipCode)
  expect_message(
    assign_treating_geography(data),
    "Zip geography skipped"
  )
})

test_that("assign_treating_geography() accepts non-KY site prefix", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(Region = "OH_Hamilton")
  result <- suppressMessages(
    assign_treating_geography(data, site = "OH", new_zip_col = NULL)
  )
  expect_false(any(result$.out_of_state))
})

test_that("assign_treating_geography() informs when HospitalRegion absent and skips region", {
  data <- make_essence_data(n = 5L) |> dplyr::select(-HospitalRegion)
  expect_message(
    assign_treating_geography(data),
    "HospitalRegion"
  )
})

test_that("assign_treating_geography() informs when HospitalZip absent but ZipCode present", {
  data <- make_essence_data(n = 5L) |> dplyr::select(-HospitalZip)
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

test_that("assign_treating_geography() preserve_original_geographies adds original_zip_code in overwrite mode", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(Region = "OTHER_REGION", ZipCode = "40202")
  result <- suppressMessages(
    assign_treating_geography(
      data,
      new_region_col                = "region",
      new_zip_col                   = "zip_code",
      overwrite                     = TRUE,
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
