# Argument validation and error attribution ----
# Every exported function checks its arguments up front and reports problems
# against the function the user actually called, never against an internal
# helper.

error_call_name <- function(expr) {
  err <- tryCatch(expr, error = identity)
  expect_s3_class(err, "rlang_error")
  rlang::call_name(err$call)
}

test_that("every exported function rejects a non-data-frame `data`", {
  expect_error(dedupe(1:3), "`data` must be a data frame")
  expect_error(summarize_duplicates(list(a = 1)), "`data` must be a data frame")
  expect_error(classify_duplicates("x"), "`data` must be a data frame")
  expect_error(filter_care_setting(NULL), "`data` must be a data frame")
  expect_error(review_facility_ed_visits(1), "`data` must be a data frame")
  expect_error(assign_treating_geography(1), "`data` must be a data frame")
  expect_error(assign_facility_geography(1), "`data` must be a data frame")
})

test_that("link_encounters() names the offending data argument", {
  expect_error(
    link_encounters(1, essence_inp_raw),
    "`ed_data` must be a data frame"
  )
  expect_error(
    link_encounters(essence_ed_raw, "x"),
    "`inpatient_admission_data` must be a data frame"
  )
})

test_that("errors are attributed to the exported function, not an internal helper", {
  expect_identical(
    error_call_name(dedupe(essence_raw, visit_col = NoSuchColumn)),
    "dedupe"
  )
  expect_identical(
    error_call_name(summarize_duplicates(essence_raw, facility_col = Nope)),
    "summarize_duplicates"
  )
  expect_identical(
    error_call_name(
      assign_treating_geography(essence_raw, new_region_col = "hospital_region")
    ),
    "assign_treating_geography"
  )
  expect_identical(error_call_name(dedupe(1:3)), "dedupe")
})

test_that("a missing column error lists what is available", {
  err <- tryCatch(dedupe(essence_raw, visit_col = NoSuchColumn), error = identity)
  expect_match(conditionMessage(err), "Column `NoSuchColumn` not found in data")
  expect_match(conditionMessage(err), "Available columns: hospital_name")
})

test_that("logical switches must be a single TRUE or FALSE", {
  expect_error(dedupe(essence_raw, clean_names = NA), "`clean_names` must be")
  expect_error(dedupe(essence_raw, clean_names = c(TRUE, FALSE)), "length 2")
  expect_error(classify_duplicates(essence_raw, verbose = "yes"), "`verbose`")
  expect_error(filter_care_setting(essence_raw, dry_run = NA), "`dry_run`")
  expect_error(
    assign_facility_geography(essence_raw, overwrite = NULL),
    "`overwrite` must be"
  )
  expect_error(
    review_facility_ed_visits(essence_raw, group_by_type = 1),
    "`group_by_type` must be"
  )
})

test_that("choice arguments report the argument name and valid values", {
  expect_error(dedupe(essence_raw, keep = "middle"), "`keep` must be one of")
  expect_error(
    classify_duplicates(essence_raw, return_format = "x"),
    "`return_format` must be one of"
  )
  expect_error(
    review_facility_ed_visits(essence_raw, method = "z"),
    "`method` must be one of"
  )
})

test_that("dedupe() still defaults to keep = 'first' and advertises its choices", {
  # formals()$keep is the call `c("first", "last", "most_complete")`
  expect_identical(
    as.character(formals(dedupe)$keep)[-1L],
    c("first", "last", "most_complete")
  )
  expect_identical(
    dedupe(essence_raw),
    dedupe(essence_raw, keep = "first")
  )
})

# review_facility_ed_visits() ----

test_that("review_facility_ed_visits() validates percentile and IQR arguments", {
  expect_error(
    review_facility_ed_visits(essence_raw, percentile_low = -0.1),
    "`percentile_low` must be a single number between 0 and 1"
  )
  expect_error(
    review_facility_ed_visits(essence_raw, percentile_high = 95),
    "`percentile_high` must be a single number between 0 and 1"
  )
  expect_error(
    review_facility_ed_visits(
      essence_raw, percentile_low = 0.9, percentile_high = 0.1
    ),
    "`percentile_low` must be less than `percentile_high`"
  )
  expect_error(
    review_facility_ed_visits(essence_raw, iqr_multiplier = -1),
    "`iqr_multiplier` must be a single number"
  )
  expect_error(
    review_facility_ed_visits(essence_raw, percentile_low = NA_real_),
    "`percentile_low` must be a single number"
  )
})

# filter_care_setting() ----

test_that("filter_care_setting() validates its character arguments", {
  expect_error(
    filter_care_setting(essence_raw, keep_types = 5),
    "`keep_types` must be a character vector"
  )
  expect_error(
    filter_care_setting(essence_raw, keep_types = c("Emergency Care", NA)),
    "`keep_types` must be a character vector"
  )
  expect_error(
    filter_care_setting(essence_raw, fix_to = NA_character_),
    "`fix_to` must be a single, non-empty character string"
  )
  expect_error(
    filter_care_setting(essence_raw, fix_facility_type_vector = 1:2),
    "`fix_facility_type_vector` must be a character vector"
  )
  expect_error(
    filter_care_setting(essence_raw, fix_facility_type_regex = c("a", "b")),
    "`fix_facility_type_regex` must be a single"
  )
})

