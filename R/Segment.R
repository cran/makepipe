
# Segment class ----------------------------------------------------------------
#' Segment
#'
#' @description A Segment object is automatically constructed and attached to
#'   the Pipeline when a call to `make_*()` is made. It stores the relationships
#'   between targets, dependencies, and sources.
#'
#' @param id An integer that uniquely identifies the segment
#' @param targets A character vector of paths to files
#' @param dependencies A character vector of paths to files which the `targets`
#'   depend on
#' @param packages A character vector of names of packages which `targets`
#'   depend on
#' @param envir The environment in which to execute the instructions.
#' @param force A logical determining whether or not execution of the `source`
#'   or `recipe` will be forced (i.e. happen whether or not the targets are
#'   out-of-date)
#' @param label A short label for the segment
#' @param note A description of what the segment does
#' @param result An object, whatever is returned by executing the instructions
#' @param executed A logical, whether or not the instructions were executed
#' @param execution_time A difftime, the time taken to execute the instructions
#'
#' @keywords internal
#' @family segment
#' @export Segment
#' @aliases Segment
#' @importFrom R6 R6Class
Segment <- R6::R6Class("Segment",
  private = list(
    id = NULL,
    instructions_txt = NULL,
    instructions_bullet = NULL,
    result_txt = NULL
  ),
  public = list(
    #' @field targets A character vector of paths to files
    targets = NULL,
    #' @field dependencies A character vector of paths to files which the `targets`
    #'   depend on
    dependencies = NULL,
    #' @field packages A character vector of names of packages which `targets`
    #'   depend on
    packages = NULL,
    #' @field force A logical determining whether or not execution of the `source`
    #'   or `recipe` will be forced (i.e. happen whether or not the targets are
    #'   out-of-date)
    force = NULL,
    #' @field envir The environment in which to execute the instructions.
    envir = NULL,
    #' @field result An object, whatever is returned by executing the instructions
    result = NULL,
    #' @field executed A logical, whether or not the instructions were executed
    executed = FALSE,
    #' @field execution_time A difftime, the time taken to execute the instructions
    execution_time = NULL,
    #' @field label A short label for the segment
    label = NULL,
    #' @field note A description of what the segment does
    note = NULL,


    #' @description Initialise a new Segment
    initialize = function(id, targets, dependencies, packages, envir, force,
                          executed, result, execution_time) {
      if (!is.integer(id)) stopifnot_class(id, "numeric")
      stopifnot_class(targets, "character")
      if (!is.null(dependencies)) stopifnot_class(dependencies, "character")
      if (!is.null(packages)) stopifnot_class(packages, "character")
      stopifnot_class(envir, "environment")
      stopifnot_class(executed, "logical")
      stopifnot_class(force, "logical")
      if (!is.null(execution_time)) stopifnot_class(execution_time, "difftime")

      find.package(packages) # Error if package cannot be found

      if (any(targets %in% dependencies)) {
        stop("`dependencies` must not be among the `targets`", call. = FALSE)
      }

      targets <- unique(targets)
      dependencies <- unique(dependencies)
      packages <- unique(packages)

      private$id <- as.integer(id)

      self$targets <- targets
      self$dependencies <- dependencies
      self$packages <- packages
      self$envir <- envir
      self$force <- force
      self$executed <- executed
      self$result <- result
      self$execution_time <- execution_time

      invisible(self)
    },

    #' @description Printing method
    print = function() {
      cli::cat_line(cli::col_grey("# makepipe segment"))
      cat("\n")
      cat(paste(self$text_summary, collapse = "\n"))
      cat("\n")
    },

    #' @description Update the Segment with new execution information
    update_result = function(executed, execution_time, result) {
      stopifnot_class(executed, "logical")
      if (!is.null(execution_time)) stopifnot_class(execution_time, "difftime")
      self$executed <- executed
      self$result <- result
      self$execution_time <- execution_time

      invisible(self)
    },
    #' @description Apply annotations to Segment
    annotate = function(label = NULL, note = NULL) {
      if (!is.null(label) && !label == "") self$label <- label
      if (!is.null(note) && !note == "") self$note <- note

      invisible(self)
    }
  ),
  active = list(
    #' @field edges Get edges connecting the dependencies, instructions, and targets
    edges = function() {
      is_recipe <- inherits(self, "SegmentRecipe")
      edges <- rbind(
        new_edge(self$dependencies, private$instructions_txt, TRUE, is_recipe, FALSE),
        new_edge(private$instructions_txt, self$targets, FALSE, FALSE, FALSE)
      )

      if (length(self$packages) > 0) {
        edges <- rbind(
          new_edge(self$packages, private$instructions_txt, TRUE, FALSE, TRUE),
          edges
        )
      }

      edges$.segment_id <- private$id

      dependencies <- self$dependencies
      if (!is_recipe) dependencies <- c(dependencies, self$source)
      missing_deps <- FALSE
      if (!is.null(dependencies)) missing_deps <- any(!file.exists(dependencies))
      if (missing_deps) {
        # Sometimes the dependencies of one segment of the pipeline are the
        # targets are the targets of a previous segment. In this case, if the
        # dependency doesn't exist, it will be rebuilt and hence be newer than
        # the existing targets therefore making the targets out-of-date
        edges$.outdated <- TRUE
      } else {
        edges$.outdated <- out_of_date(self$targets, dependencies, self$packages)
      }
      edges$.outdated[edges$.source] <- FALSE # If not a target, then up to date

      edges
    },

    #' @field nodes Get nodes corresponding to  dependencies, instructions, and targets
    nodes = function() {
      is_recipe <- inherits(self, "SegmentRecipe")
      nodes <- rbind(
        new_node(private$instructions_txt, TRUE, is_recipe, FALSE),
        new_node(self$targets, FALSE, FALSE, FALSE),
        new_node(self$dependencies, FALSE, FALSE, FALSE),
        new_node(self$packages, FALSE, FALSE, TRUE)
      )

      nodes
    },

    #' @field text_summary A plain text summary of the Segment
    text_summary = function() {
      bullet <- function(...) paste0("* ", ...)
      list_quote <- function(...) paste0("'", paste(..., collapse = "', '"), "'")

      # Title
      title <- self$label
      if (is.null(title) & !is.null(self$source)) title <- basename(self$source)
      if (is.null(title)) title <- "Recipe"
      out <- c(paste0("## ", title), "")

      # Note
      if (!is.null(self$note)) out <- c(out, self$note, "")

      # Bullets
      out <- c(out, bullet(private$instructions_bullet))
      out <- c(out, bullet("Targets: ", list_quote(self$targets)))

      if (length(self$dependencies) > 0) {
        out <- c(out, bullet("File dependencies: ", list_quote(self$dependencies)))
      }

      if (length(self$packages) > 0) {
        out <- c(out, bullet("Package dependencies: ", list_quote(self$packages)))
      }

      out <- c(out, bullet("Executed: ", self$executed))

      if (self$executed) {
        out <- c(out, bullet("Execution time: ", format(self$execution_time)))
      }
      if (self$executed) {
        out <- c(out, bullet(private$result_txt))
      }

      out <- c(out, bullet("Environment: ", env_name(self$envir)))

      out
    }
  )
)

