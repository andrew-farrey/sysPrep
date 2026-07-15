
# test-dedupe.R ----
test_that("dedupe() returns one row per facility x visit_id by default", {
  data <- make_data_with_dups()
  result <- dedupe(data)
  expect_equal(
    nrow(result),
    dplyr::n_distinct(data$HospitalName, data$Visit_ID)
  )
})

test_that("dedupe() keep = 'first' retains first row in original order", {
  data <- make_data_with_dups()
  result <- dedupe(data, keep = "first")
  expect_equal(nrow(result), dplyr::n_distinct(data$HospitalName, data$Visit_ID))
})

test_that("dedupe() keep = 'last' retains last row", {
  data <- make_data_with_dups()
  result <- dedupe(data, keep = "last")
  expect_equal(nrow(result), dplyr::n_distinct(data$HospitalName, data$Visit_ID))
})

test_that("dedupe() keep = 'most_complete' retains row with fewest NAs", {
  data <- make_essence_data(n = 4L)
  # Add a duplicate where first row has an NA and second is complete
  data[1L, "C_BioSense_ID"] <- NA_character_
  dup <- data[1L, ]
  dup$C_BioSense_ID <- "BS9999999999"
  data <- dplyr::bind_rows(data, dup)

  result <- dedupe(data, keep = "most_complete")
  # The complete row (no NAs) should be retained for the duplicated visit
  dup_row <- result |>
    dplyr::filter(visit_id == data$Visit_ID[1L])
  expect_false(is.na(dup_row$c_bio_sense_id))
})

test_that("dedupe() accepts post-clean_names() column names", {
  data <- janitor::clean_names(make_essence_data())
  expect_no_error(dedupe(data, facility_col = hospital_name, visit_col = visit_id))
})

test_that("dedupe() order_by + keep = 'most_complete' issues a warning", {
  data <- make_data_with_dups()
  expect_warning(
    dedupe(data, order_by = Date, keep = "most_complete"),
    "`order_by` is ignored"
  )
})

test_that("dedupe() order_by = Date retains the earliest-dated row with keep = 'first'", {
  base <- make_essence_data(n = 3L)
  dup  <- base[1L, ] |> dplyr::mutate(Date = Date + 2L)
  data <- dplyr::bind_rows(base, dup)
  result  <- dedupe(data, order_by = Date, keep = "first")
  dup_row <- dplyr::filter(result, visit_id == base$Visit_ID[1L])
  expect_equal(dup_row$date, base$Date[1L])
})

test_that("dedupe() returns snake_case columns by default", {
  data <- make_essence_data()
  result <- dedupe(data)
  expect_true(all(names(result) == janitor::make_clean_names(names(result))))
})

test_that("dedupe() returns original column names when clean_names = FALSE", {
  data <- make_essence_data()
  result <- dedupe(data, clean_names = FALSE)
  expect_true("HospitalName" %in% names(result))
})

test_that("dedupe() errors informatively for missing column", {
  data <- make_essence_data()
  expect_error(
    dedupe(data, facility_col = NonExistentColumn),
    "not found in data"
  )
})

test_that("dedupe() is pipeable", {
  data <- make_data_with_dups()
  expect_no_error(
    data |> dedupe() |> dplyr::filter(!is.na(visit_id))
  )
})