# link_encounters() ----

test_that("link_encounters() advertises inpatient_admission_data as required", {
  expect_true(rlang::is_missing(formals(link_encounters)$inpatient_admission_data))
})

test_that("link_encounters() aborts when inpatient_admission_data is omitted or NULL", {
  expect_error(
    link_encounters(essence_ed_raw),
    "requires `inpatient_admission_data`"
  )
  expect_error(
    link_encounters(essence_ed_raw, NULL),
    "requires `inpatient_admission_data`"
  )
})

test_that("link_encounters() rejects a malformed merge_fields", {
  expect_error(
    link_encounters(essence_ed_raw, essence_inp_raw, merge_fields = "union_ccdd"),
    "`merge_fields` must be a named character vector"
  )
  expect_error(
    link_encounters(
      essence_ed_raw, essence_inp_raw,
      merge_fields = c(CCDD = "union_ccdd", "prefer_yes")
    ),
    "`merge_fields` must be a named character vector"
  )
  expect_error(
    link_encounters(essence_ed_raw, essence_inp_raw, merge_fields = NULL),
    "`merge_fields` must be a named character vector"
  )
})

test_that("link_encounters() accepts an empty merge_fields", {
  result <- suppressMessages(
    link_encounters(
      essence_ed_raw, essence_inp_raw, merge_fields = character(0)
    )
  )
  expect_s3_class(result, "data.frame")
})

test_that("link_encounters() validates merge_delimiter", {
  expect_error(
    link_encounters(
      essence_ed_raw, essence_inp_raw, merge_delimiter = c(";", ",")
    ),
    "`merge_delimiter` must be a single"
  )
})

test_that("merge_field_value() lists every valid strategy when given an unknown one", {
  expect_error(
    merge_field_value("a", "ED", "a", strategy = "nope", delimiter = ";"),
    "Unknown merge strategy `nope`"
  )
  expect_true(all(
    vapply(
      merge_strategies,
      function(strategy) {
        !inherits(
          tryCatch(
            merge_field_value("a", "ED", "a", strategy = strategy, delimiter = ";"),
            error = identity
          ),
          "error"
        )
      },
      logical(1L)
    )
  ))
})

# assign_treating_geography() ----

test_that("assign_treating_geography() validates `site`", {
  expect_error(
    assign_treating_geography(essence_raw, site = c("KY", "OH")),
    "`site` must be a single, non-empty character string"
  )
  expect_error(assign_treating_geography(essence_raw, site = NA), "`site`")
  expect_error(assign_treating_geography(essence_raw, site = ""), "`site`")
})

test_that("assign_treating_geography() warns when `site` matches no Region value", {
  # The case that used to flag every visit as out-of-state without a word
  expect_warning(
    result <- suppressMessages(assign_treating_geography(essence_raw, site = "ky")),
    "No `region` value begins with `ky_`"
  )
  expect_true(all(result$.out_of_state))
})

test_that("assign_treating_geography() does not warn when `site` matches", {
  expect_no_warning(
    suppressMessages(assign_treating_geography(essence_raw, site = "KY"))
  )
})

test_that("assign_treating_geography() does not warn on a zero-row input", {
  expect_no_warning(
    suppressMessages(assign_treating_geography(essence_raw[0, ]))
  )
})

test_that("the geography functions reject a non-string output column name", {
  expect_error(
    assign_treating_geography(essence_raw, new_region_col = 5),
    "`new_region_col` must be a single, non-empty character string"
  )
  expect_error(
    assign_facility_geography(essence_raw, new_zip_col = c("a", "b")),
    "`new_zip_col` must be a single"
  )
})

# print methods ----

test_that("print methods write the whole report to stdout, not the message stream", {
  summary_obj    <- summarize_duplicates(essence_raw)
  classified_obj <- classify_duplicates(essence_raw, verbose = FALSE)

  expect_message(out_summary <- capture.output(print(summary_obj)), NA)
  expect_message(out_classified <- capture.output(print(classified_obj)), NA)

  expect_match(paste(out_summary, collapse = "\n"), "ESSENCE Duplicate Summary")
  expect_match(paste(out_summary, collapse = "\n"), "By Facility")
  expect_match(
    paste(out_classified, collapse = "\n"), "ESSENCE Duplicate Classification"
  )
  expect_match(paste(out_classified, collapse = "\n"), "Visit Groups")
})

test_that("format() returns the same lines that print() writes", {
  summary_obj <- summarize_duplicates(essence_raw)
  expect_identical(
    capture.output(print(summary_obj)),
    as.character(format(summary_obj))
  )
})

test_that("print methods return their input invisibly", {
  summary_obj <- summarize_duplicates(essence_raw)
  res <- withVisible(print(summary_obj))
  expect_false(res$visible)
  expect_identical(res$value, summary_obj)
})
