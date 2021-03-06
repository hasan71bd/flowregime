#' IHA Environmental Flow Components
#'
#' Compute the IHA Environmental Flow Components (EFCs).
#'
#' @param ts A time series of class \code{xts}.
#' @param method The method used to compute environmental flow components:
#'   may be either 'standard' or 'advanced'.
#' @param thresholds A list containing all or some of the following elements:
#' @return A copy of \code{ts} with an additional column containing EFC labels.
#'
#' @examples
#' data(roanokerapids)
#' EFC(roanokerapids)
#' EFC(roanokerapids, method = "advanced")
#'
#' @export
EFC = function(ts, method = c("standard", "advanced"), thresholds){
  method = match.arg(tolower(method), c("standard", "advanced"))
  if(missing(thresholds))
    thresholds = build_EFC_thresholds(ts, method)
  if(method == "standard")
    res = EFC_standard(coredata(ts), thresholds)
  else
    res = EFC_advanced(coredata(ts), thresholds)
  xts(res, order.by = index(ts))
}

efc_high_classes = function(thresholds){
  highclasses = list("high flow" = "high flow pulse", 
    "small flood minimum peak flow" = "small flood", 
    "large flood minimum peak flow" = "large flood")
  classes = highclasses[names(highclasses) %in% names(thresholds)]
  message("High flow classes specified: ", paste(classes, 
    collapse = ", "))
  classes
}
efc_low_classes = function(thresholds){
  lowclasses = list("extreme low flow" = "low flow pulse")
  classes = lowclasses[names(lowclasses) %in% names(thresholds)]
  message("Low flow classes specified: ", paste(c("low flow", classes), 
    collapse = ", "))
  classes    
}


EFC_standard = function(f, thresholds){
  if(!all(c("high flow") %in% names(thresholds)))
    stop("Missing elements in argument 'thresholds'.")
  highclasses = efc_high_classes(thresholds)
  lowclasses = efc_low_classes(thresholds)
  res = rep("low flow", length(f))
  for(i in names(highclasses)[order(unlist(thresholds[names(highclasses)]))])
    res[f >= thresholds[[i]]] = highclasses[[i]]
  if(length(lowclasses) > 0)
    for(i in names(lowclasses)[order(unlist(thresholds[names(lowclasses)]))])
      res[f <= thresholds[[i]]] = i
  res  
}

EFC_advanced = function(f, thresholds){
  if(!all(c("high flow", "low flow", "high flow start rate", 
    "high flow end rate") %in% names(thresholds)))
    stop("Missing elements in argument 'thresholds'.")
  highclasses = efc_high_classes(thresholds)
  lowclasses = efc_low_classes(thresholds)
  res = rep("low flow", length(f))
  # initial
  if(f[1] > thresholds[["low flow"]])
    if(f[1] > thresholds[["high flow"]])
      res[1] = "ascending limb"
    else
      res[1] = "descending limb"
  # first pass: assign low flow, ascending limb, descending limb
  for(i in seq(2, length(res))){
    if(res[i - 1] == "low flow"){
      if(f[i] > thresholds[["high flow"]] ||
        f[i] > f[i-1]*thresholds[["high flow start rate"]])
        res[i] = "ascending limb"
      else
        res[i] = "low flow"
    }
    if(res[i-1] == "ascending limb"){
      if(f[i] < thresholds[["low flow"]])
        res[i] = "low flow"
      else if(f[i] < f[i-1]*thresholds[["high flow end rate"]])
        res[i] = "descending limb"
      else
        res[i] = "ascending limb"
    }
    if(res[i-1] == "descending limb"){
      if(f[i] < thresholds[["low flow"]])
        res[i] = "low flow"      
      else if(f[i] > f[i-1]*thresholds[["high flow start rate"]])
        res[i] = "ascending limb"
      else if(f[i] > thresholds[["high flow"]])
        res[i] = "descending limb"
      else if(f[i] < f[i-1]*thresholds[["high flow end rate"]])
        res[i] = "low flow"
      else
        res[i] = "descending limb"
    }
  }
  # second pass
  highs = res %in% c("ascending limb", "descending limb")
  idx = 1 + cumsum(!highs)
  pulses = split(seq_along(res)[highs], idx[highs])
  peaks = lapply(pulses, function(x) max(f[x]))
  for(i in names(highclasses)[order(unlist(thresholds[names(highclasses)]))])
    for(j in seq_along(pulses)){
      res[pulses[[j]]] = "high flow pulse"
      if(peaks[[j]] > thresholds[[i]])
        res[pulses[[j]]] = highclasses[[i]]
    }
  # third pass
  if(length(lowclasses) > 0)
    for(i in names(lowclasses)[order(unlist(thresholds[names(lowclasses)]))])
      res[f <= thresholds[[i]]] = i
  res
}

#' Default thresholds for EFC Analysis
#'
#' @param ts A time series of class \code{xts}.
#' @param method The method used to compute environmental flow components:
#'   may be either 'standard' or 'advanced'.
#' @return a list containing the following thresholds:
#'
#'
#' @seealso \link{EFC}
#'
#' @export
build_EFC_thresholds = function(ts, method = c("standard", "advanced")){
  method = match.arg(tolower(method), c("standard", "advanced"))
    if(method == "standard")
      list(
        "high flow" = quantile(coredata(ts), 0.75)[[1]],
        "extreme low flow" = quantile(coredata(ts), 0.10)[[1]]
      )
    else
      list(
        "high flow" = quantile(coredata(ts), 0.75)[[1]],
        "low flow" = quantile(coredata(ts), 0.50)[[1]],
        "high flow start rate" = 1.25,
        "high flow end rate" = 0.9,
        "small flood minimum peak flow" = quantile(coredata(apply.yearly(ts, max)), 
          0.5, type = 6)[[1]],
        "large flood minimum peak flow" = quantile(coredata(apply.yearly(ts, max)), 
          0.9, type = 6)[[1]],
        "extreme low flow" = quantile(coredata(ts), 0.10)[[1]]
      )
}

#' Check EFC Thresholds
#'
#' Check the suitability of EFC thresholds. If thresholds result in classes 
#' outside the range of values in the pre-impact dataset for any parameter, 
#' a warning will be issued.
#'
#' @param efcthresh The EFC thresholds, as defined by e.g. 
#'   \code{build_EFC_thresholds(...)}.
#' @param ts The time series that the EFC thresholds will be applied to.
#' @return A dataframe of 3 columns:
#'
#' @export
check_EFC_thresholds = function(efcthresh, ts){

}

