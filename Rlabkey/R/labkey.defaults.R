##
#  Copyright (c) 2016-2018 LabKey Corporation
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
##

.lkdefaults <- new.env(parent=emptyenv());

# Set the credentials used for all http or https requests
# For now, just apiKey and baseUrl. TODO: Add email, password, folderPath, and maybe curlOptions & lkOptions
labkey.setDefaults <- function(apiKey="", baseUrl="")
{
    if (apiKey != "")
        .lkdefaults[["apiKey"]] = apiKey;
    if (baseUrl != "")
        .lkdefaults[["baseUrl"]] = baseUrl;
    # for backward compatibility, clear defaults if setDefaults() is called with NO arguments
    if (apiKey == "" && baseUrl=="")
      .lkdefaults <- new.env(parent=emptyenv());
}

ifApiKey <- function()
{
    if (exists("labkey.apiKey", envir = .GlobalEnv)) {
        get("labkey.apiKey", envir = .GlobalEnv)
    } else {
        .lkdefaults[["apiKey"]];
    }
}

labkey.getBaseUrl <- function(baseUrl=NULL)
{
    if (!is.null(baseUrl) && baseUrl != "")
    {
        # set the baseUrl if unset
        if (is.null(.lkdefaults[["baseUrl"]]))
        {
            .lkdefaults[["baseUrl"]] = baseUrl
        }
        url <- baseUrl
    }
    else
    {
        url <- .lkdefaults[["baseUrl"]]
    }

    if (is.null(url))
        stop (paste("baseUrl is null or has not been set yet."))

    ## convert any backslashes to forward slashes, ensure terminating slash
    url <- gsub("[\\]", "/", url)
    if(substr(url, nchar(url), nchar(url))!="/")
    {
        url <- paste(url,"/",sep="")
    }
    return (url)
}

## helper to encode and normalize the folder path parameter
encodeFolderPath <- function(folderPath=NULL)
{
    if (!is.null(folderPath))
    {
        ## URL encoding of folderPath
        folderPath <- URLencode(folderPath)

        folderPath <- normalizeSlash(folderPath)
    }
    return (folderPath)
}

normalizeSlash <- function(folderPath, leading = T, trailing = T) {
  ## Formatting
  folderPath <- gsub("[\\]", "/", folderPath)
  
  if (trailing) {
    if(substr(folderPath, nchar(folderPath), nchar(folderPath))!="/")
      folderPath <- paste(folderPath,"/",sep="")
  } else {
    if(substr(folderPath, nchar(folderPath), nchar(folderPath))=="/")
      folderPath <- substr(folderPath,1, nchar(folderPath)-1)
  }
  
  if (leading) {
    if(substr(folderPath, 1, 1)!="/")
      folderPath <- paste("/",folderPath,sep="")
  } else {
    if(substr(folderPath, 1, 1)=="/")
      folderPath <- substr(folderPath,2, nchar(folderPath))
  }
  
  return(folderPath)
}

## helper to retrieve and cache the CSRF token
labkey.getCSRF <- function()
{
    if (is.null(.lkdefaults[["csrf"]]))
    {
        urlBase <- labkey.getBaseUrl()
        if (!is.null(urlBase))
        {
            if (substr(urlBase, nchar(urlBase), nchar(urlBase))!="/")
            {
                urlBase <- paste(urlBase,"/",sep="")
            }
            myUrl <- paste(urlBase, "login/", "whoAmI.view", sep="")
            options = labkey.getRequestOptions()
            verboseOutput("OPTIONS", options)
            if (!is.null(.lkdefaults[["debug"]]) && .lkdefaults[["debug"]] == TRUE)
                response <- GET(url=myUrl, config=options, verbose(data_in=TRUE, info=TRUE, ssl=TRUE))
            else
                response <- GET(url=myUrl, config=options)
            r <- processResponse(response, haltOnError=FALSE)
            json <- fromJSON(r, simplifyVector=FALSE, simplifyDataFrame=FALSE)
            if (!is.null(json$CSRF))
            {
                .lkdefaults[["csrf"]] = json$CSRF
            }
        }
    }
    return (.lkdefaults[["csrf"]])
}