# Recipe subclass --------------------------------------------------------------
#' Segment
#'
#' @description A Segment object is automatically constructed and attached to
#'   the Pipeline when a call to `make_*()` is made. It stores the relationships
#'   between targets, dependencies, and sources.
#'
#' @param id An integer that uniquely identifies the segment
#' @param recipe A chunk of R code which makes the `targets`
#' @param targets A character vector of paths to files
#' @param dependencies A character vector of paths to files which the `targets`
#'   depend on
#' @param packages A character vector of names of packages which `targets`
#'   depend on
#' @param envir The environment in which to execute the instructions.
#' @param force A logical determining whether or not execution of the `source`
#'   or `recipe` will be forced (i.e. happen whether or not the targets are
#'   out-of-date)
#' @param result An object, whatever is returned by executing the instructions
#' @param executed A logical, whether or not the instructions were executed
#' @param execution_time A difftime, the time taken to execute the instructions
#' @param quiet A logical determining whether or not messages are signaled
#'
#' @keywords internal
#' @family segment
#' @export SegmentRecipe
#' @aliases SegmentRecipe
#' @importFrom R6 R6Class
SegmentRecipe <- R6::R6Class("SegmentRecipe",
  inherit = Segment,
  public = list(
    #' @field recipe A chunk of R code which makes the `targets`
    recipe = expression(),

    #' @description Initialise a new Segment
    initialize = function(id, recipe, targets, dependencies, packages, envir,
                          force, executed, result, execution_time) {
      if (!is.language(recipe)) stop("`recipe` must be an expression", call. = FALSE)
      super$initialize(id, targets, dependencies, packages, envir, force, executed, result, execution_time)

      instructions_txt <- robust_deparse(recipe)
      instructions_bullet <- paste0("Recipe: \n\n", instructions_txt, "\n")
      result_txt <- ifelse(is.null(result), "Result: 0 object(s)", "Result: 1 object(s)")

      private$instructions_txt <- instructions_txt
      private$instructions_bullet <- instructions_bullet
      private$result_txt <- result_txt
      self$recipe <- recipe

      invisible(self)
    },

    #' @description Update the Segment with new execution information
    update_result = function(executed, execution_time, result) {
      private$result_txt <- ifelse(is.null(result), "Result: 0 object(s)", "Result: 1 object(s)")
      super$update_result(executed, execution_time, result)
    },

    #' @description Execute the Segment
    #' @param ... Additional parameters to pass to `base::eval()`
    execute = function(envir = NULL, quiet = getOption("makepipe.quiet"), ...) {
      if (!is.null(envir)) {
        stopifnot_class(envir, "environment")
        self$envir <- envir
      }

      outdated <- TRUE
      if (!self$force) outdated <- out_of_date(self$targets, self$dependencies, self$packages)

      if (outdated) {
        if (!quiet) {
          cli::cli_process_start(
            "Targets are out of date. Updating...",
            msg_done = "Finished updating",
            msg_failed = "Something went wrong"
          )
          cli::cat_line()
        }

        execution_time <- Sys.time()
        out <- eval(self$recipe, envir = self$envir, ...)
        execution_time <- Sys.time() - execution_time

        if (!quiet) cli::cli_process_done()
      } else {
        execution_time <- NULL
        if (!quiet) cli::cli_alert_success("Targets are up to date")
        out <- NULL
      }

      self$update_result(outdated, execution_time, out)

      invisible(self)
    }
  )
)


