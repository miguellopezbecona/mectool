# Reads CSV generated by RAPL profiler. Nothing special
read_data <- function(filename){
	df <- read.csv(filename, header = TRUE)
	return (df)
}

# Different lines per node. Needs to focus on a specific RAPL domain
plot_cons_per_node <- function(df, domain = "pkg", dump_to_file = FALSE){
	df_d <- df[df$domain == domain, ] # Gets data from the specified domain
	
	nodes <- unique(df_d$node) # Gets nodes involved in data
	cl <- rainbow(length(nodes))
	legend_labels <- sapply(nodes, function(n) paste("Node ", n))

	if(dump_to_file)
		png(paste("cons_per_node_", domain, ".png", sep=""), width = 1500, height = 1000, units = 'px', res = 150)

	plt_title <- paste("Energy consumption per node (", domain, " domain)", sep="")
	plot(0, 0, xlim=c(0.0, max(df_d$time)), ylim=c(min(df_d$val), max(df_d$val)), type="n", main=plt_title, xlab="Time (s)", ylab="Power (W)")
	for(i in 1:length(nodes)){ # One line per node
		df_node <- df_d[df_d$node == nodes[i], ] # Gets data from node i
		lines(df_node$time, df_node$val, col = cl[i])
	}
	legend("left", legend = legend_labels, col=cl, pch=1, cex = 0.5) # Adds legend

	if(dump_to_file)
		dev.off()
}

plot_all_cons_per_node <- function(df, dump_to_file = FALSE){
	domains <- unique(df$domain) # Gets domains involved in data
	
	for(i in 1:length(domains))
		plot_cons_per_node(df, domains[i], dump_to_file)
}

# Different lines per RAPL domain. Needs to focus on a node, unless you want to use a sum or a mean
plot_cons_per_domain <- function(df, node = 0, dump_to_file = FALSE){
	df_n <- df[df$node == node, ] # Gets data from the specified node

	domains <- unique(df_n$domain) # Gets domains involved in data
	cl <- rainbow(length(domains))
	legend_labels <- sapply(domains, function(d) paste("energy-", d)) # Not necessary but meh

	if(dump_to_file)
		png(paste("cons_per_domain_n", node, ".png", sep=""), width = 1500, height = 1000, units = 'px', res = 150)	

	plt_title <- paste("Energy consumption per domain (node ", node, ")", sep="")
	plot(0, 0, xlim=c(0.0, max(df_n$time)), ylim=c(min(df_n$val), max(df_n$val)), type="n", main=plt_title, xlab="Time (s)", ylab="Power (W)")
	
	for(i in 1:length(domains)){ # One line per domain
		df_node <- df_n[df_n$domain == domains[i], ] # Gets data for domain i
		lines(df_node$time, df_node$val, col = cl[i])
	}
	legend("left", legend = legend_labels, col=cl, pch=1, cex = 0.6) # Adds legend

	if(dump_to_file)
		dev.off()
}

plot_all_cons_per_domain <- function(df, dump_to_file = FALSE){
	nodes <- unique(df$node) # Gets nodes involved in data
	
	for(i in 1:length(nodes))
		plot_cons_per_domain(df, nodes[i], dump_to_file)
}

# Very optional function to process output from my_test.c with PRINT_PHASE_CHANGE macro uncommented
read_and_process_iosfile <- function(filename, dump_to_file = FALSE) {
	ios <- read.csv(filename, header = TRUE, stringsAsFactors = FALSE)
	ios$s[ios$s == "l" ] <- 0
	ios$s[ios$s == "h" ] <- 1
	ios$s <- as.integer(ios$s)
	x <- c(0)
	y <- c(0)

	for(i in 1:nrow(ios)){
		s <- ios[i,]$s
		t <- ios[i,]$t
		
		x <- c(x, t) 
		y <- c(y, s)
		
		# A second point for doing a vertical line (same x value, inverted y one)
		x <- c(x, t)
		y <- c(y, as.integer(!s))
	}
	
	if(dump_to_file)
		png("ios.png", width = 1500, height = 1000, units = 'px', res = 150)

	#plot(x,y, type="l", col="red", xlab="Time (s)", ylab="Low/high IO")
	
	# This version of the plot changes x axis ticks to be more readable
	plot(x,y, type="l", col="red", xlab="Time (s)", ylab="Low/high IO", xaxt = "n")
	m <- max(ios$t)
	sq <- seq(0,m,0.5)
	axis(1, at=sq, labels=sq)

	if(dump_to_file)
		dev.off()
}

build_incr_df <- function(df, base_filename="base.csv"){
	basedf <- read.csv(base_filename, header = TRUE) # Energy base consumptions
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

file <- "data.csv"
base_file <- ""
dump_to_files <- FALSE

args = commandArgs(trailingOnly=TRUE)
if (length(args) > 0){
	file <- args[1] # Main data file
	dump_to_files <- TRUE # If you execute the script from a terminal, we will asume you would want the plots to be dumped
}
if (length(args) > 1)
	base_file <- args[2] # Increments file

df <- read_data(file)
incr_df <- df

if(base_file != "")
	incr_df <- build_incr_df(df, base_file)

#plot_cons_per_node(incr_df, "pkg", dump_to_files)
#plot_cons_per_domain(incr_df, 0, dump_to_files)
#read_and_process_iosfile("ios.csv", dump_to_files)

plot_all_cons_per_node(incr_df, dump_to_files)
plot_all_cons_per_domain(incr_df, dump_to_files)

