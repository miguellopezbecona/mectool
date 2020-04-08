### rapl_overhead.R. Execute if after running experiment_overhead.sh ###

# Subtracts base values (basedf) to the raw data (df)
build_incr_df <- function(df, basedf){
	nodes <- unique(basedf$node)
	domains <- unique(basedf$domain)

	incr_df <- df
	for(n in nodes){
		for(d in domains){
			b <- basedf[basedf$node == n & basedf$domain == d, 3] # Incr value in third column
			incr_df[incr_df$node == n & incr_df$domain == d, 4] <- incr_df[incr_df$node == n & incr_df$domain == d, 4] - b
		}
	}
	return (incr_df)
}

# Core function that does all the workflow
do_everything <- function(folder, base_filename = "", dump_to_files = FALSE){
	l <- list.files(path = folder, pattern = "p.*.csv")
	if(length(l) == 0){
		print("No files in folder!\n")
		return ()
	}

	periods <- sort(unique(sapply(l, function(fn) as.integer(substring(strsplit(fn, "_")[[1]][1],2)))))

	# Reads base_filename, if provided
	if(base_filename != "")
		basedf <- read.csv(base_filename, header = TRUE) # Energy base consumptions

	# First loops for each period, then for each different measure file for that period
	for(p in periods){
		lsub <- list.files(path = folder, pattern = paste("p", p, "_.*.csv", sep=""))

		# First we get the minimum dataset size (to be able to get the mean) and the last time of each one
		nrows <- c()
		last_times <- c()
		for(fn in lsub){
			path <- paste(folder, fn, sep="/")
			df <- read.csv(path, header = TRUE) # Data file

			nrw <- nrow(df)
			nrows <- c(nrows, nrw)
			last_times <- c(last_times, df$time[nrw])
		}

		min_nrows <- min(nrows)

		# Now we get the mean consumption for the first min_nrows (almost all of them)
		dfp <- NULL
		for(fn in lsub){
			path <- paste(folder, fn, sep="/")
			df <- read.csv(path, header = TRUE) # Data file
			df <- df[1:min_nrows,]

			if(is.null(dfp))
				dfp <- df
			else
				dfp$val <- dfp$val + df$val
		}

		# Makes final division to finish the mean
		dfp$val <- dfp$val / length(lsub)

		# Now we have to apply increments if applicable, and get the average of the aggregated dataset, per domain/node pair
		domains <- unique(dfp$domain)
		nodes <- unique(dfp$node)
		num_nodes <- length(nodes)

		for(d in domains){
			for(n in nodes){
				incr_df <- dfp

				# Applies increments, if provided
				if(base_filename != "")
					incr_df <- build_incr_df(dfp, basedf)

				subdf <- incr_df[incr_df$domain == d & incr_df$node == n,] # Filters by domain and node
				avg <- mean(subdf$val) # Obtains average

				cat(p, d, n, avg, "\n")
			}
		}

		# Prints mean time for the period (time overhead)
		time_avg <- mean(last_times)
		cat(p, time_avg, "\n")
	}
	return (1)
}

folder="~/files"
base_file <- ""
dump_to_files <- FALSE

args = commandArgs(trailingOnly=TRUE)
if (length(args) > 0){
	folder = args[1]
	dump_to_files <- TRUE # If you execute the script from a terminal, we will asume you would want the plots to be dumped
}
if (length(args) > 1)
	base_file <- args[2] # Increments file

do_everything(folder, base_file, dump_to_files)