# Source subclass --------------------------------------------------------------
#' Segment
#'
#' @description A Segment object is automatically constructed and attached to
#'   the Pipeline when a call to `make_*()` is made. It stores the relationships
#'   between targets, dependencies, and sources.
#'
#' @param id An integer that uniquely identifies the segment
#' @param source The path to an R script which makes the `targets`
#' @param targets A character vector of paths to files
#' @param dependencies A character vector of paths to files which the `targets`
#'   depend on
#' @param packages A character vector of names of packages which `targets`
#'   depend on
#' @param envir The environment in which to execute the instructions.
#' @param force A logical determining whether or not execution of the `source`
#'   or `recipe` will be forced (i.e. happen whether or not the targets are
#'   out-of-date)
#' @param result An object, whatever is returned by executing the instructions
#' @param executed A logical, whether or not the instructions were executed
#' @param execution_time A difftime, the time taken to execute the instructions
#' @param quiet A logical determining whether or not messages are signaled

#' @keywords internal
#' @family segment
#' @export SegmentSource
#' @aliases SegmentSource
#' @importFrom R6 R6Class
SegmentSource <- R6::R6Class("SegmentSource",
   inherit = Segment,
   public = list(
     #' @field source The path to an R script which makes the `targets`
     source = character(),

     #' @description Initialise a new Segment
     initialize = function(id, source, targets, dependencies, packages, envir,
                           force, executed, result, execution_time) {
       stopifnot_class(source, "character")
       if (!file.exists(source)) stop("`source` does not exist", call. = FALSE)
       if (any(targets %in% source)) {
         stop("`source` must not be among the `targets`", call. = FALSE)
       }

       super$initialize(id, targets, dependencies, packages, envir, force, executed, result, execution_time)

       private$instructions_txt <- source
       private$instructions_bullet <- paste0("Source: '", source, "'")
       private$result_txt <- paste0("Result: ", length(result), " object(s)")
       self$source <- source

       invisible(self)
     },

     #' @description Update the Segment with new execution information
     update_result = function(executed, execution_time, result) {
       private$result_txt <- paste0("Result: ", length(result), " object(s)")
       super$update_result(executed, execution_time, result)
     },

     #' @description Execute the Segment
     #' @param ... Additional parameters to pass to `base::source()`
     execute = function(envir = NULL, quiet = getOption("makepipe.quiet"), ...) {
       if (!is.null(envir)) {
         stopifnot_class(envir, "environment")
         self$envir <- envir
       }

       outdated <- TRUE
       if (!self$force) outdated <- out_of_date(self$targets, c(self$dependencies, self$source), self$packages)

       # Prepare fresh execution environment so we don't clutter existing environment
       register_env <- new.env(parent = emptyenv())
       assign("__makepipe_register__", register_env, self$envir)

       if (outdated) {
         if (!quiet) {
           cli::cli_process_start(
             "Targets are out of date. Updating...",
             msg_done = "Finished updating",
             msg_failed = "Something went wrong"
           )
           cli::cat_line()
         }

         execution_time <- Sys.time()
         source(self$source, local = self$envir, ...)
         execution_time <- Sys.time() - execution_time

         if (!quiet) cli::cli_process_done()
       } else {
         execution_time <- NULL
         if (!quiet) cli::cli_alert_success("Targets are up to date")
       }

       self$update_result(outdated, execution_time, register_env)

       invisible(self)
     }
   )
)


