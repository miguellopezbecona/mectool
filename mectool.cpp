#include <stdio.h>
#include <unistd.h>
#include <signal.h>
#include <sys/time.h>
#include <ctype.h> // isprint

#include <numeric> // accumulate

#include "energy_data.h"

// No incremental data gathering
//#define ONE_MEASURE

//#define PRINT_OUTPUT
#define DUMP_TO_FILE

// Copy paste from utils
double get_median_from_list(vector<double> l){
	size_t size = l.size();

	sort(l.begin(), l.end()); // Getting median requires sorting

	if (size % 2 == 0)
		return (l[size / 2 - 1] + l[size / 2]) / 2;
	else 
		return l[size / 2];
}

/////

#ifdef ONE_MEASURE
struct timeval t_beg, t_end;
#else
unsigned int sleep_time = 1000 * 1000; // One second (in microseconds) by default
double seconds_sleep;
#endif

energy_data_t ed;

typedef vector<double> hist_cons; // List of consumptions
typedef vector<hist_cons> cons_per_dom; // List of consumptions per domain (list of lists)
vector<cons_per_dom> cons_per_node; // List of consumptions per node (list of lists of lists)

void dump_data(vector<cons_per_dom> data){
	size_t v_size = data[0][0].size(); // All most-inner lists should have the same length
	if(v_size == 0) // Sanity checking
		return;

	const char* data_filename = "data.csv";
	FILE* fp = fopen(data_filename, "w");
	if(fp == NULL){
		printf("Error opening file %s to log data.\n", data_filename);
		return;
	}

	fprintf(fp, "time,node,domain,val\n"); // Header
	for(size_t it=0;it<v_size;it++){
		for(int n=0;n<system_struct_t::NUM_OF_MEMORIES;n++){
			for(int d=0;d<energy_data_t::NUM_RAPL_DOMAINS;d++)
				fprintf(fp, "%.2f,%d,%s,%.3f\n", it*seconds_sleep, n, energy_data_t::rapl_domain_names[d], data[n][d][it]);
		}
	}
	fclose(fp);


	#ifndef ONE_MEASURE
	// Print additional statistics in other file
	const char* metadata_filename = "metadata.csv";
	fp = fopen(metadata_filename, "w");
	if(fp == NULL){
		printf("Error opening file %s to log data.\n", metadata_filename);
		return;
	}

	fprintf(fp, "node,domain,v_size,min,mean,max,median\n"); // Header
	for(int n=0;n<system_struct_t::NUM_OF_MEMORIES;n++){
		for(int d=0;d<energy_data_t::NUM_RAPL_DOMAINS;d++){
			vector<double> v = data[n][d];

			if(v.empty()) // Sanity checking
				continue;

			double min = *(min_element(v.begin(), v.end()));
			double mean = accumulate(v.begin(), v.end(), 0.0) / v_size;
			double max = *(max_element(v.begin(), v.end()));
			double median = get_median_from_list(v);

			fprintf(fp, "%d,%s,%lu,%.3f,%.3f,%.3f,%.3f\n",n,energy_data_t::rapl_domain_names[d],v_size,min,mean,max,median);
		}
	}
	fclose(fp);
	#endif
}

static void clean_end(int n) {
	#ifdef ONE_MEASURE
	ed.read_buffer();
	gettimeofday(&t_end, NULL);
	double elapsed_time = (t_end.tv_sec - t_beg.tv_sec + (t_end.tv_usec - t_beg.tv_usec)/1.e6);
	printf("Elapsed time: %.2f seconds\n", elapsed_time);

	ed.print_curr_vals_with_time(elapsed_time);

	#ifdef DUMP_TO_FILE
	// We store each historical consumption in our internal structure
	double** data = ed.get_curr_vals();
	for(int n=0;n<system_struct_t::NUM_OF_MEMORIES;n++){
		for(int d=0;d<energy_data_t::NUM_RAPL_DOMAINS;d++)
			cons_per_node[n][d].push_back(data[n][d] / elapsed_time); // We will store the mean consumption
	}
	#endif
	#endif

	ed.close_buffers();

	#ifdef DUMP_TO_FILE
	dump_data(cons_per_node);

	// We clear our messy nested structure
	for(int n=0;n<system_struct_t::NUM_OF_MEMORIES;n++){
		for(int d=0;d<energy_data_t::NUM_RAPL_DOMAINS;d++)
			cons_per_node[n][d].clear();
		cons_per_node[n].clear();
	}
	cons_per_node.clear();
	#endif

	exit(0);
}

void read_parameters(int argc, char** argv){
	char c;

	// Parses argv with getopt
	while ((c = getopt (argc, argv, "p:d:")) != -1){
		switch (c) {
			#ifndef ONE_MEASURE
			case 'p': // Period (in milliseconds)
				sleep_time = atoi(optarg)*1000; // Microseconds
				break;
			#endif
			case 'd': { // Domains to be read, separated by "_"
				char* domain = strtok(optarg, "_");
				while(domain != NULL){
					energy_data_t::rapl_domain_names.push_back(strdup(domain));
					domain = strtok(NULL, "_");
				}

				#ifdef PRINT_OUTPUT
				printf("Domains chosen to be read:");
				for(char* const & d : energy_data_t::rapl_domain_names)
					printf(" %s", d);
				printf("\n");
				#endif
				break;
			}
			case '?': // Default
				if (isprint(optopt))
					fprintf (stderr, "Unknown option `-%c'.\n", optopt);
				else
					fprintf (stderr, "Unknown option character `\\x%x'.\n", optopt);
				exit(1);
		}
	}
}

int main(int argc, char **argv) {
	// Sets up handler for some signals for a clean end
	signal(SIGINT, clean_end);
	system_struct_t::detect_system();

	read_parameters(argc, argv);

	int ret = ed.prepare_energy_data();
	if(ret != 0)
		exit(ret);

	// We prepare our messy nested structure with resizes and reserves
	cons_per_node.resize(system_struct_t::NUM_OF_MEMORIES); // Fixed size: number of nodes
	for(int n=0;n<system_struct_t::NUM_OF_MEMORIES;n++){
		cons_per_node[n].resize(energy_data_t::NUM_RAPL_DOMAINS);
		for(int d=0;d<energy_data_t::NUM_RAPL_DOMAINS;d++) // Fixsed size: number of domains
			cons_per_node[n][d].reserve(100); // We could reserve much more depending on the situation
	}

	#ifndef ONE_MEASURE
	seconds_sleep = sleep_time / (1000*1000.0);
	double inv_seconds_sleep = 1 / seconds_sleep; // For using "*" instead of "/" and therefore being more efficient
	while(1){
		usleep(sleep_time);
		ed.read_buffer();
		
		#ifdef DUMP_TO_FILE
		// We store each historical consumption in our internal structure
		double** data = ed.get_curr_vals();
		for(int n=0;n<system_struct_t::NUM_OF_MEMORIES;n++){
			for(int d=0;d<energy_data_t::NUM_RAPL_DOMAINS;d++)
				cons_per_node[n][d].push_back(data[n][d] * inv_seconds_sleep);
		}
		#endif

		#ifdef PRINT_OUTPUT
		ed.print_curr_vals_with_time(seconds_sleep);
		#endif
	}
	#else
	gettimeofday(&t_beg, NULL);
	pause();
	#endif

	return 0;
}
