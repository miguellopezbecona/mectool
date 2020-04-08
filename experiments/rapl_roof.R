### rapl_roof.R: possible correlation with Roofline Model. Execute if after running experiment_roof.sh ###

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

plot_ener_roofline_partial <- function(xs, ys, xli, yli, node, fixed_val, param_values = NULL, dump_to_files = FALSE, subtract_ram = FALSE){
	if(subtract_ram){
		ys <- ys - xs # pkg - ram
		yla <- "Avg W increase (pkg-ram)"
		extratitle <- "_st_"
	} else{
		yla <- "Avg W increase (pkg)"
		extratitle <- "_nost_"
	}

	otherp <- NULL
	if(fixed_val$n == "L")
		otherp <- "O"
	else
		otherp <- "L"
		
	plt_title <- paste("RAM consumption vs PKG consumption for different values of ", otherp, " (", fixed_val$n, " fixed with ", fixed_val$v, ", node ", node, ")", sep="")
	if(dump_to_files){
		# We include the node within the filename
		fn <- paste("energy_roofline_node", node, extratitle, fixed_val$n, fixed_val$v ,".png", sep="")
		png(fn, width = 1500, height = 1000, units = 'px', res = 150)
	}
	
	cls <- rainbow(length(param_values))
	pchs <- 1:length(param_values)
	
	legend_labels <- sapply(param_values, function(v) paste(otherp, "=", format(as.double(v),scientific=TRUE)) )

	fx_idx <- which(param_values == fixed_val$v)
	cl_line <- cls[fx_idx] # To print the line in the same colour as the full energy roofline version in O format
	pch_line <- pchs[fx_idx] # To print the line with the same pch as the full energy roofline version in L format
	
	# Main call
	if(otherp == "O"){ # O format
		plot(xs, ys, xlim=rev(xli), ylim=yli, type="p", main=plt_title, xlab="Avg W increase (ram)", ylab=yla, col = cl_line, cex= 3.5, lwd=3, pch = pchs)
		lines(xs, ys, col = cl_line, lwd=3)
		legend("topright", legend = legend_labels, col=cl_line, pch=pchs, cex = 0.6)
	}
	else if(otherp == "L"){ # L format
		plot(xs, ys, xlim=rev(xli), ylim=yli, type="p", main=plt_title, xlab="Avg W increase (ram)", ylab=yla, col = cls, cex= 3.5, lwd=3, pch = pch_line)
		lines(xs, ys, col = cl_line, lwd=3)
		legend("topright", legend = legend_labels, pch = pch_line, col=cls, cex = 0.6)
	}

	if(dump_to_files)
		dev.off()
}

# All dots in the same plot
plot_ener_roofline_full <- function(data, node, param_values = NULL, dump_to_files = FALSE){
	xs <- data$x
	ys <- data$y

	plt_title <- paste("RAM consumption vs PKG consumption for different values of L and O (node ", node, ")", sep="")
	if(dump_to_files){
		# We include the node within the filename
		fn <- paste("energy_roofline_node", node, ".png", sep="")
		png(fn, width = 1500, height = 1000, units = 'px', res = 150)
	}

	cl <- "black"
	pchs <- 1

	# Color depending on L value. pchs depending on O value
	if(!is.null(param_values)){
		cl_set <- rainbow(length(param_values))
		cls <- rep(cl_set, each=length(param_values))
		legend_l_labels <- sapply(param_values, function(v) paste("L =", format(as.double(v),scientific=TRUE)) )

		pchs <- 1:length(param_values)
		legend_o_labels <- sapply(param_values, function(v) paste("O =", format(as.double(v),scientific=TRUE)) )
	}

	# Main call
	xl <- rev(c(min(xs), max(xs)))
	plot(xs, ys, xlim = xl, type="p", main=plt_title, xlab="Avg W increase (ram)", ylab="Avg W increase (pkg)", col = cls, pch = pchs, lwd = 2)
	if(!is.null(param_values)){
		legend("topright", legend = legend_l_labels, col=cl_set, pch=1, cex = 0.6)
		legend("bottomleft", legend = legend_o_labels, col="black", pch=pchs, cex = 0.6)
	}

	if(dump_to_files)
		dev.off()
}

# Plots pure roofline
plot_roofline <- function(data, param_values = NULL, dump_to_files = FALSE){
	xs <- data$x
	ys <- data$y

	plt_title <- "Roofline Model for the executed tests"
	if(dump_to_files)
		png("roofline_model.png", width = 1500, height = 1000, units = 'px', res = 150)

	cls <- "black"
	pchs <- 1

	# Color depending on L value. pchs depending on O value
	if(!is.null(param_values)){
		cl_set <- rainbow(length(param_values))
		cls <- rep(cl_set, each=length(param_values))
		legend_l_labels <- sapply(param_values, function(v) paste("L =", v) )

		pchs <- 1:length(param_values)
		legend_o_labels <- sapply(param_values, function(v) paste("O =", v) )
	}

	# Plots points
	plot(xs, ys, type="p", main=plt_title, xlab="Operational Intensity (FLOPit./bytes read per it.)", ylab="MFLOPit.", col = cls, pch = pchs)
	
	# Plots lines
	cll <- length(cl_set)
	for(i in 1:cll){
		cl <- cl_set[i]
		rng <- ((i-1)*cll+1):(i*cll) # Ranges of length cll from 0, steps of cll
		lines(xs[rng], ys[rng], col = cl)
	}
	
	if(!is.null(param_values)){
		legend("topleft", legend = legend_l_labels, col=cl_set, pch=1, cex = 0.6)
		legend("bottomright", legend = legend_o_labels, col="black", pch=pchs, cex = 0.6)
	}

	if(dump_to_files)
		dev.off()
}

