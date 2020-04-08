# Builds data for plot and updates table_df
build_ratiodata <- function(wd, o, dom, node, par_vals, base_filename = ""){
	mx <- par_vals[length(par_vals)]

	ts <- c()
	vals <- c()
	ratios <- c()

	# Builds subtable from scratch
	subtable <- as.data.frame(matrix(0, ncol = 6, nrow = 0))

	if(base_filename != "")
		basedf <- read.csv(base_filename, header = TRUE) # Energy base consumptions

	# Reads CSV files for different l and r values
	for(l in par_vals){
		r <- mx - l
		ratio <- l/(l+r)
		filename <- paste(wd, "/l", l, "_r", r, "_o", o, ".csv", sep="")
		df <- read.csv(filename, header = TRUE)
		subdf <- df[df$domain == dom & df$node == node,] # Filters by domain and node

		if(base_filename != "")
			subbase <- basedf[basedf$domain == dom & basedf$node == node,]

		for(j in 1:nrow(subdf)){ # Builds data from each row
			rw <- subdf[j,]
			ts <- c(ts, rw$time)

			if(base_filename != "")
				rw$val <- rw$val - subbase$mean # Increments

			vals <- c(vals, rw$val)
			ratios <- c(ratios, ratio)
		}

		# Gets averages for the other data frame
		avg <- mean(subdf$val)
		if(base_filename != "")
			avg <- avg - subbase$mean # Increments
		table_rw <- data.frame(l=l,r=r,o=o,dom=dom,node=node,avg_val=avg)
		subtable <- rbind(subtable, table_rw)
	}

	new_df <- data.frame(t = ts, val = vals, ratio = ratios)
	return (list(ratiodf = new_df, tablerows = subtable))
}

# By default, plots all the unique ratios
plot_ratiodata <- function(df, subtitle="", ratios_to_plot=unique(df$ratio), filename=""){
	plt_title <- paste("Instant energy consumption across time depending on local acceses proportion", subtitle)
	ratios <- ratios_to_plot # Readibility
	cl <- rainbow(length(ratios)) # A line per ratio

	xmax <- max(df$t)
	ymin <- min(df$val)
	ymax <- max(df$val)

	if(filename != "")
		png(filename, width = 1500, height = 1000, units = 'px', res = 150)

	plot(0, 0, xlim=c(0.0, xmax), ylim=c(ymin, ymax), type="n", main=plt_title, xlab="Time", ylab="W")
	for(i in 1:length(ratios)){
		r <- ratios[i]
		subdf <- df[df$ratio == r,]
		lines(subdf$t, subdf$val, col = cl[i], lwd = 1.5)
	}

	legend_labels <- sapply(ratios, function(r) paste("prop l/(l+r) =", r))
	legend("right", legend = ratios, col=cl, pch=1, cex = 1.0, pt.cex = 1.5)
	if(filename != "")
		dev.off()
}

# Core function that calls the two above
build_table_and_plot_radiodata <- function(folder, export_to_files = FALSE, base_filename = ""){
	l <- list.files(path = folder, pattern = "*.csv")
	if(length(l) == 0){
		print("No files in folder!\n")
		return ()
	}
	any_file <- paste(folder, "/", l[1], sep="")
	any_df <- read.csv(any_file, header = TRUE)

	domains <- unique(any_df$domain)
	nodes <- unique(any_df$node)
	num_nodes <- length(nodes)

	param_range <- sort(unique(sapply(l, function(fn) as.integer(substring(strsplit(fn, "_")[[1]][1],2)))))
	mx <- max(param_range)
	os <- c(param_range[1], median(param_range), max(param_range)) # Only some "o"s

	# Builds table from scratch
	table <- as.data.frame(matrix(0, ncol = 6, nrow = 0))

	# Builds a subdf and a plot for each domain/node combination, and some "o"s values
	for(d in domains){
		for(n in nodes){
			for(o in os){
				l <- build_ratiodata(folder, o, d, n, param_range, base_filename)
				ndf <- l[["ratiodf"]]
				table <- rbind(table, l[["tablerows"]])
				sbt <- paste("(", d,"-node",n,", o=", o, ")", sep="") # Subtitle for distinguishing plots

				fn <- paste("ratios_", d, "_node", n, "_o", o, ".png", sep="")
				if(export_to_files)
					plot_ratiodata(ndf, sbt, c(0.0, 0.5, 1.0), filename = fn) # Exported to file
				else
					#plot_ratiodata(ndf, sbt) # All ratios
					plot_ratiodata(ndf, sbt, c(0.0, 0.5, 1.0))
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
			lines(df_odn$ratio, df_odn$avg_val, col = cl[n_i], lwd = 1.5)
		}
		legend("left", legend = legend_labels, col=cl, pch=1, cex = 1.0, pt.cex = 1.5)
		if(dump_to_files)
			dev.off()
	}
}

plot_io <- function(df, r = 0, dump_to_files = FALSE){
	df_r <- df[df$r == r, ] # Only data for a specific "r" value
	
	domains <- unique(df_r$dom)
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
		df_rn <- df_r[df_r$dom == "pkg" & df_r$node == n,]
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
			df_rdn <- df_r[df_r$dom == d & df_r$node == n,]
			cl_i <- which(legend_labels == paste(d, ", node ", n, sep="")) # Gets actual color index
			lines(df_rdn$ratio, df_rdn$avg_val, col = cl[cl_i], lwd = 1.5)
		}
	}

	legend("left", legend = legend_labels, col=cl, pch=1, cex = 1.0, pt.cex = 1.5) # Adds legend
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

# Little tests
#ndf <- build_ratiodata("~/files", o=0, dom="pkg", node=0, par_vals = as.integer(c(0,1e6)))
#plot_ratiodata(ndf[["ratiodf"]], "(pkg-node0)")

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
