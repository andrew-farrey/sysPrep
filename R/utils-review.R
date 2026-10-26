#' Stages of review_facility_ed_visits()
#'
#' Internal helpers that [review_facility_ed_visits()] runs in order, so the
#' exported function reads as a short pipeline.
#'
#' @details
#' The stages, in the order `review_facility_ed_visits()` calls them:
#' \enumerate{
#'   \item `check_percentile_order()` aborts unless `percentile_low` is below
#'     `percentile_high`.
#'   \item `resolve_review_date_col()` resolves the optional `date_col`,
#'     warning and falling back to raw visit counts when it is absent.
#'   \item `inform_review_defaults()` emits the informational messages about
#'     the defaults in effect.
#'   \item `count_facility_visits()` counts visits per facility and facility
#'     type. When a date column is available it also reports `n_days` (the
#'     days the facility sent data) and `visits_per_day`, which divides by the
#'     number of distinct dates in the whole pull rather than by `n_days`, so
#'     a facility that stops sending partway through the pull scores lower
#'     instead of looking the same as one that sent every day. The divisor is
#'     the same for every facility, so the rate ranks facilities exactly as
#'     the count does and flags the same ones.
#'   \item `add_outlier_thresholds()` adds the percentile and/or IQR
#'     thresholds, optionally within facility types. Only the quantiles the
#'     chosen `method` actually uses are computed: the IQR quantiles would be
#'     wasted work (recomputed per group) under the default
#'     `method = "percentile"`, and vice versa.
#'   \item `flag_outliers()` adds the `.outlier_*` columns and drops the
#'     threshold helper columns. `.outlier_method` records the criterion that
#'     fired (`"percentile"`, `"iqr"`, or `"percentile+iqr"`), not the
#'     requested `method`. `method` is a single scalar for the whole
#'     call, so the comparison is chosen once with `if`/`else` rather than
#'     `dplyr::case_when()`, which is deprecated for a scalar condition as of
#'     dplyr 1.2.0.
#'   \item `arrange_review_result()` applies `return_format`.
#'   \item `inform_review_summary()` reports how many facilities were
#'     flagged.
#' }
#'
#' @param percentile_low,percentile_high Lower and upper percentile
#'   thresholds, each already validated as a number in `[0, 1]`.
#' @param call The environment errors are attributed to; see
#'   [resolve_col()].
#' @param data A data frame already passed through [clean_names_safe()].
#' @param date_col_quo The captured `date_col` expression (a `quosure` from
#'   [rlang::enquo()]), possibly `NULL`.
#' @param verbose Logical. Whether to emit informational messages.
#' @param use_time_norm Logical. Whether visits are normalized to visits per
#'   day.
#' @param group_by_type Logical. Whether thresholds are computed within
#'   facility types.
#' @param type_col_str,fac_col_str Names of the facility type and facility
#'   columns in `data`.
#' @param date_col_str Name of the date column, or `NULL`.
#' @param facility_counts The per-facility count data frame built so far.
#' @param detect_col Name of the count column outliers are detected on:
#'   `"visits_per_day"` or `"n_visits"`.
#' @param method One of `"percentile"`, `"iqr"`, or `"both"`.
#' @param iqr_multiplier Non-negative number: the IQR fence multiplier.
#' @param x,pct_low,pct_high,iqr_low,iqr_high The detection column and the
#'   four thresholds, as parallel vectors. A threshold that is `NA` (the
#'   method was not requested) never fires.
#' @param return_format One of `"outliers_only"` or `"all"`.
#'
#' @return `check_percentile_order()` returns `NULL` invisibly or aborts.
#'   `resolve_review_date_col()` returns a list with `use_time_norm` and
#'   `date_col_str`. `inform_review_defaults()` and `inform_review_summary()`
#'   are called for their messages. The remaining stages return the updated
#'   `facility_counts` data frame. `outlier_method_label()` returns a character
#'   vector the length of `x`.
#' @keywords internal
check_percentile_order <- function(percentile_low, percentile_high,
                                   call = rlang::caller_env()) {
  if (percentile_low >= percentile_high) {
    rlang::abort(
      c(
        "`percentile_low` must be less than `percentile_high`.",
        "x" = paste0(
          "`percentile_low` is ", percentile_low,
          " and `percentile_high` is ", percentile_high, "."
        )
      ),
      call = call
    )
  }
  invisible(NULL)
}

