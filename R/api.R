#' Fetch the base URL and port for cromwell server
#'
#' The Cromwell server presents a RESTFul API. The base URL is of the form:
#' `http://EXAMPLE.COM:PORT`. The current approach to changing that
#' url is to set an option, `cromwell_base` to a valid URL (without trailing slash).
#' This URL will then be used throughout the `cRomwell` package.  If no option is set,
#' the server is assumed to be running at `http://localhost:8000`.
#'
#' @export
#' @examples
#' cromwell_base()
#'
#' # set a bogus host
#' options('cromwell_base' = 'http://example.com:8111')
#' cromwell_base()
#'
#' # and set back to NULL to get the default behavior
#' options('cromwell_base' = NULL)
#' cromwell_base()
cromwell_base <- function() {
    base_url = getOption('cromwell_base', default="http://localhost:8000")
    return(base_url)
}

#' Perform a GET request to cromwell server
#'
#' See the docmentation at \href{https://github.com/broadinstitute/cromwell#rest-api}{the cromwell github site} for details. Generally, this is not meant to be called by the end user. Rather, use the endpoint-specific functions. See \code{\link{cromwell_base}} for details of setting the base URL and port.
#'
#' @param path The path part of the URL
#' @param query Any query terms as a named character vector
#' @param ... passed directly to httr `POST` (for including `timeouts`, `handles`, etc.)
#'
#' @importFrom httr modify_url
#' @importFrom httr GET
#'
cromwell_GET <- function(path,query=NULL,...) {
    url <- modify_url(cromwell_base(), path = path, query = query)
    resp <- GET(url,...)
    return(.cromwell_process_response(resp))
}

#' Perform a POST request to cromwell server
#'
#' See the docmentation at \href{https://github.com/broadinstitute/cromwell#rest-api}{the cromwell github site} for details. Generally, this is not meant to be called by the end user. Rather, use the endpoint-specific functions.
#'
#' @param path The path part of the URL
#' @param body A list that will become the multipart form that is passed as the request body
#' @param ... passed directly to httr `POST` (for including `timeouts`, `handles`, etc.)
#'
#' @importFrom httr modify_url
#' @importFrom httr POST
#'
#' @seealso \code{\link{cromwellBatch}}
#'
cromwell_POST = function(path,body,...) {
    url = modify_url(cromwell_base(), path = path)
    resp = POST(url, body = body, ...)
    return(.cromwell_process_response(resp))
}

#' Check cromwell response
#'
#' @param resp a \code{\link{response}} object
#'
#' @return a simple list that includes the actual `content` and the complete `response` object.
#'
#' @import httr
#'
.cromwell_process_response = function(resp) {
    if (http_type(resp) != "application/json") {
        stop("API did not return json", call. = FALSE)
    }

    parsed <- httr::content(resp,'parsed')

    if (status_code(resp) != 200) {
        stop(
            sprintf(
                "Cromwell API request failed [%s]\n%s\n<%s>",
                status_code(resp),
                parsed$message,
                parsed$documentation_url
            ),
            call. = FALSE
        )
    }

    structure(
        list(
            content = parsed,
            response = resp
        ),
        class = c("cromwell_api")
    )
}

#' Get the info about cromwell workflows
#'
#' @param terms terms about the workflow
#' @param ... passed directly to httr `GET` (for including `timeouts`, `handles`, etc.)
#'
#' @details
#' Each of the following terms can be specified one or more times. Simply create a named list
#' or named character vector.
#' \describe{
#'   \item{name}{The name of a job; may be specified more than once}
#'   \item{status}{one of Succeeded, Failed, Running}
#'   \item{id}{an id of a cromwell job}
#'   \item{start}{a timestamp of the form "2015-11-01T07:45:52.000-05:00", including mandatory offset}
#'   \item{end}{a timestamp of the form "2015-11-01T07:45:52.000-05:00", including mandatory offset}
#'   \item{page}{if paging is used, what page to select}
#'   \item{pagesize}{if paging is used, how many records per page}
#' }
#'
#' @return a data.frame of query results
#'
#' @importFrom httr GET
#' @importFrom plyr rbind.fill
#'
#' @examples
#' #cromwellQuery(terms=c(status='Succeeded',name='taskName'))
#' @export
cromwellQuery = function(terms=NULL, ...) {
    path = 'api/workflows/v1/query'
    resp = cromwell_GET(path=path,query=terms)

    x = do.call(rbind.fill,lapply(resp$content$results,as.data.frame))
    if('start' %in% colnames(x))
        x$start = strptime(substr(as.character(x$start),1,19),format="%Y-%m-%dT%H:%M:%S",tz="UTC")
    else
        x$start = NA
    if('end' %in% colnames(x))
        x$end = strptime(substr(as.character(x$end),1,19),format="%Y-%m-%dT%H:%M:%S",tz="UTC")
    else
        x$end = NA
    x$duration = x$end-x$start
    attr(x,'when') = Sys.time()
    attr(x,'path') = path
    class(x) = c('cromwell_query','cromwell_api','data.frame')
    return(x)
}


#' Get metadata associated with one or more workflow ids
#'
#' @param id A cromwell id as a string
#' @param ... passed directly to httr `GET` (for including `timeouts`, `handles`, etc.)
#'
#' @return a list of metadata lists
#'
#' @importFrom httr GET
#'
#' @examples
#' #cromwellMetadata(ids='INSERT_HASH_HERE')
#' @export
cromwellMetadata = function(id, ...) {
    path=sprintf('api/workflows/v1/%s/metadata',id)
    resp = cromwell_GET(path = path, ...)

    x = resp$content
    attr(x,'when') = Sys.time()
    attr(x,'path') = path
    class(x) = c('cromwell_metadata','cromwell_api')
    x
}

