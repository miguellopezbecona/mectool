## An altenative version that attempts to be more efficient by reading each CSV file just once. Though, this is actually SLOWER! :S
## Issues: radiodata should include data for all ratios. RIght now a different df is generated for eah one

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

# By default, plots all the unique ratios
plot_ratiodata <- function(df, meta=c("?,?,?"), ratios_to_plot=unique(df$ratio), dump_to_files = FALSE){
	sbt <- paste("(", meta[1], ", node", meta[2], ", o: ", meta[3], ")", sep="") # Subtitle for distinguishing plots
	plt_title <- paste("Instant energy consumption across time depending on local acceses proportion", sbt)

	ratios <- ratios_to_plot # Readibility
	cl <- rainbow(length(ratios)) # A line per ratio

	xmax <- max(df$t)
	ymin <- min(df$val)
	ymax <- max(df$val)

	if(dump_to_files){
		fn <- paste("ratios_", meta[1], "_node", meta[2], "_o", meta[3], ".png", sep="")
		png(fn, width = 1500, height = 1000, units = 'px', res = 150)
	}

	plot(0, 0, xlim=c(0.0, xmax), ylim=c(ymin, ymax), type="n", main=plt_title, xlab="Time", ylab="W")
	for(i in 1:length(ratios)){
		r <- ratios[i]
		subdf <- df[df$ratio == r,]
		lines(subdf$t, subdf$val, col = cl[i])
	}

	legend_labels <- sapply(ratios, function(r) paste("prop l/(l+r) =", r))
	legend("bottomright", legend = ratios, col=cl, pch=1, cex = 0.6)
	if(dump_to_files)
		dev.off()
}

# Core function that calls the two above
build_table_and_plot_radiodata <- function(folder, dump_to_files = FALSE, base_filename = ""){
	l <- list.files(path = folder, pattern = "l*.csv")
	if(length(l) == 0){
		print("No files in folder!\n")
		return ()
	}
	param_range <- sort(unique(sapply(l, function(fn) as.integer(substring(strsplit(fn, "_")[[1]][1],2)))))
	mx <- max(param_range)

	any_file <- paste(folder, l[1], sep="/")
	any_df <- read.csv(any_file, header = TRUE)

	domains <- unique(any_df$domain)
	nodes <- unique(any_df$node)
	num_nodes <- length(nodes)

	#os <- param_range
	os <- c(param_range[1], median(param_range), max(param_range)) # Only some "o"s

	# Builds table from scratch
	table <- as.data.frame(matrix(0, ncol = 6, nrow = 0))

	if(base_filename != "")
		basedf <- read.csv(base_filename, header = TRUE) # Energy base consumptions

	# Reads all CSV files, varying l, r and o
	for(l in param_range){
		r <- mx - l
		ratio <- l/(l+r)

		for(o in os){
			filename <- paste(folder, "/l", l, "_r", r, "_o", o, ".csv", sep="")
			df <- read.csv(filename, header = TRUE)
			incr_df <- df

			# Applies increments, if provided
			if(base_filename != "")
				incr_df <- build_incr_df(df, basedf)

			# Builds a subdf and a plot for each domain/node combination
			for(d in domains){
				for(n in nodes){
					ts <- c()
					vals <- c()
					ratios <- c()

					# Filters by domain and node
					subdf <- incr_df[incr_df$domain == d & incr_df$node == n,]

					# Builds ratio data with each row
					for(j in 1:nrow(subdf)){
						rw <- subdf[j,]
						ts <- c(ts, rw$time)
						vals <- c(vals, rw$val)
						ratios <- c(ratios, ratio)
					}
					rdf <- data.frame(t = ts, val = vals, ratio = ratios)

					# Plots ratiodata
					meta <- c(d, n, o)
					#plot_ratiodata(ndf, meta, unique(rdf$ratio), dump_to_files) # All ratios
					plot_ratiodata(rdf, meta, c(0.0, 0.5, 1.0), dump_to_files)

					# Gets average for main table
					avg <- mean(subdf$val)
					table_rw <- data.frame(l=l,r=r,o=o,domain=d,node=n,avg_val=avg)
					table <- rbind(table, table_rw)
				}
			}
		}
	}

	return (table)
}