# Internal ---------------------------------------------------------------------

#' Create edges
#'
#' @param from A character vector of nodes
#' @param to A character vector of nodes
#' @param .source Either TRUE or FALSE
#' @param .recipe Either TRUE or FALSE
#' @param .pkg Either TRUE or FALSE
#'
#' @return A data.frame defining edges from all nodes in `from` to all nodes in
#'   `to`.
#' @noRd
new_edge <- function(from, to, .source, .recipe, .pkg) {
  lvls <- levels(factor(c(from, to)))
  expand.grid(
    from = factor(from, lvls),
    to = factor(to, lvls),
    arrows = "to",
    .source = .source,
    .recipe = .recipe,
    .pkg = .pkg,
    .outdated = FALSE,
    stringsAsFactors = FALSE
  )
}

#' Create nodes
#'
#' @param id A character vector of nodes
#' @param .source Either TRUE or FALSE
#' @param .recipe Either TRUE or FALSE
#' @param .pkg Either TRUE or FALSE
#'
#' @return A data.frame defining nodes
#' @noRd
new_node <- function(id, .source, .recipe, .pkg) {
  if (is.null(id)) return(NULL)
  nodes <- data.frame(
    id = factor(id),
    .source = .source,
    .recipe = .recipe,
    .pkg = .pkg,
    stringsAsFactors = FALSE
  )

  nodes
}

#' Get an environment's name
#'
#' @param x An environment
#'
#' @return A character vector
#' @noRd
env_name <- function(x) {
  stopifnot(is.environment(x))
  env_name <- environmentName(x)
  if (env_name == "") {
    env_name <- utils::capture.output(print(x))
    env_name <- regmatches(
      env_name,
      regexec("<environment: (.*)>", text = env_name)
    )

    env_name <- env_name[[1]][2]
  }

  env_name
}