#' Abort a cromwell job
#'
#' @param id A cromwell id as a string
#' @param ... passed directly to httr `GET` (for including `timeouts`, `handles`, etc.)
#'
#' @importFrom httr GET
#'
#' @examples
#' #cromwellQuery(ids=c('1','2','abc'))
#' @export
cromwellAbort = function(id, ...) {
    return(cromwell_GET(path=sprintf('api/workflows/v1/%s/abort')))
}

#' Get output paths associated with one or more workflow ids
#'
#' @param id a cromwell job id
#' @param ... passed directly to httr `POST` (for including `timeouts`, `handles`, etc.)
#'
#' @return a list of output lists
#'
#' @importFrom httr GET
#'
#' @examples
#' #cromwellOutputs(ids)
#' @export
cromwellOutputs = function(id, ...) {
    path = sprintf('api/workflows/v1/%s/outputs', id)
    resp = cromwell_GET(path = path)
    ret = resp$content
    attr(ret,'path') = path
    attr(ret,'when') = Sys.time()
    class(ret) = c('cromwell_logs','cromwell_api',class(ret))
    return(ret)
}



#' Get output paths associated with one or more workflow ids
#'
#' @param id a cromwell job id
#' @param ... passed directly to httr `POST` (for including `timeouts`, `handles`, etc.)
#'
#' @return a list of logfile lists
#'
#' @importFrom httr GET
#'
#' @examples
#' #cromwellLogs(id)
#' @export
cromwellLogs = function(id, ...) {
    path = sprintf('api/workflows/v1/%s/logs', id)
    resp = cromwell_GET(path = path)
    ret = resp$content$calls
    attr(ret,'path') = path
    attr(ret,'when') = Sys.time()
    class(ret) = c('cromwell_api',class(ret))
    return(ret)
}


#' Submit a cromwell batch job
#'
#' This function submits a set of one or more inputs to cromwell. It is much more efficient
#' than submitting a single job at a time.  See
#' \href{https://github.com/broadinstitute/cromwell#post-apiworkflowsversionbatch}{the cromwell \code{batch} API documentation} for details.
#'
#' @param wdlSource Represents the \href{https://software.broadinstitute.org/wdl/}{WDL}A string (character vector of length 1)
#'   or an \code{\link[httr]{upload_file}} object. See details below.
#' @param workflowInputs A \code{data.frame} that will be coerced to a json array or a JSON string (as a \code{character} vector of length 1),
#'   or an \code{\link[httr]{upload_file}} object. See details below.
#' @param workflowOptions A \code{list}, a JSON string (as a \code{character} vector of length 1,
#'   or an \code{\link[httr]{upload_file}} object. See details below.
#' @param timeout The number of seconds to wait for a response. Batch jobs can take
#'   quite some time for cromwell to process, so this will typically need to be set
#'   to a large value to allow for a completed response.
#' @param ... passed directly to httr `POST` (for including `timeouts`, `handles`, etc.)
#'
#' @return If a timeout does not occur (this is pretty common....), then a list that contains the submission status.
#'
#' @details TODO details
#'
#' @importFrom jsonlite toJSON
#'
#' @export
cromwellBatch = function(wdlSource,
                         workflowInputs,
                         workflowOptions=NULL,
                         timeout = 120,
                         ...) {
    if(!(is.data.frame(workflowInputs) | (is.character(workflowInputs) & length(workflowInputs)==1)))
        stop('workflowInputs should be a data.frame or a character vector of length 1')
    if(is.data.frame(workflowInputs))
        inputs = toJSON(workflowInputs)
    else
        inputs = workflowInputs
    opts = workflowOptions
    if(!is.null(workflowOptions)) {
    if(!(is.list(workflowOptions) | (is.character(workflowOptions) & length(workflowOptions)==1)))
        stop('workflowOptions should be a data.frame or a character vector of length 1')
    if(is.list(workflowOptions))
        opts = toJSON(workflowOptions)
    else
        opts = workflowOptions
    }
    body = list(wdlSource       = wdlSource,
                workflowInputs  = inputs,
                workflowOptions = opts)

    return(cromwell_POST('/api/workflows/v1/batch',body = body, encode = 'multipart',
                timeout(timeout), ...))
}


#' List available backends for a cromwell endpoint
#'
#' @param ... passed directly to httr `GET` (for including `timeouts`, `handles`, etc.)
#'
#' @return a list that includes backend details
#'
#' @importFrom httr GET
#'
#' @examples
#' #cromwellBackends()
#' @export
cromwellBackends = function(...) {
    path = 'api/workflows/v1/backends'
    resp = cromwell_GET(path = path)
    ret = resp$content
    attr(ret,'path') = path
    attr(ret,'when') = Sys.time()
    class(ret) = c('cromwell_backends','cromwell_api',class(ret))
    return(ret)
}

#' Get current statistics for cromwell endpoint
#'
#' @param ... passed directly to httr `GET` (for including `timeouts`, `handles`, etc.)
#'
#' @return a list containing engine stats
#'
#' @importFrom httr GET
#'
#' @examples
#' #cromwellStats()
#' @export
cromwellStats = function(...) {
    path = 'api/engine/v1/stats'
    resp = cromwell_GET(path = path)
    ret = resp$content
    attr(ret,'path') = path
    attr(ret,'when') = Sys.time()
    class(ret) = c('cromwell_stats','cromwell_api',class(ret))
    return(ret)
}


