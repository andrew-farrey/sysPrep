
# test-classify_duplicates.R ----

test_that("classify_duplicates() returns list with required components", {
  data <- make_data_with_dups()
  result <- classify_duplicates(data)
  expect_named(result, c("duplicate_ids", "visit_groups", "by_facility", "overall"))
})

test_that("classify_duplicates() identifies visit_date_change correctly", {
  data <- make_data_with_dups()
  result <- classify_duplicates(data, return_format = "tibble")
  date_change_rows <- dplyr::filter(result, dup_type == "visit_date_change")
  expect_equal(nrow(date_change_rows), 1L)
})

test_that("classify_duplicates() identifies pid_change correctly", {
  data <- make_data_with_dups()
  result <- classify_duplicates(data, return_format = "tibble")
  pid_rows <- dplyr::filter(result, dup_type == "pid_change")
  expect_equal(nrow(pid_rows), 1L)
})

test_that("classify_duplicates() return_format = 'tibble' returns a tibble", {
  data <- make_data_with_dups()
  result <- classify_duplicates(data, return_format = "tibble")
  expect_s3_class(result, "data.frame")
  expect_true("dup_type" %in% names(result))
})

test_that("classify_duplicates() aborts with informative message for missing columns", {
  data <- make_essence_data(include_biosense = FALSE)
  expect_error(classify_duplicates(data), "required columns are missing")
})

test_that("classify_duplicates() informs when c_patient_class absent", {
  data <- make_data_with_dups()
  expect_message(classify_duplicates(data), "c_patient_class")
})

test_that("classify_duplicates() assigns no_duplication to non-duplicated rows", {
  data   <- make_data_with_dups()
  result <- classify_duplicates(data, return_format = "tibble")
  no_dup <- dplyr::filter(result, dup_type == "no_duplication")
  # 10 base visits, 3 have dups -> 7 unique-only visits
  expect_equal(nrow(no_dup), 7L)
})

test_that("classify_duplicates() assigns type_unknown when rows differ only in C_BioSense_ID", {
  # Standard dup: same Date and C_Unique_Patient_ID, only C_BioSense_ID differs
  data   <- make_data_with_dups()
  result <- classify_duplicates(data, return_format = "tibble")
  unknown_rows <- dplyr::filter(result, dup_type == "type_unknown")
  expect_equal(nrow(unknown_rows), 1L)
})

test_that("classify_duplicates() detects compound visit_date_change+pid_change", {
  base <- make_essence_data(n = 5L)
  compound_dup <- base[1L, ] |>
    dplyr::mutate(
      C_BioSense_ID       = "BS_COMPOUND",
      Date                = Date + 1L,
      C_Unique_Patient_ID = "P_COMPOUND"
    )
  data   <- dplyr::bind_rows(base, compound_dup)
  result <- classify_duplicates(data, return_format = "tibble")
  compound_row <- dplyr::filter(result, visit_id == base$Visit_ID[1L])
  expect_equal(compound_row$dup_type, "visit_date_change+pid_change")
})

test_that("classify_duplicates() $overall has n and percent columns", {
  data   <- make_data_with_dups()
  result <- classify_duplicates(data)
  expect_true("n"       %in% names(result$overall))
  expect_true("percent" %in% names(result$overall))
  expect_s3_class(result$overall, "data.frame")
})

test_that("classify_duplicates() $by_facility is wide with facility column and n_duplicated_total", {
  data   <- make_data_with_dups()
  result <- classify_duplicates(data)
  expect_true("n_duplicated_total" %in% names(result$by_facility))
  # Wide format: facility column must be present
  expect_true("hospital_name" %in% names(result$by_facility))
})

test_that("classify_duplicates() result has class essence_dup_classified", {
  data   <- make_data_with_dups()
  result <- classify_duplicates(data)
  expect_s3_class(result, "essence_dup_classified")
})

test_that("print.essence_dup_classified() runs without error", {
  data   <- make_data_with_dups()
  result <- classify_duplicates(data)
  expect_output(print(result))
})

test_that("classify_duplicates() aborts when Date or C_Unique_Patient_ID missing", {
  data <- make_essence_data(n = 5L, include_pid = FALSE) |>
    dplyr::select(-Date)
  expect_error(classify_duplicates(data), "required columns are missing")
})

test_that("classify_duplicates() counts n_patient_classes when c_patient_class present", {
  data <- make_data_with_dups() |>
    dplyr::mutate(c_patient_class = "E")
  result <- suppressMessages(classify_duplicates(data))
  expect_s3_class(result, "essence_dup_classified")
  expect_true(all(result$visit_groups$n_patient_classes >= 1L))
})

test_that("classify_duplicates() verbose = FALSE suppresses c_patient_class message", {
  data <- make_data_with_dups()
  expect_no_message(classify_duplicates(data, verbose = FALSE))
})

test_that("classify_duplicates() aborts on missing required columns regardless of verbose", {
  data <- make_essence_data(include_biosense = FALSE)
  expect_error(classify_duplicates(data, verbose = FALSE), "required columns are missing")
})