### Plot functions once we have table data
plot_local_vs_remote <- function(df, o = 0, dump_to_files = FALSE){
	df_o <- df[df$o == o, ] # Only data for a specific "o" value
	
	df_o$ratio <- df_o$l / (df_o$r + df_o$l)

	domains <- unique(df_o$dom)
	nodes <- unique(df_o$node)
	num_nodes <- length(nodes)
	cl <- rainbow(num_nodes)
	legend_labels <- sapply(nodes, function(n) paste("Node", n) )

	# One plot per domain
	for(d in domains){
		df_od <- df_o[df_o$dom == d, ]
		plt_title <- paste("Energy consumption depending on local acceses proportion (", d, ", o=", o, ")", sep="")

		ymin <- min(df_od$avg_val)
		ymax <- max(df_od$avg_val)

		if(dump_to_files){
			fn <- paste("l_vs_r_o_", o, "_", d, ".png", sep="")
			png(fn, width = 1500, height = 1000, units = 'px', res = 150)
		}
		plot(0, 0, xlim=c(0.0, 1.0), ylim=c(ymin, ymax), type="n", main=plt_title, xlab="Local/Total (Local+Remote)", ylab="Avg W")

		# One line per node
		for(n_i in 1:length(nodes)){
			n <- nodes[n_i]
			df_odn <- df_od[df_od$node == n, ]
			lines(df_odn$ratio, df_odn$avg_val, col = cl[n_i])
		}
		legend("left", legend = legend_labels, col=cl, pch=1, cex = 0.6)
		if(dump_to_files)
			dev.off()
	}
}

plot_io <- function(df, r = 0, dump_to_files = FALSE){
	df_r <- df[df$r == r, ] # Only data for a specific "r" value
	
	domains <- unique(df_r$domain)
	nodes <- unique(df_r$node)
	num_nodes <- length(nodes)

	cl <- rainbow( length(nodes) * length(domains) ) # One line per domain/node combination

	# Cartesian product
	legend_labels <- apply(expand.grid(domains, nodes), 1, function(x) paste(x[1], ", node ", x[2], sep=""))

	df_r$ratio <- df_r$o / df_r$l
	df_r <- df_r[is.finite(df_r$ratio),] # Discards Infs

	if(nrow(df_r)==0)
		return ()

	plt_title <- paste("Operational intensity vs energy consumption (r = ", r, ")", sep="")
	xmax <- min( max(df_r$ratio), 100)

	# Gets highest "y" value
	ymax <- 0.0
	for(n in nodes){
		df_rn <- df_r[df_r$domain == "pkg" & df_r$node == n,]
		ymax <- max(ymax, df_rn$avg_val)
	}

	if(dump_to_files){
		fn <- paste("io_r", r, ".png", sep="")
		png(fn, width = 1500, height = 1000, units = 'px', res = 150)
	}
	plot(0, 0, xlim=c(0.0, xmax), ylim=c(0.0, ymax), type="n", main=plt_title, xlab="Operational Intensity (o/l)", ylab="Avg W")

	# Plots each line
	for(d in domains){
		for(n in nodes){
			df_rdn <- df_r[df_r$domain == d & df_r$node == n,]
			cl_i <- which(legend_labels == paste(d, ", node ", n, sep="")) # Gets actual color index
			lines(df_rdn$ratio, df_rdn$avg_val, col = cl[cl_i])
		}
	}

	legend("left", legend = legend_labels, col=cl, pch=1, cex = 0.6) # Adds legend
	if(dump_to_files)
		dev.off()
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

tbl <- build_table_and_plot_radiodata(folder, dump_to_files, base_file)
if(is.null(tbl))
	quit(status=1)

# Plots cons depending on local vs remote accesses for determined "o" values
os <- unique(tbl$o)
for(o in os)
	plot_local_vs_remote(tbl, o, dump_to_files)

# Plots cons depending on OI for determined "r" values
rs <- unique(tbl$r)
for(r in rs)
	plot_io(tbl, r, dump_to_files)

