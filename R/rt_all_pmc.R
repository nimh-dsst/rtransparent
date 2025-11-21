.get_xml <- function(filename, remove_ns = F) {  

  article_xml <- xml2::read_xml(filename)
  if (remove_ns) article_xml <- xml2::xml_ns_strip(article_xml)

  return(article_xml)
}

.get_fund_pmc <- function(article_xml, synonyms) {

  fund_pmc_anysource <- ""
  is_fund_pred <- TRUE
  is_fund_pmc_title <- NA
  is_fund_pmc_anysource <- NA

  group_ls <- .get_fund_pmc_group(article_xml)

  fund_text <- group_ls$fund_statement_pmc
  fund_pmc_institute <- group_ls$fund_institute_pmc
  fund_pmc_source <- group_ls$fund_source_pmc
  is_fund_pmc_group <- group_ls$is_fund_group_pmc

  if (nchar(fund_text) == 0) {

    fund_text <- .get_fund_pmc_title(article_xml)
    is_fund_pmc_title <- nchar(fund_text) > 0
    is_fund_pred <- is_fund_pmc_title

  }

  if (!is_fund_pred) {

    # TODO Consider removing the if-statement  to always capture this

    fund_pmc_anysource <- .get_fund_pmc_source(article_xml)
    is_fund_pmc_anysource <- nchar(fund_pmc_anysource) > 0

  }

  return(list(
    "is_fund_pred" = is_fund_pred,
    "fund_text" = fund_text,
    "fund_pmc_institute" = fund_pmc_institute,
    "fund_pmc_source" = fund_pmc_source,
    "fund_pmc_anysource" = fund_pmc_anysource,
    "is_fund_pmc_group" = is_fund_pmc_group,
    "is_fund_pmc_title" = is_fund_pmc_title,
    "is_fund_pmc_anysource" = is_fund_pmc_anysource
  ))
}

.get_data_pmc <- function (article_xml, filename) {
  # rt_data_code_pmc <- function(article_xml, remove_ns = T, specificity = "low") {

  open_data <- rt_data_code_pmc(article_xml, filename)
  return(list(
    "is_open_data" = (open_data[["is_open_data"]] %||% F),
    "is_open_code" = (open_data[["is_open_code"]] %||% F),
    # FIXME these ones are inconsistent for some reason
    # "open_data_statements" = open_data["open_data_statements"],
    # "open_code_statements" = open_data["open_code_statements"],
    # "open_data_category" = open_data["open_data_category"],
    "is_relevant_code" = (open_data[["is_relevant_code"]] %||% F),
    "is_relevant_data" = (open_data[['is_relevant_data']] %||% F)
  ))
}


#' @returns Article sections as a list
.get_article_txt <- function(article_xml) {

  # Tidier but takes a median 11.0 ms vs current, which takes 10.6 ms
  section_names <- c(
    "ack",
    "body",
    "methods",
    "abstract",
    "footnotes"
  )

  section_funs <- list(
    .xml_ack,
    .xml_body,
    .xml_methods,
    .xml_abstract,
    .xml_footnotes
  )

  article_xml %>%
    purrr::map(section_funs, rlang::exec, .) %>%
    rlang::set_names(section_names)
}

#' Identify and extract statements of COI, Funding and Registration.
#'
#' Takes a PMC XML and returns relevant meta-data, as well as whether any
#'     statements of Conflicts of Interest (COI), Funding or Protocol
#'     Registration. If any such statements are found, it also extracts the
#'     relevant text.
#'
#' @param filename The name of the PMC XML as a string.
#' @param remove_ns TRUE if an XML namespace exists, else FALSE (default).
#' @param all_meta TRUE extracts all meta-data, FALSE extracts some (default).
#' @return A dataframe of results. It returns the unique identifiers of the
#'     article, whether each of 3 indicators of transparency (COI, Funding or
#'     Registration) was identified, the relevant text identified, whether it
#'     was identified through a dedicated XML tag (such variables include "pmc"
#'     in their name, e.g. “fund_pmc_source”) and whether each labelling
#'     function identified relevant text or not. The labeling functions are
#'     returned to add flexibility in how this package is used; for example,
#'     future definitions of Registration may differ from the one we used. If a
#'     labelling function returns NA it means that it was not run.
#' @examples
#' \dontrun{
#' # Path to PMC XML.
#' filepath <- "../inst/extdata/00003-PMID26637448-PMC4737611.xml"
#'
#' # Identify and extract meta-data and indicators of transparency.
#' results_table <- rt_all_pmc(filepath, remove_ns = T, all_meta = T)
#' }
#' @export
rt_all_pmc <- function(filename) {

  # A lot of the PMC XML files are malformed
  article_xml <- tryCatch(.get_xml(filename, FALSE), error = function(e) e)

  if (inherits(article_xml, "error")) {
     return(tibble::tibble(filename, is_success = F))
  }

  dict <- .create_synonyms()
  id_ls <- .get_ids(article_xml)
  id_ls$filename <- filename

  meta_ls <- .xml_metadata_lean(article_xml, as_list=T)
  pmc_fund_ls <- .get_fund_pmc(article_xml, dict)
  pmc_data_ls <- .get_data_pmc(article_xml, filename)
  article_ls <- .get_article_txt(article_xml)

  fund_out <- .rt_fund_pmc(article_ls, pmc_fund_ls)
  fund_ls <- purrr::list_modify(pmc_fund_ls, !!!fund_out)

  status_ls <- list(is_success = T)

  a <- tibble::as_tibble(c(id_ls, meta_ls, fund_ls, status_ls, pmc_data_ls))
  
  print(filename)
  return(a)
}
