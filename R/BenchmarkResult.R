#' @title Container for Benchmarking Results
#'
#' @include mlr_reflections.R
#'
#' @description
#' This is the result container object returned by [benchmark()].
#' A [BenchmarkResult] consists of the data row-binded data of multiple
#' [ResampleResult]s, which can easily be re-constructed.
#'
#' [BenchmarkResult]s can be visualized via \CRANpkg{mlr3viz}'s `autoplot()` function.
#'
#' For statistical analysis of benchmark results and more advanced plots, see \CRANpkg{mlr3benchmark}.
#'
#' @note
#' All stored objects are accessed by reference.
#' Do not modify any extracted object without cloning it first.
#'
#' @template param_measures
#'
#' @section S3 Methods:
#' * `as.data.table(rr, ..., reassemble_learners = TRUE, convert_predictions = TRUE, predict_sets = "test")`\cr
#'   [BenchmarkResult] -> [data.table::data.table()]\cr
#'   Returns a tabular view of the internal data.
#' * `c(...)`\cr
#'   ([BenchmarkResult], ...) -> [BenchmarkResult]\cr
#'   Combines multiple objects convertible to [BenchmarkResult] into a new [BenchmarkResult].
#'
#' @export
#' @examples
#' set.seed(123)
#' learners = list(
#'   lrn("classif.featureless", predict_type = "prob"),
#'   lrn("classif.rpart", predict_type = "prob")
#' )
#'
#' design = benchmark_grid(
#'   tasks = list(tsk("sonar"), tsk("spam")),
#'   learners = learners,
#'   resamplings = rsmp("cv", folds = 3)
#' )
#' print(design)
#'
#' bmr = benchmark(design)
#' print(bmr)
#'
#' bmr$tasks
#' bmr$learners
#'
#' # first 5 resampling iterations
#' head(as.data.table(bmr, measures = c("classif.acc", "classif.auc")), 5)
#'
#' # aggregate results
#' bmr$aggregate()
#'
#' # aggregate results with hyperparameters as separate columns
#' mlr3misc::unnest(bmr$aggregate(params = TRUE), "params")
#'
#' # extract resample result for classif.rpart
#' rr = bmr$aggregate()[learner_id == "classif.rpart", resample_result][[1]]
#' print(rr)
#'
#' # access the confusion matrix of the first resampling iteration
#' rr$predictions()[[1]]$confusion
#'
#' # reduce to subset with task id "sonar"
#' bmr$filter(task_ids = "sonar")
#' print(bmr)
BenchmarkResult = R6Class("BenchmarkResult",
  public = list(
    #' @field data (`ResultData`)\cr
    #' Internal data storage object of type `ResultData`.
    #' We discourage users to directly work with this field.
    #' Use `as.table.table(BenchmarkResult)` instead.
    data = NULL,

    #' @description
    #' Creates a new instance of this [R6][R6::R6Class] class.
    #'
    #' @param data (`ResultData`)\cr
    #'   An object of type `ResultData`, either extracted from another [ResampleResult], another
    #'   [BenchmarkResult], or manually constructed with [as_result_data()].
    initialize = function(data = NULL) {
      if (inherits(data, "ResultData")) {
        self$data = data
      } else {
        self$data = ResultData$new(data)
      }
    },

    #' @description
    #' Opens the help page for this object.
    help = function() {
      open_help("mlr3::BenchmarkResult")
    },

    #' @description
    #' Helper for print outputs.
    format = function() {
      sprintf("<%s>", class(self)[1L])
    },

    #' @description
    #' Printer.
    print = function() {
      tab = self$aggregate(measures = list(), conditions = TRUE)
      catf("%s of %i rows with %i resampling runs",
        format(self), self$data$iterations(), nrow(tab))
      if (nrow(tab)) {
        tab = remove_named(tab, c("uhash", "resample_result"))
        print(tab, class = FALSE, row.names = FALSE, print.keys = FALSE, digits = 3)
      }
    },

    #' @description
    #' Fuses a second [BenchmarkResult] into itself, mutating the [BenchmarkResult] in-place.
    #' If the second [BenchmarkResult] `bmr` is `NULL`, simply returns `self`.
    #' Note that you can alternatively use the combine function [c()] which calls this method internally.
    #'
    #' @param bmr ([BenchmarkResult])\cr
    #'   A second [BenchmarkResult] object.
    #'
    #' @return
    #' Returns the object itself, but modified **by reference**.
    #' You need to explicitly `$clone()` the object beforehand if you want to keep
    #' the object in its previous state.
    combine = function(bmr) {
      if (!is.null(bmr)) {
        assert_benchmark_result(bmr)
        if (self$data$iterations() && self$task_type != bmr$task_type) {
          stopf("BenchmarkResult is of task type '%s', but must be '%s'", bmr$task_type, self$task_type)
        }

        self$data$combine(bmr$data)
      }

      invisible(self)
    },


    #' @description
    #' Returns a table with one row for each resampling iteration, including
    #' all involved objects: [Task], [Learner], [Resampling], iteration number
    #' (`integer(1)`), and [Prediction]. If `ids` is set to `TRUE`, character
    #' column of extracted ids are added to the table for convenient
    #' filtering: `"task_id"`, `"learner_id"`, and `"resampling_id"`.
    #'
    #' Additionally calculates the provided performance measures and binds the
    #' performance scores as extra columns. These columns are named using the id of
    #' the respective [Measure].
    #'
    #' @param ids (`logical(1)`)\cr
    #'   Adds object ids (`"task_id"`, `"learner_id"`, `"resampling_id"`) as
    #'   extra character columns for convenient subsetting.
    #'
    #' @param predict_sets (`character()`)\cr
    #'   Vector of predict sets (`{"train", "test"}`) to construct the [Prediction] objects from.
    #'   Default is `"test"`.
    #'
    #' @return [data.table::data.table()].
    score = function(measures = NULL, ids = TRUE, predict_sets = "test") {
      measures = assert_measures(as_measures(measures, task_type = self$task_type))
      assert_flag(ids)

      tab = score_measures(self, measures, view = NULL)
      tab = merge(self$data$data$uhashes, tab, by = "uhash", sort = FALSE)
      tab[, "nr" := .GRP, by = "uhash"]

      if (ids) {
        set(tab, j = "task_id", value = ids(tab$task))
        set(tab, j = "learner_id", value = ids(tab$learner))
        set(tab, j = "resampling_id", value = ids(tab$resampling))
      }

      set(tab, j = "prediction", value = as_predictions(tab$prediction, predict_sets))

      cns = c("uhash", "nr", "task", "task_id", "learner", "learner_id", "resampling", "resampling_id",
        "iteration", "prediction", ids(measures))
      cns = intersect(cns, names(tab))
      tab[, cns, with = FALSE]
    },

    #' @description
    #' Returns a result table where resampling iterations are combined into
    #' [ResampleResult]s. A column with the aggregated performance score is
    #' added for each [Measure], named with the id of the respective measure.
    #'
    #' For convenience, different flags can be set to extract more
    #' information from the returned [ResampleResult]:
    #'
    #' @param uhashes (`logical(1)`)\cr
    #'   Adds the uhash values of the [ResampleResult] as extra character
    #'   column `"uhash"`.
    #'
    #' @param ids (`logical(1)`)\cr
    #'   Adds object ids (`"task_id"`, `"learner_id"`, `"resampling_id"`) as
    #'   extra character columns for convenient subsetting.
    #'
    #' @param params (`logical(1)`)\cr
    #'   Adds the hyperparameter values as extra list column `"params"`. You
    #'   can unnest them with [mlr3misc::unnest()].
    #'
    #' @param conditions (`logical(1)`)\cr
    #'   Adds the number of resampling iterations with at least one warning as
    #'   extra integer column `"warnings"`, and the number of resampling
    #'   iterations with errors as extra integer column `"errors"`.
    #'
    #' @return [data.table::data.table()].
    aggregate = function(measures = NULL, ids = TRUE, uhashes = FALSE, params = FALSE, conditions = FALSE) {
      measures = assert_measures(as_measures(measures, task_type = self$task_type))
      assert_flag(ids)
      assert_flag(uhashes)
      assert_flag(params)
      assert_flag(conditions)

      create_rr = function(view) {
        if (length(view)) ResampleResult$new(self$data, view = copy(view)) else list()
      }

      rdata = self$data$data
      tab = rdata$fact[rdata$uhashes, list(
        nr = .GRP,
        iters = .N,
        task_hash = .SD$task_hash[1L],
        learner_hash = .SD$learner_hash[1L],
        learner_phash = .SD$learner_phash[1L],
        resampling_hash = .SD$resampling_hash[1L],
        resample_result = list(create_rr(.BY[[1L]])),
        warnings = if (conditions) sum(map_int(.SD$learner_state, function(s) sum(s$log$class == "warning"))) else NA_integer_,
        errors = if (conditions) sum(map_int(.SD$learner_state, function(s) sum(s$log$class == "error"))) else NA_integer_
      ), by = "uhash", on = "uhash", nomatch = NULL]

      if (ids) {
        tab = merge(tab, rdata$tasks[, list(task_hash = .SD$task_hash, task_id = ids(.SD$task))],
          by = "task_hash", sort = FALSE)
        tab = merge(tab, rdata$learners[, list(learner_phash = .SD$learner_phash, learner_id = ids(.SD$learner))],
          by = "learner_phash", sort = FALSE)
        tab = merge(tab, rdata$resamplings[, list(resampling_hash = .SD$resampling_hash, resampling_id = ids(.SD$resampling))],
          by = "resampling_hash", sort = FALSE)
      }

      if (!uhashes) {
        set(tab, j = "uhash", value = NULL)
      }

      if (params) {
        tab = merge(tab, rdata$learner_components, by = "learner_hash", sort = FALSE)
        setnames(tab, "learner_param_vals", "params")
      }

      if (!conditions) {
        tab = remove_named(tab, c("warnings", "errors"))
      }

      if (nrow(tab) > 0L) {
        scores = map_dtr(tab$resample_result, function(rr) as.list(rr$aggregate(measures)))
      } else {
        scores = setDT(named_list(ids(measures), double()))
      }
      tab = insert_named(tab, scores)

      cns = c("uhash", "nr", "resample_result", "task_id", "learner_id", "resampling_id", "iters",
          "warnings", "errors", "params", ids(measures))
      cns = intersect(cns, names(tab))
      tab[, cns, with = FALSE]
    },

    #' @description
    #' Subsets the benchmark result. If `task_ids` is not `NULL`, keeps all
    #' tasks with provided task ids and discards all others tasks.
    #' Same procedure for `learner_ids` and `resampling_ids`.
    #'
    #' @param task_ids (`character()`)\cr
    #'   Ids of [Task]s to keep.
    #' @param task_hashes (`character()`)\cr
    #'   Hashes of [Task]s to keep.
    #' @param learner_ids (`character()`)\cr
    #'   Ids of [Learner]s to keep.
    #' @param learner_hashes (`character()`)\cr
    #'   Hashes of [Learner]s to keep.
    #' @param resampling_ids (`character()`)\cr
    #'   Ids of [Resampling]s to keep.
    #' @param resampling_hashes (`character()`)\cr
    #'   Hashes of [Resampling]s to keep.
    #'
    #' @return
    #' Returns the object itself, but modified **by reference**.
    #' You need to explicitly `$clone()` the object beforehand if you want to keeps
    #' the object in its previous state.
    filter = function(task_ids = NULL, task_hashes = NULL, learner_ids = NULL, learner_hashes = NULL,
      resampling_ids = NULL, resampling_hashes = NULL) {
      learner_phashes = NULL

      filter_if_not_null = function(column, hashes) {
        if (is.null(hashes))
          fact
        else
          fact[unique(hashes), on = column, nomatch = NULL]
      }


      if (!is.null(task_ids)) {
        task = task_hash = NULL
        task_hashes = union(task_hashes, self$data$data$tasks[ids(task) %in% task_ids, task_hash])
      }

      if (!is.null(learner_ids)) {
        learner = learner_phash = NULL
        learner_phashes = self$data$data$learners[ids(learner) %in% learner_ids, learner_phash]
      }

      if (!is.null(resampling_ids)) {
        resampling = resampling_hash = NULL
        resampling_hashes = union(resampling_hashes, self$data$data$resamplings[ids(resampling) %in% resampling_ids, resampling_hash])
      }

      fact = self$data$data$fact
      fact = filter_if_not_null("task_hash", task_hashes)
      fact = filter_if_not_null("learner_hash", learner_hashes)
      fact = filter_if_not_null("learner_phash", learner_phashes)
      fact = filter_if_not_null("resampling_hash", resampling_hashes)

      self$data$data$fact = fact
      self$data$sweep()

      invisible(self)
    },

    #' @description
    #' Retrieve the i-th [ResampleResult], by position or by unique hash `uhash`.
    #' `i` and `uhash` are mutually exclusive.
    #'
    #' @param i (`integer(1)`)\cr
    #'   The iteration value to filter for.
    #'
    #' @param uhash (`logical(1)`)\cr
    #'   The `ushash` value to filter for.
    #'
    #' @return [ResampleResult].
    resample_result = function(i = NULL, uhash = NULL) {
      if (!xor(is.null(i), is.null(uhash))) {
        stopf("Either `i` or `uhash` must be provided")
      }

      uhashes = self$data$uhashes()
      if (is.null(i)) {
        needle = assert_choice(uhash, uhashes)
      } else {
        i = assert_int(i, lower = 1L, upper = length(uhashes), coerce = TRUE)
        needle = uhashes[i]
      }

      ResampleResult$new(self$data, view = needle)
    }
  ),

  active = list(
    #' @field task_type (`character(1)`)\cr
    #' Task type of objects in the `BenchmarkResult`.
    #' All stored objects ([Task], [Learner], [Prediction]) in a single `BenchmarkResult` are
    #' required to have the same task type, e.g., `"classif"` or `"regr"`.
    #' This is `NA` for empty [BenchmarkResult]s.
    task_type = function(rhs) {
      assert_ro_binding(rhs)
      self$data$task_type
    },

    #' @field tasks ([data.table::data.table()])\cr
    #' Table of included [Task]s with three columns:
    #'
    #' * `"task_hash"` (`character(1)`),
    #' * `"task_id"` (`character(1)`), and
    #' * `"task"` ([Task]).
    tasks = function(rhs) {
      assert_ro_binding(rhs)

      tab = self$data$tasks()
      set(tab, j = "task_id", value = ids(tab$task))
      setcolorder(tab, c("task_hash", "task_id", "task"))[]
    },

    #' @field learners ([data.table::data.table()])\cr
    #' Table of included [Learner]s with three columns:
    #'
    #' * `"learner_hash"` (`character(1)`),
    #' * `"learner_id"` (`character(1)`), and
    #' * `"learner"` ([Learner]).
    #'
    #' Note that it is not feasible to access learned models via this field, as the training task would be ambiguous.
    #' For this reason the returned learner are reseted before they are returned.
    #' Instead, select a row from the table returned by `$score()`.
    learners = function(rhs) {
      assert_ro_binding(rhs)

      tab = self$data$learners(states = FALSE)
      set(tab, j = "learner_id", value = ids(tab$learner))
      setcolorder(tab, c("learner_hash", "learner_id", "learner"))[]
    },

    #' @field resamplings ([data.table::data.table()])\cr
    #' Table of included [Resampling]s with three columns:
    #'
    #' * `"resampling_hash"` (`character(1)`),
    #' * `"resampling_id"` (`character(1)`), and
    #' * `"resampling"` ([Resampling]).
    resamplings = function(rhs) {
      assert_ro_binding(rhs)

      tab = self$data$resamplings()
      set(tab, j = "resampling_id", value = ids(tab$resampling))
      setcolorder(tab, c("resampling_hash", "resampling_id", "resampling"))[]
    },

    #' @field resample_results ([data.table::data.table()])\cr
    #' Returns a table with three columns:
    #' * `uhash` (`character()`).
    #' * `resample_result` ([ResampleResult]).
    resample_results = function(rhs) {
      assert_ro_binding(rhs)
      rdata = self$data$data

      create_rr = function(view) {
        if (length(view)) ResampleResult$new(self$data, view = copy(view)) else list()
      }
      tab = rdata$fact[rdata$uhashes, list(
        nr = .GRP,
        resample_result = list(create_rr(.BY[[1L]]))
      ), by = "uhash"]
    },

    #' @field n_resample_results (`integer(1)`)\cr
    #' Returns the total number of stored [ResampleResult]s.
    n_resample_results = function(rhs) {
      assert_ro_binding(rhs)
      length(self$data$uhashes())
    },

    #' @field uhashes (`character()`)\cr
    #' Set of (unique) hashes of all included [ResampleResult]s.
    uhashes = function(rhs) {
      assert_ro_binding(rhs)
      self$data$uhashes()
    }
  ),

  private = list(
    deep_clone = function(name, value) {
      if (name == "data") value$clone(deep = TRUE) else value
    }
  )
)

#' @export
as.data.table.BenchmarkResult = function(x, ..., hashes = FALSE, predict_sets = "test") { # nolint
  tab = x$data$as_data_table(view = NULL, predict_sets = predict_sets)
  tab[, c("uhash", "task", "learner", "resampling", "iteration", "prediction"), with = FALSE]
}

#' @export
c.BenchmarkResult = function(...) { # nolint
  bmrs = lapply(list(...), as_benchmark_result)
  init = BenchmarkResult$new()
  Reduce(function(lhs, rhs) lhs$combine(rhs), bmrs, init = init)
}

#' @title Convert to BenchmarkResult
#'
#' @description
#' Simple S3 method to convert objects to a [BenchmarkResult].
#'
#' @param x (`any`)\cr
#'  Object to dispatch on, e.g. a [ResampleResult].
#' @param ... (`any`)\cr
#'  Currently not used.
#'
#' @return ([BenchmarkResult]).
#' @export
as_benchmark_result = function(x, ...) {
  UseMethod("as_benchmark_result")
}

#' @export
as_benchmark_result.BenchmarkResult = function(x, ...) { # nolint
  x
}
