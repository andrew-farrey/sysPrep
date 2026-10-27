
# test-filter_care_setting.R ----
make_mixed_facility_data <- function() {
  d <- make_essence_data(n = 15L)
  # Add non-ED rows
  non_ed <- d[1:3, ] |>
    dplyr::mutate(
      HospitalName = c("Westside Clinic", "Cardiology Group", "Pain Center"),
      FacilityType = c("Primary Care", "Medical Specialty", "Medical Specialty")
    )
  dplyr::bind_rows(d, non_ed)
}

test_that("filter_care_setting() removes non-ED facility types", {
  data <- make_mixed_facility_data()
  result <- filter_care_setting(data)
  expect_false(any(result$facility_type %in% c("Primary Care", "Medical Specialty")))
})

test_that("filter_care_setting() retains Emergency Care rows", {
  data <- make_mixed_facility_data()
  result <- filter_care_setting(data)
  expect_true(all(
    result$facility_type %in%
      c("emergency_care", "inpatient_practice_setting",
        "Emergency Care", "Inpatient Practice Setting")
  ))
})

test_that("filter_care_setting() fix_facility_type_vector corrects FSED type", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(
      HospitalName = dplyr::if_else(
        dplyr::row_number() == 1L,
        "Hillside FSED",
        HospitalName
      ),
      FacilityType = dplyr::if_else(
        HospitalName == "Hillside FSED",
        "Urgent Care",
        FacilityType
      )
    )
  result <- filter_care_setting(
    data,
    fix_facility_type_vector = "Hillside FSED"
  )
  expect_gt(nrow(result), 0L)
  # FSED should be retained (corrected to Emergency Care)
  expect_true(
    "hillside_fsed" %in% result$hospital_name |
      "Hillside FSED" %in% result$hospital_name
  )
})

test_that("filter_care_setting() dry_run returns preview tibble", {
  data <- make_mixed_facility_data()
  result <- filter_care_setting(data, dry_run = TRUE)
  expect_s3_class(result, "data.frame")
  expect_true(".would_keep" %in% names(result))
  expect_true("corrected_facility_type" %in% names(result))
})

test_that("filter_care_setting() warns on empty result", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(FacilityType = "Primary Care")
  expect_warning(
    filter_care_setting(data),
    "No rows remain"
  )
})

test_that("filter_care_setting() empty-result warning lists the types present", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(FacilityType = "Primary Care")
  w <- expect_warning(filter_care_setting(data), "No rows remain")
  expect_match(conditionMessage(w), "Primary Care", fixed = TRUE)
  expect_match(conditionMessage(w), "Emergency Care", fixed = TRUE)
  expect_no_match(conditionMessage(w), "letter case")
})

test_that("filter_care_setting() empty-result warning names a case-only mismatch", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(FacilityType = "emergency care")
  w <- expect_warning(filter_care_setting(data), "No rows remain")
  expect_match(conditionMessage(w), "\"emergency care\"", fixed = TRUE)
  expect_match(conditionMessage(w), "letter case", fixed = TRUE)
})

test_that("filter_care_setting() empty-result warning handles all-missing types", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(FacilityType = NA_character_)
  w <- expect_warning(filter_care_setting(data), "No rows remain")
  expect_match(conditionMessage(w), "all missing", fixed = TRUE)
})

test_that("filter_care_setting() says an empty input has nothing to filter", {
  data <- make_essence_data(n = 5L)[0L, ]
  w <- expect_warning(filter_care_setting(data), "No rows remain")
  expect_match(conditionMessage(w), "has no rows", fixed = TRUE)
  expect_no_match(conditionMessage(w), "keep_types")
})

test_that("filter_care_setting() warns on unmatched fix_facility_type_vector names during dry_run", {
  data <- make_essence_data(n = 5L)
  expect_warning(
    filter_care_setting(
      data,
      fix_facility_type_vector = "Nonexistent FSED",
      dry_run                  = TRUE
    ),
    "not found in data"
  )
})

test_that("filter_care_setting() does not warn on unmatched fix_facility_type_vector names outside dry_run", {
  data <- make_essence_data(n = 5L)
  expect_no_warning(
    filter_care_setting(data, fix_facility_type_vector = "Nonexistent FSED")
  )
})

test_that("filter_care_setting() fix_facility_type_regex corrects matching facilities and warns", {
  data <- make_essence_data(n = 10L) |>
    dplyr::mutate(
      HospitalName = dplyr::if_else(
        dplyr::row_number() <= 2L,
        paste0("Metro FSED ", dplyr::row_number()),
        HospitalName
      ),
      FacilityType = dplyr::if_else(
        stringr::str_detect(HospitalName, "FSED"),
        "Urgent Care",
        FacilityType
      )
    )
  expect_warning(
    result <- filter_care_setting(data, fix_facility_type_regex = "FSED"),
    "matched by `fix_facility_type_regex`"
  )
  expect_true(any(stringr::str_detect(result$hospital_name, "FSED")))
})

