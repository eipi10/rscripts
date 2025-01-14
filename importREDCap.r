# title: Function to clean up REDCap dataset exported to R
# major: data manipulation
# minor: import
#
importREDCap <- function(file=NULL, pr=TRUE) {

## Purpose: Process the two files exported from REDCap exactly as they
## were created by REDCap: the R script and the data .csv file.  Remove
## unnecessary variables and convert date variables to R Date variables.
##
## Given file (the name of the REDCap exported R script)
##
## 1. Runs the R script created by REDCap, which calls read.csv to
##    input the data.  Ignores lines containing rm(list=ls()) and
##    graphics.off()
## 2. Removes all original non-factor versions of variables that also exist
##    as factors
## 3. Renames factorized versions of variables by dropping .factor from the
##    end of the name
## 4. Converts any character or factor variable that other than blanks and
##    NAs contains only valid dates as judged by the as.Date function
##    (i.e., yyyy-mm-yy) to R Date variables, keeping the original label
## 5. Adds as a "codes" attribute to all factor variables the vector of
##    original codes of the variable in REDCap before value labels were
##    applied by factor()
## 6. Changes any factor variable having at least n/2 levels, where n is
##    number of observations, to a character vector
##
## If file is not given, the last created file containing _R_*.r at the end
## of its name is used.  Specify pr=FALSE to suppress printing of
## information about the conversion process.
##
## Example: mydata <- importREDCap()
##          Save(mydata)    # creates mydata.rda
##
## Requires Hmisc

  if(! length(file)) {
    possfiles <- file.info(list.files(pattern=".*_R_.*\\.r$"))
    if(nrow(possfiles) == 0) stop('no qualifying R scripts found')
    ## Find newest qualifying file
    file <- rownames(possfiles)[order(possfiles$mtime, decreasing=TRUE) == 1]
    if(pr) cat('Running', file, '\n')
  }
  ## Override factor function to make a version that retains the original
  ## levels as the "codes" attribute
  factor <- function(x, levels, ...) {
    z <- base::factor(x, levels, ...)
    attr(z, 'codes') <- all.is.numeric(levels, what='vector')
    z
  }
  f <- readLines(file)
  f <- f[f %nin% c('rm(list=ls())', 'graphics.off()')]
  eval(parse(text=f))   ## runs scripts, creates object data
  
  n <- names(data)
  delete <- integer(0)
  old <- options(warn = -1)
  on.exit(options(old))
  for(i in 1 : length(n)) {
    ni  <- n[i]
    w   <- data[[i]]
    lab <- label(w)
    if(is.character(w) || is.factor(w)) {
      k <- ! (is.na(w) | w == '')
      if(! any(k)) next
      if(is.factor(w) && length(levels(w)) > 0.5 * length(w)) {
        w <- as.character(w)
        label(w) <- lab
        data[[i]] <- w
      }
      w <- as.character(w)
      if(! all(grepl('^[1-2][0-9][0-9][0-9]-[0-1]*[0-9]-[0-3]*[0-9]$',
                     w[k]))) next
      dat <- tryCatch(as.Date(ifelse(w == '', NA, w), error=function(x) x))
      if(inherits(dat, 'error')) next
      label(dat) <- lab
      data[[i]]  <- dat
    }
    ## See if current variable has a factor-ized version
    if(! grepl('\\.factor', ni)) {
      j <- which(gsub('\\.factor', '', n) == ni)
      if(length(j) > 2) stop('more than 2 variables have the same base name')
      if(length(j) == 2) {
        delete <- c(delete, i)
        j <- setdiff(j, i)
        ## Label the .factor version of the variable; these aren't labeled
        label(data[[j]]) <- lab
      }
    }
  }
  if(length(delete)) {
    if(pr) {
      cat('\nVariables deleted because same variable exists as factor:\n',
          paste(names(data)[delete], sep=','), '\n\n')
      cat('(.factor removed from names of factor version)\n')
    }
    data <- data[, -delete]
  }
  n <- names(data)
  names(data) <- gsub('\\.factor', '', n)
  data
}



