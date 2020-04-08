### ex3: effect of number of threads ###

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

# Core function that calls the two above
build_th_table <- function(folder, base_filename = ""){
	l <- list.files(path = folder, pattern = "t*.csv")
	if(length(l) == 0){
		cat("No files in folder!\n")
		return ()
	}

	ths <- sort(sapply(l, function(str) as.integer(substring(str, 2, nchar(str)-4)))) # Sorted integer values
	l <- names(ths) # Filenames sorted by number
	paths <- sapply(l, function(fn) paste(folder, fn, sep="/"))

	# For getting unique domains and nodes beforehand
	any_file <- paths[1]
	any_df <- read.csv(any_file, header = TRUE)
	domains <- unique(any_df$domain)
	nodes <- unique(any_df$node)
	num_nodes <- length(nodes)

	# Builds table from scratch
	table <- as.data.frame(matrix(0, ncol = 4, nrow = 0))

	# Reads base_filename, if provided
	if(base_filename != "")
		basedf <- read.csv(base_filename, header = TRUE) # Energy base consumptions

	# Builds a subdf and a plot for each domain/node combination, and some "o"s values
	for(i in 1:length(ths)){
		th <- ths[i]
		p <- paths[i]
		df <- read.csv(p, header = TRUE) # Data file for a determined number of threads
		incr_df <- df

		# Applies increments, if provided
		if(base_filename != "")
			incr_df <- build_incr_df(df, basedf)

		# Calculates averages for each pair or domain/nodes
		for(d in domains){
			for(n in nodes){
				subdf <- incr_df[incr_df$domain == d & incr_df$node == n,] # Filters by domain and node
				avg <- mean(subdf$val) # Obtains average

				# Adds data to table
				rw <- data.frame(th=th,domain=d,node=n,avg_val=avg)
				table <- rbind(table, rw)
			}
		}
	}

	return (table)
}

plot_th_cons <- function(df, dump_to_files = FALSE){
	domains <- unique(df$domain)
	nodes <- unique(df$node)
	num_nodes <- length(nodes)
	cl <- rainbow(num_nodes)
	legend_labels <- sapply(nodes, function(n) paste("Node", n) )

	ths <- unique(df$th)
	xmin <- min(ths)
	xmax <- max(ths)

	# One plot per domain
	for(d in domains){
		df_d <- df[df$dom == d, ]
		plt_title <- paste("Average power consumption depending on number of threads (", d, ")", sep="")

		ymin <- min(df_d$avg_val)
		ymax <- max(df_d$avg_val)

		if(dump_to_files){
			# We include the domain within the filename
			fn <- paste("th_", d, ".png", sep="")
			png(fn, width = 1500, height = 1000, units = 'px', res = 150)
		}
		plot(0, 0, xlim=c(xmin, xmax), ylim=c(ymin, ymax), type="n", main=plt_title, xlab="Number of threads", ylab="Avg W")

		# One line per node
		for(n_i in 1:length(nodes)){
			n <- nodes[n_i]
			df_dn <- df_d[df_d$node == n, ]
			lines(df_dn$th, df_dn$avg_val, col = cl[n_i])
		}

		legend("topleft", legend = legend_labels, col=cl, pch=1, cex = 0.6)
		if(dump_to_files != "")
			dev.off()
	}
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

# Builds main data
table <- build_th_table(folder, base_file)
if(is.null(table))
	quit(status=1)

# Plots table
plot_th_cons(table, dump_to_files)