test_that("filter_care_setting() clean_names = FALSE keeps the input's column names", {
  data <- make_essence_data(n = 5L)
  result <- suppressMessages(filter_care_setting(data, clean_names = FALSE))
  expect_s3_class(result, "data.frame")
  expect_identical(names(result), names(data))
})

test_that("filter_care_setting() leaves a row with a missing facility name unchanged under a regex correction", {
  data <- tibble::tibble(
    HospitalName = c("Hillside FSED", NA, "General"),
    Hospital     = c(1L, 2L, 3L),
    FacilityType = c("Urgent Care", "Emergency Care", "Emergency Care")
  )
  expect_warning(
    result <- suppressMessages(
      filter_care_setting(data, fix_facility_type_regex = "FSED")
    ),
    "1 facility/facilities matched"
  )
  # all three rows survive: the FSED is corrected, and the NA-name row keeps
  # its own type instead of having it overwritten with NA and being dropped
  expect_equal(nrow(result), 3L)
  expect_false(anyNA(result$facility_type))
})

test_that("filter_care_setting() verbose = FALSE suppresses dropped-types message", {
  data <- make_mixed_facility_data()
  expect_no_message(filter_care_setting(data, verbose = FALSE))
})

test_that("filter_care_setting() warns on empty result regardless of verbose", {
  data <- make_essence_data(n = 5L) |>
    dplyr::mutate(FacilityType = "Primary Care")
  expect_warning(
    filter_care_setting(data, verbose = FALSE),
    "No rows remain"
  )
})

test_that("filter_care_setting() fix_facility_id_vector corrects matching facility type", {
  data <- make_essence_data(n = 10L) |>
    dplyr::mutate(
      FacilityType = dplyr::if_else(Hospital == 1001L, "Urgent Care", FacilityType)
    )
  result <- filter_care_setting(data, fix_facility_id_vector = 1001L)
  expect_true(all(
    result$facility_type[result$hospital == 1001L] == "Emergency Care" |
      result$facility_type[result$hospital == 1001L] == "emergency_care"
  ))
})

test_that("filter_care_setting() fix_facility_id_vector accepts character IDs matching numeric column", {
  data <- make_essence_data(n = 10L) |>
    dplyr::mutate(
      FacilityType = dplyr::if_else(Hospital == 1001L, "Urgent Care", FacilityType)
    )
  result <- filter_care_setting(data, fix_facility_id_vector = "1001")
  expect_gt(nrow(dplyr::filter(result, hospital == 1001L)), 0L)
})

test_that("filter_care_setting() matches round numeric IDs against text Hospital values", {
  # as.character(100000) is "1e+05", which would not equal "100000"
  data <- tibble::tibble(
    HospitalName = c("A", "B"), Hospital = c("100000", "300000"),
    FacilityType = "Urgent Care"
  )
  result <- suppressMessages(
    filter_care_setting(data, fix_facility_id_vector = c(100000, 300000))
  )
  expect_equal(nrow(result), 2L)
})

test_that("filter_care_setting() never warns on unmatched fix_facility_id_vector IDs", {
  data <- make_essence_data(n = 5L)
  expect_no_warning(
    filter_care_setting(data, fix_facility_id_vector = 9999L, dry_run = TRUE)
  )
})

test_that("filter_care_setting() informs when facility_id_col absent and no ID vector supplied", {
  data <- make_essence_data(n = 5L) |> dplyr::select(-Hospital)
  expect_message(
    filter_care_setting(data),
    "facility_id_col"
  )
})

test_that("filter_care_setting() aborts when fix_facility_id_vector supplied but facility_id_col absent", {
  data <- make_essence_data(n = 5L) |> dplyr::select(-Hospital)
  expect_error(
    filter_care_setting(data, fix_facility_id_vector = 1001L),
    "facility_id_col"
  )
})

test_that("filter_care_setting() excludes ID-corrected facility from regex candidate warning", {
  data <- make_essence_data(n = 10L) |>
    dplyr::mutate(
      HospitalName = dplyr::if_else(Hospital == 1001L, "Metro FSED", HospitalName),
      FacilityType = dplyr::if_else(Hospital == 1001L, "Urgent Care", FacilityType)
    )
  # Only the ID-corrected facility's name matches "FSED"; if the exclusion
  # logic works, already_corrected removes it as a regex candidate entirely,
  # so no facility remains to trigger the regex warning.
  expect_no_warning(
    result <- suppressMessages(
      filter_care_setting(
        data,
        fix_facility_id_vector  = 1001L,
        fix_facility_type_regex = "FSED"
      )
    )
  )
  expect_gt(nrow(dplyr::filter(result, hospital == 1001L)), 0L)
})

test_that("filter_care_setting() dry_run preview includes facility_id column", {
  data <- make_essence_data(n = 5L)
  result <- filter_care_setting(data, dry_run = TRUE)
  expect_true("facility_id" %in% names(result))
})