cleanupREDCap <- function(d, mchoice=TRUE, rmhtml=TRUE, rmrcl=TRUE,
                          toPOSIXct=FALSE, cdatetime=NULL,
                          mod=FALSE, dsname=NULL,
                          entrydate=NULL, id=NULL,
                          drop=NULL, check=TRUE, fixdt=FALSE, propdt=0.5,
                          byref=TRUE, ...) {
  # Purpose: Clean up a data table imported from REDCap using either
  # manual export or API.  By default removes html tags from variable
  # labels and converts sequences of variables representing a single
  # multiple choice question to a single variable using Hmisc::mChoice.
  # Even if rmhtml=FALSE, any label with the only html being <p>...</p>
  # will have <p> and </p> stripped.
  #
  # See https://hbiostat.org/rflow/fcreate#sec-fcreate-import
  #
  # Before the first dataset is run through cleanupREDCap, set an object
  # named crednotes to NULL if you run a sequence of forms more than once
  # in the same session.  cleanupREDCap will initialize crednotes to NULL
  # the very first time cleanupREDCap is called in a session.
  # For changes made to variables, a data frame
  # row will be added to crednotes.  Columns are the optional value
  # of dsname (dataset name), name (variable name), description (generic
  # description of the change) and details (specific change details).
  # When mod is specified it contributes to these records.
  # Removal of html from labels and handling of redcapFactor are not recorded.
  #
  # By default REDCap labels and levels and the redcapFactor class
  # are removed.  Set rmrcl=FALSE to not remove these.
  # You can get this information by exporting REDCap metadata.
  #
  # Multiple choice variables are found by looking for variable names
  # that end in three underscores followed only by integers
  #
  # Per https://stackoverflow.com/questions/21487614 POSIXlt does not
  # work with data.table.  Set toPOSIXct=TRUE to convert any
  # POSIXlt class variables to POSIXct.  Note that data.table()
  # converts POSIXlt POSIXt variables to POSIXct POSIXt automatically,
  # with a warning, so this option is seldom needed.
  #
  # cdatetime is a vector of alternating names of date and time variables
  # that are to be combined into a date-time variable, and the time variable
  # dropped.
  # 
  # mod is a list specifying modifications to be made to variables.  The elements
  # of mod are lists, and each list must be named by a description of the change.
  # Each inner list has these components: the name of the variable to which the
  # change applies (this may also be a regular expression for partial name
  # matching), a function affecting the change, an optional element
  # named ignore.case which defaults to FALSE for name matching, and an optional
  # element regex which defaults to FALSE for name matching.  Set regex to TRUE
  # to match using grep().
  # Here is an example where a variable named age ignoring case is
  # truncated at 90 years, and a variable containing 'zip' (case-sensitive)
  # in its name is modified to keep only the first 3 digits of the code.
  # Zip codes that are numeric are first zero-padded on the left.
  #
  # ziptrunc <- function(x) {
  #              if(is.numeric(x)) stop('zip code should have been a character variable because of leading zeros')
  #              substring(x, 1, 3) }
  # mod = list('truncate age at 90'=list('age', function(x) pmin(x, 90), ignore.case=TRUE),
  #       list('keep first 3 digits of zip code'=list('zip', ziptrunc, regex=TRUE) )
  #
  # entrydate is an optional vector specifying how to replace date or date/time variables
  # with days and fraction of a day from a subject-specify entry date or date/time.  When
  # specifying entrydate you must also specify id which is a formula with a single
  # variable on the right side naming the ID variable in dataset d. If the id variable
  # contains integers 1, 2, 3, ... entrydate need not have named elements, and the
  # entry dates will be looked up using subject ID as an integer subscript into it.
  # If the id variable does not contain consecutive integers starting at 1, it needs
  # to be a character vector, and entrydate must have these id values as
  # vector element names.  All dates and date/times in the dataset will have their
  # corresponding subject's entry date subtracted from them and the result stored as days
  # plus possible fractions of a day since the entry date.
  # This is applied after cdatetime is applied, if present.
  #
  # Set check=TRUE to check that variables whose names contain "dat" or "tim" are
  # already marked as being date or time variables by their R class.  This checking
  # is done before other date/time processing is done but after drop= is processed.
  # Case is ignored.  When check=TRUE, results of checks are appended to
  # crednotes.
  # Also when check=TRUE you have the option of specifying fixdt=TRUE.
  # When a character variable with dat or tim in its name is a legal
  # date-time, date, or time variable more than propdt of the time,
  # the variable will be converted to one of those numeric types and
  # this is noted in crednotes.  Illegal values are set to NA and are set
  # as special missing values that are tabulated with Hmisc::describe().
  #
  # drop is an optional vector of variable names to remove from the dataset.
  # It is OK for drop to contain variables not present; these names are ignored.
  #
  # By default changes are made in-place (byref=TRUE).  To make changes in a
  # copy of the dataset (which in this case may also be a data.frame),
  # set byref=FALSE.  
  #
  # ... arguments are passed to mChoice
  #
  # cleanupREDCap does its changes to data tables by reference.
  # It returns a character vector of the distinct changes made
  # to the data table if byref=TRUE, or puts this as the 'changes'
  # attribute of the returned data.table if byref=FALSE.

  require(data.table)
  if(byref) {
    if(! is.data.table(d)) stop('dataset must be a data table')
    }  else {
      d <- copy(d)
      setDT(d)
      }

# Set missing or blank times to noon, then concatenate date and time character strings
# Convert character to POSIXlt/POSIXt date/time variable, adding mid day
# Check that missingness of result is same as missingness of date
# Transfer label of date to resulting variable
# See https://stackoverflow.com/questions/21487614

  combdt <- function(a, b, aname, bname) {
	  if(! requireNamespace('chron', quietly=TRUE))
		  stop('chron package must be installed to combine dates and times')
    # x <- data.frame(a, b)
    # names(x) <- c(aname, bname)
    # saveRDS(x, file='combdttest.rds')
    if(! inherits(b, 'times'))
      stop(paste(bname), 'must be a chron times variable')
    a[trimws(a) == ''] <- NA
    b[trimws(b) == ''] <- NA
    ao <- a
    bo <- b
    ## Sometimes the imported variable is changed to character
    if(! is.numeric(b)) {
      bat <- attributes(b)
      b   <- suppressWarnings(as.numeric(b))
      bad <- bo[is.na(b) & ! is.na(bo)]
      if(length(bad))
        cat('\nbad time values in ', bname, ' set to noon:',
            paste(bad, collapse=', '), '\n', sep='')
      attributes(b) <- bat
      }
    
    b[(! is.na(a)) & is.na(b)] <- '12:00:00'
    x <- paste(a, b)   # will not work for b unless chron is loaded
    x[is.na(a)] <- NA
    y <- as.POSIXct(x, format='%Y-%m-%d %H:%M:%S')
    # j <- which(! is.na(y))
    # cat('\n'); print(data.frame(Date=a, Time=b, Combined=y)[j[1:5], ])
    j <- is.na(y) != is.na(a)
    if(any(j)) {
      cat('\n')
      print(as.data.frame(table(is.na(a), is.na(b), is.na(y))))
      stop('missingness of date/time variables ',
           aname, ' ', bname,
           ' does not match that in original dates')
    }
    label(y) <- label(ao)
    y
  }

  cred <- NULL

  if(length(drop)) {
    todrop <- intersect(names(d), drop)
    if(length(todrop)) {
      d[, (todrop) := NULL]
      cred <- rbind(cred,
                    data.frame(name = todrop,
                               description = 'dropped', details='') )
      }
  }

  n <- names(d)
  
  if(check) {
    pcla <- function(i) {
      cl <- d[, sort(unique(unlist(lapply(.SD, class)))), .SDcols=i]
      cl <- setdiff(cl, c('labelled', 'redcapFactor'))
      if(length(cl)) paste(' class:', paste(cl, collapse=','))
    }
    dsnt <- if(length(dsname)) paste(' dataset:', dsname)
    # regular expression finds dat but not data or validation or _
    dats <- n[grepl('dat[^ai_]*$', n, ignore.case=TRUE) |
              grepl('tim',       n, ignore.case=TRUE)]
    dtty <- c('datetime', 'date', 'time')
    if(length(dats)) {
      dvars  <- dats[d[,
                       sapply(.SD, testCharDateTime, existing=TRUE) %nin% dtty,
                       .SDcols=dats] ]
      if(length(dvars)) {
        desc <- 'variables with dat or tim in names are not of date/time type'
        cred <- rbind(cred,
                      data.frame(name        = dvars,
                                 description = desc,
                                 details     = pcla(dvars)))
        if(fixdt)
          for(v in dvars) {
            x <- testCharDateTime(d[[v]], p=propdt, convert=TRUE)
            desc <- 'dat/tim in name, not a date/time variable, converted'
            detail <- paste0('to:', x$type, ' # not convertible:', x$numna,
                             '/', length(x$x))
            if(x$type %nin% c('character', 'notcharacter')) {
              cred <- rbind(cred,
                            data.frame(name=v, description=desc,
                                       details=detail) )
              set(d, j=v, value=x$x)
            }
          }
        }
    }
  }

  if(rmhtml) {
    trans <- markupSpecs$html$totxt
    for(v in names(d)) {
      lab <- attr(d[[v]], 'label')
      if(length(lab)) setattr(d[[v]], 'label', trans(lab))
    }
  } else for(v in names(d)) {
           lab <- attr(d[[v]], 'label')
           if(length(lab)) setattr(d[[v]], 'label',
                                   sub('^<p>(.*?)</p>$', '\\1', lab) )
           }

  if(mchoice) {
    ## Find all variable names that are part of multiple choice sequences
    ## These names end in ___x with x being an integer
    i <- grep('^.*___[0-9][0-9]*[0-9]*$', n)
    i <- grep('^.*___.*$', n)
    if(length(i)) {
      n <- n[i]

      basename <- sub('___[0-9][0-9]*[0-9]*$', '', n)
      basename <- sub('___.*', '', n)
      if(any(basename %in% names(d)))
        stop('base name for multiple choice variable has the same name as a non-multiple choice variable')

      for(v in unique(basename)) {
        V <- n[basename == v]
        numbers    <- sub(paste0('^', v, '___'), '', V)
        if(! all.is.numeric(numbers)) next
        numbers    <- as.integer(numbers)
        numchoices <- length(numbers)
        first <- paste0(v, '___', min(numbers))
        d[, (v) := do.call('mChoice', c(.SD, ...)), .SDcols=V]
        d1 <- d[[first]]
        la <- label(d1)
        # REDCap puts value label of first category at end of variable
        # label; remove it
        le <- setdiff(levels(d1), '')
        if(length(le) == 1) la <- sub(le, '', la, fixed=TRUE)
        # Also remove (Choose all that apply)
        la <- sub('(Choose all that apply)', '', la, fixed=TRUE)
        la <- trimws(la)
        la <- sub('(:|\\.)$', '', la)   # remove trailing : or .
        setattr(d[[v]], 'label', la)
        d[, (V) := NULL]
         cred <- rbind(cred,
                      data.frame(name=v,
                                 description='variables combined into mChoice variable',
                                 details=paste(numchoices, 'original variables')))
      }
    }
  }

  n <- names(d)

  if(rmrcl)
    for(v in n) {
      x <- d[[v]]
      if(inherits(x, 'redcapFactor')) {
        class(x) <- setdiff(class(x), 'redcapFactor')
        attr(x, 'redcapLabels') <- attr(x, 'redcapLevels') <- NULL
        d[, (v) := x]
        }
    }
    
  if(toPOSIXct)
    for(v in n) {
      x <- d[[v]]
      if(inherits(x, 'POSIXlt')) {
        lab <- label(x)
        x   <- as.POSIXct(x)
        d[, (v) := x]
        set(d, j=v, value=x)
        setattr(d[[v]], 'label', lab)
        cred <- rbind(cred, data.frame(name=v, description='POSIXlt -> POSITct',
                                       details='') )
       }
    }

  m <- length(cdatetime)
  if(m) {
    if(m %% 2 != 0) stop('cdatetime must have an even number of elements')
    for(i in seq(1 , m, by=2)) {
      a <- cdatetime[i]
      b <- cdatetime[i + 1]
      nfound <- (a %in% n) + (b %in% n)
      if(nfound == 1) warning('Only one of date and time variables ', a, ' ', b,
                              ' is in the dataset')
      if(nfound == 2) {
        x   <- combdt(d[[a]], d[[b]], a, b)
        cred <- rbind(cred,
                      data.frame(name=a,
                                 description='date and time variables combined',
                                 details=paste0(a, ', ', b, ' -> ', a,
                                                ', ', b, ' dropped')))
        set(d, j=a, value=x)
        set(d, j=b, value=NULL)
      }
    }
  }

  if(length(mod)) for(nm in names(mod)) {
    w   <- mod[[nm]]
    v   <- w[[1]]
    fun <- w[[2]]
    if(! is.character(v) ) stop(paste(v,   'is not a character string'))
    if(! is.function(fun)) stop(paste(fun, 'is not a function'))
    regex <- if('regex' %in% names(w)) w$regex else FALSE
    ig    <- if('ignore.case' %in% names(w)) w$ignore.case else FALSE
    i     <- if(regex) grep(v, n, ignore.case=ig)
             else if(ig) which(tolower(n) == tolower(v)) else which(n == v)
    if(length(i)) for(j in i) {
      x <- d[[j]]
      set(d, j=n[j], value=fun(x))
      lab <- label(x)
      un  <- units(x)
      if(lab != '') setattr(d[[n[j]]], 'label', lab)
      if(un  != '') setattr(d[[n[j]]], 'units', un)
      cred <- rbind(cred,
                    data.frame(name        = n[j],
                               description = 'customized modification',
                               details     = nm))
    }
  }
         
  if(length(entrydate)) {
  if(! length(id)) stop('must specify id = ~ idvar when specifying entrydate')
  idname <- all.vars(id)
  if(length(idname) != 1) stop('There must be one and only one ID variable')
  if(idname %nin% n) stop(paste('ID variable', idname, 'is not in the dataset'))
  if(! inherits(entrydate, c('Date', 'POSIXct')))
    stop('entrydate variable is not a date or date/time')
  id <- d[[idname]]
  if(length(names(entrydate))) {
    j <- id %nin% names(entry)
    if(any(j)) stop(paste('IDs in dataset are not in entrydate names:', paste(id[j], collapse=', ')))
  } else if(! is.numeric(id) || any(id < 1 | id > length(entrydate)))
      stop('ID variable is non-integer or < 1 or > number of elements in entrydate')
  entry <- entrydate[id]
  for(n in names(d)) {
    x <- d[[n]]
    lab <- label(x)
    if(inherits(x, c('Date', 'POSIXct'))) {
      x <- as.numeric(difftime(x, entry))
      units(x) <- 'days'
      set(d, j=n, value=x)
      cred <- rbind(cred,
                    data.frame(name=n,
                               description='changed from date/time to days from entry',
                               details='') )
    }
  }
}
if(length(cred)) {
  if(length(dsname)) cred <- cbind(dsname=dsname, cred)
  if(! exists('crednotes')) crednotes <<- cred
  else                      crednotes <<- rbind(crednotes, cred)
}

  changes <- if(length(cred)) unique(sort(cred$description))
  
  if(byref) return(if(length(changes)) changes else invisible())
  
  attr(d, 'changes') <- changes
  d
}

    
  