labkey.getRequestOptions <- function(method='GET', encoding=NULL)
{
    ## Set options
    headerFields <- c()
   if (method == "POST")
   {
       if (is.null(encoding) || encoding != "multipart")
           headerFields <- c('Content-Type'="application/json;charset=utf-8")
   }

    options <- labkey.curlOptions()

    ## Support user-settable options for debugging and setting proxies etc
    if(exists(".lksession"))
    {
        userOpt <- .lksession[["curlOptions"]]
        if (!is.null(userOpt))
            options <- c(options, config(userOpt))
    }

    clist <- ifcookie()
    if(clist$Cvalue==1)
    {
        # don't use the httr wrapper because it URL encodes the cookie value
        cook <- config(cookie = paste(clist$Cname, "=", clist$Ccont, sep=""))
        options <- c(options, cook)
    }
    else
    {
        if (method == "GET")
            options <- c(options, config(httpauth=1L))
        apikey <- ifApiKey();
        if (!is.null(apikey))
        {
            headerFields <- c(headerFields, apikey=apikey)
        }
        else
        {
            options <- c(options, config(netrc=1))
        }
    }

    if (method == "POST")
    {
        ## CSRF
        csrf <- labkey.getCSRF()
        if (!is.null(csrf))
            headerFields <- c(headerFields, "X-LABKEY-CSRF" = csrf)
    }
    o <- c(options, add_headers(headerFields))
    return (c(options, add_headers(headerFields)))
}

## Executes an HTTP GET against the supplied URL, with standard handling for session, api key, status codes and error messages.
labkey.get <- function(myurl)
{
    ## HTTP GET
    options <- labkey.getRequestOptions(method="GET")
    verboseOutput("OPTIONS", options)
    if (!is.null(.lkdefaults[["debug"]]) && .lkdefaults[["debug"]] == TRUE)
        response <- GET(url=myurl, config=options, verbose(data_in=TRUE, info=TRUE, ssl=TRUE))
    else
        response <- GET(url=myurl, config=options)
    processResponse(response)
}

## Executes an HTTP POST of pbody against the supplied URL, with standard handling for session, api key, status codes and error messages.
labkey.post <- function(myurl, pbody, encoding=NULL, responseType=NULL, haltOnError=TRUE)
{
    ## HTTP POST form
    options <- labkey.getRequestOptions(method="POST", encoding=encoding)
    verboseOutput("OPTIONS", options)
    if (!is.null(.lkdefaults[["debug"]]) && .lkdefaults[["debug"]] == TRUE)
        response <- POST(url=myurl, config=options, body=pbody, verbose(data_in=TRUE, info=TRUE, ssl=TRUE))
    else
        response <- POST(url=myurl, config=options, body=pbody)
    processResponse(response, responseType = responseType, haltOnError = haltOnError)
}

processResponse <- function(response, haltOnError=TRUE, responseType = NULL)
{
    if(isRequestError(response))
    {
      handleError(response, haltOnError)
    }
    content(response, as = "text", type = responseType)
}

labkey.setDebugMode <- function(debug=FALSE)
{
    .lkdefaults[["debug"]] = debug;
}

isRequestError <- function(response, status_code) 
{
  status_code <- getStatusCode(response)
  
  return(status_code==500 | status_code >= 400)
}

getStatusCode <- function(response) 
{
  ## Error checking, decode data and return
  status_code <- response$status_code
  
  #test for the situations where the header reports 200, but the JSON contains the error:
  if (sum(grepl('application/json', response$headers[['content-type']])) > 0) {
    c <- content(response, type = "application/json")
    if (!is.null(c[['status']])) {
      status_code <- c$status
    }
  }

  return(status_code)  
}

handleError <- function(response, haltOnError) 
{
  status <- http_status(response)
  message = status$message
  
  ## pull out the error message if possible
  error <- content(response, type = "application/json")
  if (!is.null(error$exception))
  {
    message <- error$exception
  }
  if (haltOnError) {
    status_code <- getStatusCode(response)

    # Note: is this request was writing to a file, the error message JSON will be written to that file, so we delete.  
    if (inherits(response$content, 'path')) {
      if (file.exists(response$content)){
        unlink(response$content)  
      } 
    }

    stop (paste("HTTP request was unsuccessful. Status code = ", status_code, ", Error message = ", message, sep=""))
  }
}

verboseOutput <- function(title, content)
{
    if (!is.null(.lkdefaults[["debug"]]) && .lkdefaults[["debug"]] == TRUE) {
        print(paste("*******************BEGIN ",title,"*******************", sep=""))
        print(content)
        print(paste("*******************END ",title,"*********************", sep=""))
    }
}