#' @rdname check_percentile_order
resolve_review_date_col <- function(data, date_col_quo,
                                    call = rlang::caller_env()) {
  use_time_norm <- !rlang::quo_is_null(date_col_quo)
  date_col_str  <- NULL

  if (use_time_norm) {
    date_col_sym <- capture_col_sym(date_col_quo, "date_col", call)
    date_col_str <- rlang::as_string(date_col_sym)
    date_col_sym <- resolve_col_optional(data, date_col_sym)
    if (is.null(date_col_sym)) {
      rlang::warn(
        paste0(
          "Date column `", date_col_str, "` not found in data. ",
          "Falling back to raw visit counts."
        )
      )
      use_time_norm <- FALSE
    } else {
      date_col_str <- rlang::as_string(date_col_sym)
    }
  }

  list(use_time_norm = use_time_norm, date_col_str = date_col_str)
}

#' @rdname check_percentile_order
inform_review_defaults <- function(data, type_col_str, use_time_norm,
                                   group_by_type, verbose) {
  inform_if(
    verbose,
    paste0(
      "Low-count facilities are expected for narrow syndrome definitions, ",
      "particularly at small rural hospitals. Low outliers do not necessarily ",
      "indicate a data quality problem. For most reliable outlier detection, ",
      "use denominator (all-cause ED visit) data."
    )
  )

  if (!use_time_norm) {
    inform_if(
      verbose,
      paste0(
        "No `date_col` supplied; using raw visit counts. ",
        "Supply a date column (e.g., `date_col = Date`) to report visits ",
        "per day, which makes pulls of different durations comparable."
      )
    )
  }

  if (!group_by_type && dplyr::n_distinct(data[[type_col_str]]) > 1L) {
    inform_if(
      verbose,
      paste0(
        "Outlier detection across all facility types combined. ",
        "Use `group_by_type = TRUE` to detect outliers within each ",
        "`FacilityType` separately."
      )
    )
  }
}

#' @rdname check_percentile_order
count_facility_visits <- function(data, fac_col_str, type_col_str,
                                  use_time_norm, date_col_str) {
  group_vars <- c(fac_col_str, type_col_str)

  facility_counts <- data |>
    dplyr::group_by(dplyr::across(dplyr::all_of(group_vars))) |>
    dplyr::summarise(
      n_visits = dplyr::n(),
      n_days   = if (use_time_norm) {
        dplyr::n_distinct(.data[[date_col_str]], na.rm = TRUE)
      } else {
        NA_integer_
      },
      .groups = "drop"
    )

  # Normalize by the pull's own date span, not by each facility's active
  # days: dividing by the days a facility actually sent data would give a
  # facility that went silent after day 10 the same rate as one that sent
  # every day, hiding exactly the dropout this rate exists to expose ----
  if (use_time_norm) {
    n_pull_days <- dplyr::n_distinct(data[[date_col_str]], na.rm = TRUE)
    facility_counts <- dplyr::mutate(
      facility_counts,
      visits_per_day = n_visits / n_pull_days
    )
  }

  facility_counts
}

#' @rdname check_percentile_order
add_outlier_thresholds <- function(facility_counts, detect_col, type_col_str,
                                   group_by_type, method, percentile_low,
                                   percentile_high, iqr_multiplier) {
  threshold_groups <- if (group_by_type) {
    dplyr::group_by(facility_counts, .data[[type_col_str]])
  } else {
    facility_counts
  }

  needs_pct <- method != "iqr"
  needs_iqr <- method != "percentile"

  threshold_groups |>
    dplyr::mutate(
      .pct_low  = if (needs_pct) {
        quantile(.data[[detect_col]], percentile_low, na.rm = TRUE)
      } else {
        NA_real_
      },
      .pct_high = if (needs_pct) {
        quantile(.data[[detect_col]], percentile_high, na.rm = TRUE)
      } else {
        NA_real_
      },
      .q1       = if (needs_iqr) {
        quantile(.data[[detect_col]], 0.25, na.rm = TRUE)
      } else {
        NA_real_
      },
      .q3       = if (needs_iqr) {
        quantile(.data[[detect_col]], 0.75, na.rm = TRUE)
      } else {
        NA_real_
      },
      .iqr      = .q3 - .q1,
      .iqr_low  = if (needs_iqr) .q1 - iqr_multiplier * .iqr else NA_real_,
      .iqr_high = if (needs_iqr) .q3 + iqr_multiplier * .iqr else NA_real_
    ) |>
    dplyr::ungroup()
}

