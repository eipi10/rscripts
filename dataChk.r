# Function to run various data checks on a data table d
# checks is a vector of expressions that if satisfied causes records to be listed
# The variables listed are all variables mentioned in the expression plus
# optional variables whose names are in the character vector id
# %between% c(a,b) in expressions is printed as [a,b]
# The output format is plain text unless html=TRUE which also puts
# each table in a separate Quarto tab (and you must have run
# getRs('maketabs.r', put='source') previously).
# The returned value is an invisible data frame containing variables
# check (the expression checked) and n (the number of records satisfying
# the expression)

dataChk <- function(d, checks, id=character(0), html=FALSE) {
s  <- NULL
ht <- list()

for(i in 1 : length(checks)) {
  x <- checks[i]
  cx <- as.character(x)
  cx <- gsub('%between% c\\((.*?)\\)', '[\\1]', cx)
  form <- as.formula(paste('~', cx))
  # Find all variables mentioned in expression
  vars.involved <- all.vars(form)
  z <- d[eval(x), c('id', vars.involved), with=FALSE]
  no <- nrow(z)
  if(html) ht[[cx]] <- 
    if(no == 0) htmltools::HTML('n=0')
     else knitr::kable(z, caption=paste(cx, '   n=', no))
  else {
  cat('-----------------------------------------------------------------------\n',
      cx, '    n=', no, '\n',
      if(no > 0)
      '-----------------------------------------------------------------------\n', sep='')
  if(no > 0) print(z)
  }
  s <- rbind(s, data.frame(check=cx, n=no))
}
if(html) maketabs(ht, initblank=TRUE)
invisible(s)
}