# Core function that does all the workflow
do_everything <- function(folder, base_filename = "", dump_to_files = FALSE){
	l <- list.files(path = folder, pattern = "l.*.csv")
	if(length(l) == 0){
		print("No files in folder!")
		return ()
	}

	param_range <- sort(unique(sapply(l, function(fn) as.integer(substring(strsplit(fn, "_")[[1]][1],2)))))

	# Readibility
	ls <- param_range
	os <- param_range

	# For getting unique domains and nodes beforehand
	any_file <- paste(folder, l[1], sep="/")
	any_df <- read.csv(any_file, header = TRUE)
	domains <- unique(any_df$domain)
	nodes <- unique(any_df$node)
	num_nodes <- length(nodes)

	# Data
	d <- list()
	for(n in nodes)
		d[[n+1]] <- list()

	# Reads base_filename, if provided
	if(base_filename != "")
		basedf <- read.csv(base_filename, header = TRUE) # Energy base consumptions

	# Mean local and ops (flops) per application. 
	lps <- c()
	ops <- c()

	# Builds data looping over files
	for(l in ls){
		for(o in os){
			fn <- paste(folder, "/l", l, "_o", o, ".csv", sep="")
			df <- read.csv(fn, header = TRUE) # Data file
			incr_df <- df

			# Applies increments, if provided
			if(base_filename != "")
				incr_df <- build_incr_df(df, basedf)

			# We get time execution
			nrw <- nrow(incr_df)
			exec_time <- incr_df$time[nrw]

			# Each file provides a point for the graphic
			for(n in nodes){
				idx <- n+1

				# Filters by node
				subdf <- incr_df[incr_df$node == n,]

				# Filters by domain, statically
				subdf_p <- subdf[subdf$domain == "cores",]
				subdf_r <- subdf[subdf$domain == "ram",]

				# Obtains averages
				avg_p <- mean(subdf_p$val)
				avg_r <- mean(subdf_r$val)

				if(n == 0){
					i_val <- 850 # Constant for this case
					lt <- l*i_val
					ot <- o*i_val

					lps <- c(lps, lt/exec_time)
					ops <- c(ops, ot/exec_time)
				}

				d[[idx]]$x <- c(d[[idx]]$x, avg_r)
				d[[idx]]$y <- c(d[[idx]]$y, avg_p)
			}
		}
	}
	
	### Plots

	## One plot per node
	for(n in nodes)
		plot_ener_roofline_full(d[[n+1]], n, param_range, dump_to_files)
	
	## One plot per L and O ratios. We will focus on node 0
	xs <- d[[1]]$x
	ys <- d[[1]]$y
	xl <- c(min(xs), max(xs))
	yl <- c(min(ys), max(ys))
	pl <- length(ls)
	fx <- list()
	
	# Ls
	fx$n <- "L"
	for(i in 1:pl){
		l <- ls[i]
		rng <- ((i-1)*pl+1):(i*pl) # Ranges of length pl from (i-1)*pl to i*pl, steps of 1
		fx$v <- l

		# With and without pkg-ram subtract
		#plot_ener_roofline_partial(xs[rng], ys[rng], xl, yl, node=0, fx, param_range, dump_to_files, TRUE)
		plot_ener_roofline_partial(xs[rng], ys[rng], xl, yl, node=0, fx, param_range, dump_to_files, FALSE)
	}
	
	# Os
	fx$n <- "O"
	for(i in 1:pl){
		o <- os[i]
		rng <- seq(i,length(xs),by=pl) # Ranges of length pl from i to length(points), steps of pl
		fx$v <- o
		
		# With and without pkg-ram subtract
		#plot_ener_roofline_partial(xs[rng], ys[rng], xl, yl, node=0, fx, param_range, dump_to_files, TRUE)
		plot_ener_roofline_partial(xs[rng], ys[rng], xl, yl, node=0, fx, param_range, dump_to_files, FALSE)
	}

	## Pure Roofline
	r <- list()
	for(l in ls){
		for(o in os){
			r$x <- c(r$x, o/(4*l)) # Operational Intensity
			r$y <- c(r$y, o/(2 ** 20)) # Floating point operations per iteration
		}
	}
	plot_roofline(r, param_range, dump_to_files)

	## Local ops per second vs ram, flops vs pkg-ram
	cl_set <- rainbow(length(param_range))
	#cls <- rep(cl_set, each=length(param_range)) # Fixing L
	cls <- cl_set # Fixing O
	legend_labels <- sapply(param_range, function(v) paste("O =", v) )
	
	if(dump_to_files)
		png("lps_ram.png", width = 1500, height = 1000, units = 'px', res = 150)
	plot(lps, d[[1]]$x, type="p", main="Local mem-ops per second vs ram", xlab="Local mem-ops per second", ylab="Avg RAM", col = cls, cex = 3.5, lwd = 3)
	legend("topleft", legend = legend_labels, col=cl_set, pch=1, cex = 0.6)
	if(dump_to_files)
		dev.off()

	if(dump_to_files)
		png("flops_pkg.png", width = 1500, height = 1000, units = 'px', res = 150)
	plot(ops, d[[1]]$y - d[[1]]$x, type="p", main="FLOPS vs (pkg-ram)", xlab="FLOPS", ylab="(Avg PKG)-(Avg RAM)", col = cls, cex = 2.5, lwd = 3)
	#plot(ops, d[[1]]$y, type="p", main="FLOPS vs pkg", xlab="FLOPS", ylab="Avg PKG", col = cls, cex = 2.5, lwd=3)
	legend("topleft", legend = legend_labels, col=cl_set, pch=1, cex = 0.6)
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

do_everything(folder, base_file, dump_to_files)