#' @rdname check_percentile_order
flag_outliers <- function(facility_counts, detect_col, method) {
  facility_counts |>
    dplyr::mutate(
      .outlier_low = if (method == "percentile") {
        .data[[detect_col]] < .data[[".pct_low"]]
      } else if (method == "iqr") {
        .data[[detect_col]] < .data[[".iqr_low"]]
      } else {
        .data[[detect_col]] < .data[[".pct_low"]] |
          .data[[detect_col]] < .data[[".iqr_low"]]
      },
      .outlier_high = if (method == "percentile") {
        .data[[detect_col]] > .data[[".pct_high"]]
      } else if (method == "iqr") {
        .data[[detect_col]] > .data[[".iqr_high"]]
      } else {
        .data[[detect_col]] > .data[[".pct_high"]] |
          .data[[detect_col]] > .data[[".iqr_high"]]
      },
      .outlier_flag = .outlier_low | .outlier_high,
      .outlier_direction = dplyr::case_when(
        .outlier_low  & .outlier_high ~ "both",
        .outlier_low                  ~ "low",
        .outlier_high                 ~ "high",
        TRUE                          ~ NA_character_
      ),
      # Which criterion fired, not which `method` was requested; the unused
      # method's thresholds are NA, so it can never fire under a single
      # method ----
      .outlier_method = outlier_method_label(
        .data[[detect_col]],
        .data[[".pct_low"]], .data[[".pct_high"]],
        .data[[".iqr_low"]], .data[[".iqr_high"]]
      )
    ) |>
    dplyr::select(
      -dplyr::starts_with(".pct_"),
      -dplyr::starts_with(".q"),
      -dplyr::starts_with(".iqr")
    )
}

#' @rdname check_percentile_order
outlier_method_label <- function(x, pct_low, pct_high, iqr_low, iqr_high) {
  by_percentile <- (x < pct_low | x > pct_high) %in% TRUE
  by_iqr        <- (x < iqr_low | x > iqr_high) %in% TRUE

  label <- rep(NA_character_, length(x))
  label[by_iqr] <- "iqr"
  label[by_percentile] <- "percentile"
  label[by_percentile & by_iqr] <- "percentile+iqr"
  label
}

#' @rdname check_percentile_order
arrange_review_result <- function(facility_counts, detect_col, return_format) {
  if (return_format == "outliers_only") {
    facility_counts |>
      dplyr::filter(.outlier_flag) |>
      dplyr::arrange(dplyr::desc(.outlier_direction), .data[[detect_col]])
  } else {
    dplyr::arrange(
      facility_counts,
      dplyr::desc(.outlier_flag),
      .data[[detect_col]]
    )
  }
}

#' @rdname check_percentile_order
inform_review_summary <- function(facility_counts, method, group_by_type,
                                  verbose) {
  n_flagged <- sum(facility_counts$.outlier_flag, na.rm = TRUE)
  n_total   <- nrow(facility_counts)

  if (n_total == 0L) {
    inform_if(
      verbose,
      "No facilities in data after processing. Returning empty result."
    )
  } else {
    inform_if(
      verbose,
      paste0(
        n_flagged, " of ", n_total, " facilities flagged as outliers (",
        round(n_flagged / n_total * 100, 1), "%) ",
        "using `method = \"", method, "\"`",
        if (group_by_type) " within FacilityType groups" else "", "."
      )
    )
  }
}
