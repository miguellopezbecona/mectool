#define _GNU_SOURCE 1
#include <stdio.h>
#include <unistd.h> // optarg, getting number of CPUs...
#include <sys/syscall.h> // gettid
#include <ctype.h> // isprint
#include <sys/time.h>

#include <emmintrin.h> // clflush
#include <sched.h> // CPU affinity stuff
#include <omp.h> // OpenMP

#include "system_struct.h"

typedef float data_type; // For changing data type easily
typedef unsigned long int bigint; // For readibility and changing it easier

// Default macro values
#define DEFAULT_MAIN_ITERS 1000
#define DEFAULT_ELEMS_ITER 1
#define DEFAULT_REMOTE_READS 0
#define DEFAULT_NUMBER_OPS 1
#define DEFAULT_NUM_THREADS 1
#define DEFAULT_LOCAL_NODE 0
#define DEFAULT_REMOTE_NODE 1

#define CACHE_LINE_SIZE 64
#define ELEMS_PER_CACHE (int) (CACHE_LINE_SIZE / sizeof(data_type))

//#define DO_CLFLUSH
//#define OUTPUT
//#define DOGETPID

// For a specific test. Can be commented
#define PRINT_PHASE_CHANGE

#ifdef PRINT_PHASE_CHANGE
struct timeval t_beg, t_end;
#endif

// Main data
bigint array_basic_size; // array_total_size / num_th
bigint array_total_size;
data_type* local_array_a;
data_type* local_array_b;
data_type* remote_array_a;
data_type* remote_array_b;

// Options
bigint main_iters;
bigint elems_iter;
bigint remote_reads;
bigint ops;
unsigned int num_th;
unsigned char *selected_cpus;
unsigned char local_node;
unsigned char remote_node;

// Predeclarations
void print_selected_cpus();
void print_params();
void usage(char **argv);

/*** Auxiliar functions ***/
void print_selected_cpus(){
	printf("Selected CPUs:");

	int i;
	for(i=0;i<num_th;i++)
		printf(" %d", selected_cpus[i]);

	printf("\n");
}

void print_params(){
	//printf("Main iterations: %lu\nElements read/written per iteration: %lu\nRemote elements read/written per iteration: %d\nNumber of floating operations per iteration: %d\nNumber of threads: %d\nArray size: %lu\nLocal node: %d\nRemote node: %d\n\n",main_iters,elems_iter,remote_reads,ops,num_th,array_total_size, local_node, remote_node);
	printf("I: %lu\nL: %lu\nR: %lu\nO: %lu\nThs: %d\nArray size: %lu\nLocal node: %d\nRemote node: %d\n\n",main_iters,elems_iter,remote_reads,ops,num_th,array_total_size, local_node, remote_node);
}

void usage(char **argv) {
	printf("Usage: %s [-imain_iterations] [-lelements_processed_per_iteration] [-rremote_elements_processed_per_iteration] [-ooperations_per_iteration] [-tnumber_of_threads] [-mlocal_node] [-Mremote_node]\n\n", argv[0]);
}

#ifdef DO_CLFLUSH
void cache_flush(const void *p, unsigned int allocation_size){
	const char *cp = (const char *)p;
	size_t i = 0;

	if (p == NULL || allocation_size <= 0)
		return;

	for (i = 0; i < allocation_size; i += CACHE_LINE_SIZE)
		_mm_clflush(&cp[i]);
}
#endif

/*** Main functions ***/

// Allocates memory and does other stuff
void data_initialization(){
	int th, offset;

	local_array_a = (data_type*)numa_alloc_onnode(array_total_size*sizeof(data_type), local_node);
	local_array_b = (data_type*)numa_alloc_onnode(array_total_size*sizeof(data_type), local_node);
	if(local_array_a == NULL || local_array_b == NULL){
		printf("Local malloc failed, probably due to not enough memory.\n");
		exit(-1);
	}

	remote_array_a = (data_type*)numa_alloc_onnode(array_total_size*sizeof(data_type), remote_node);
	remote_array_b = (data_type*)numa_alloc_onnode(array_total_size*sizeof(data_type), remote_node);
	if(remote_array_a == NULL || remote_array_b == NULL){
		printf("Remote malloc failed, probably due to not enough memory.\n");
		numa_free(local_array_a, array_total_size*sizeof(data_type));
		numa_free(local_array_b, array_total_size*sizeof(data_type));
		exit(-1);
	}

	// Random initialization
	for(th=0;th<num_th;th++){
		offset = th*array_basic_size;

		#ifdef OUTPUT
		// Gets the memory range where each thread will work in
		printf("local_array_a[%d] from %lx to %lx\nremote_array_a[%d] from %lx to %lx\n\n",
			th,(long unsigned int)&local_array_a[offset],(long unsigned int)&local_array_a[offset+array_basic_size],
			th,(long unsigned int)&remote_array_a[offset],(long unsigned int)&remote_array_a[offset+array_basic_size]
		);
		printf("local_array_b[%d] from %lx to %lx\nremote_array_b[%d] from %lx to %lx\n\n",
			th,(long unsigned int)&local_array_b[offset],(long unsigned int)&local_array_b[offset+array_basic_size],
			th,(long unsigned int)&remote_array_b[offset],(long unsigned int)&remote_array_b[offset+array_basic_size]
		);
		#endif
	}


	#ifdef PRINT_PHASE_CHANGE
	gettimeofday(&t_beg, NULL);
	#endif
}

// The kernel operation in the parallel zone. Defined as inline to reduce call overhead
static inline void operation(pid_t my_ompid){
	bigint i,n,r,o;
	int offset = my_ompid*array_basic_size; // Different work zone for each thread
	
	for(i=0; i<main_iters; i++){ // How many main iterations will we do?
		int index = offset + i;
	
		// This is done to avoid doing a lot of multiplications in inner loop
		int limit = elems_iter*ELEMS_PER_CACHE;

		/// Reads/writes in LOCAL arrays
		#ifdef PRINT_PHASE_CHANGE // To add load without using a bigger array
		int j;
		for(j=0; j<5; j++){
		#endif
		for(n=0; n<limit; n+=ELEMS_PER_CACHE) // How many items will we process? (not in same cache line)
			local_array_b[index+n] = local_array_a[index+n];
		#ifdef PRINT_PHASE_CHANGE
		}
		#endif

		#pragma omp barrier
		#ifdef PRINT_PHASE_CHANGE
		if(my_ompid == 0){ // Only one TID printing
			gettimeofday(&t_end, NULL);
			double elapsed_time = (t_end.tv_sec - t_beg.tv_sec + (t_end.tv_usec - t_beg.tv_usec)/1.e6);
			//printf("End of low OI phase. Elapsed time since the beginning: %.2f seconds\n", elapsed_time);
			printf("l,%.2f\n", elapsed_time);
		}
		#endif

		/// Reads/writes in REMOTE arrays
		limit = remote_reads*ELEMS_PER_CACHE;
		for(r=0; r<limit; r+=ELEMS_PER_CACHE) // How many remote items will we read/write?
			remote_array_b[index+r] = remote_array_a[index+r]; // Not in same cache line

		/// Floating point OPERATIONS
		data_type datum_a = local_array_a[index];
		data_type datum_b = local_array_b[index];
		data_type datum_c;
		for(o=0; o<ops; o++) // How many float operations per iteration?
			datum_c = datum_a * 1.42 + datum_b * 0.58;

		#pragma omp barrier
		#ifdef PRINT_PHASE_CHANGE
		if(my_ompid == 0){ // Only one TID printing
			gettimeofday(&t_end, NULL);
			double elapsed_time = (t_end.tv_sec - t_beg.tv_sec + (t_end.tv_usec - t_beg.tv_usec)/1.e6);
			//printf("End of high OI phase. Elapsed time since the beginning: %.2f seconds\n", elapsed_time);
			printf("h,%.2f\n", elapsed_time);
		}
		#endif

		#pragma omp barrier

		/// The cache is flushed (not the whole arrays, just what we processed in this iteration) to force fails
		#ifdef DO_CLFLUSH
		cache_flush(&local_array_a[index], limit);
		cache_flush(&local_array_b[index], limit);
		cache_flush(&remote_array_a[index], limit);
		cache_flush(&remote_array_b[index], limit);

		#pragma omp barrier
		#endif
	}
}

void set_options_from_parameters(int argc, char** argv){
	char c;

	// Parses argv with getopt
	while ((c = getopt (argc, argv, "i:l:r:o:t:m:M:")) != -1){
		switch (c) {
			case 'i': // Main iterations
				main_iters = atol(optarg);
				break;
			case 'l': // Number of elements read/written per iteration
				elems_iter = atol(optarg);
				break;
			case 'r': // Remote reads/writes per iteration
				remote_reads = atol(optarg);
				break;
			case 'o': // Number of floating operations per iteration
				ops = atol(optarg);
				break;
			case 't': // Number of threads
				num_th = atoi(optarg);
				
				// No more threads than CPUs per memory because they will all belong to the same node
				if(num_th > CPUS_PER_MEMORY)
					num_th = CPUS_PER_MEMORY;
				break;
			case 'm': // Local memory node
				local_node = atoi(optarg);
				break;
			case 'M': // Remote memory node
				remote_node = atoi(optarg);
				break;
			case '?': // Default
				if (isprint(optopt))
					fprintf (stderr, "Unknown option `-%c'.\n", optopt);
				else
					fprintf (stderr, "Unknown option character `\\x%x'.\n", optopt);
				usage(argv);
				exit(1);
		}
	}
}

void pick_cpus(){
	selected_cpus = (unsigned char*)calloc(num_th, sizeof(unsigned char));
	cpu_set_t aff;
	sched_getaffinity(0,sizeof(cpu_set_t),&aff);

	// Gets available CPU IDs from local_node to pin the threads
	int i, picked_cpus = 0;
	for(i=0;i<CPUS_PER_MEMORY && i != num_th;i++) {
		int current_cpu = node_cpu_map[local_node][i]; // Working with node 0
		if(CPU_ISSET(current_cpu, &aff)){
			selected_cpus[picked_cpus] = current_cpu;
			picked_cpus++;
		}
	}
	
	// Lowers number of threads if less were picked due to numactl or stuff
	if(picked_cpus < num_th)
		num_th = picked_cpus;
}

void calculate_array_sizes(){
	// This way we avoid being out of bounds
	bigint max_p = elems_iter;
	if(remote_reads > max_p)
		max_p = remote_reads;
	array_basic_size = main_iters + max_p*ELEMS_PER_CACHE;

	array_total_size = array_basic_size*num_th; // In this case, the whole array would be proportional to the number of threads
}

int main(int argc, char *argv[]){
	detect_system();

	// Set defaults
	main_iters = DEFAULT_MAIN_ITERS;
	elems_iter = DEFAULT_ELEMS_ITER;
	remote_reads = DEFAULT_REMOTE_READS;
	ops = DEFAULT_NUMBER_OPS;
	num_th = DEFAULT_NUM_THREADS;
	local_node = DEFAULT_LOCAL_NODE;
	remote_node = DEFAULT_REMOTE_NODE;

	set_options_from_parameters(argc, argv);
	
	// Sanity checks
	if(local_node >= NUM_OF_MEMORIES)
		local_node = 0;
	if(remote_node >= NUM_OF_MEMORIES)
		remote_node = NUM_OF_MEMORIES - 1; // Maximum
	
	pick_cpus();

	calculate_array_sizes();

	#ifdef OUTPUT
	// Just printings
	print_params();
	print_selected_cpus();
	#endif
	#ifdef DOGETPID
	printf("PID: %d\n", getpid()); // May be useful sometimes
	#endif

	// Sets number of threads to use
	omp_set_num_threads(num_th);
	
	data_initialization();

	#ifdef PRINT_PHASE_CHANGE
	printf("s,t\n");
	#endif

	// Parallel zone
	#pragma omp parallel shared(local_array_a, local_array_b, remote_array_a, remote_array_b, selected_cpus)
	{
		int tid = syscall(SYS_gettid);
		pid_t ompid = omp_get_thread_num(); // From 0 to num_th
		unsigned char my_cpu = selected_cpus[ompid]; // Picks selected CPU with omp index

		// Pins thread to CPU
		cpu_set_t my_affinity;
		CPU_ZERO(&my_affinity);
		CPU_SET(my_cpu, &my_affinity);
		sched_setaffinity(0,sizeof(cpu_set_t),&my_affinity);

		#ifdef OUTPUT
		printf("I am thread (%d,%d) and I got CPU %u\n", ompid, tid, my_cpu);
		#endif

		operation(ompid); // Kernel

		#ifdef OUTPUT
		printf("I am thread (%d,%d), pinned in CPU %d and I just finished\n", ompid, tid, my_cpu);
		#endif
	}

	// Frees resources and end
	int i;
	for(i=0;i<NUM_OF_MEMORIES;i++)
		free(node_cpu_map[i]);
	free(node_cpu_map);
	free(selected_cpus);
	numa_free(local_array_a, array_total_size*sizeof(data_type));
	numa_free(local_array_b, array_total_size*sizeof(data_type));
	numa_free(remote_array_a, array_total_size*sizeof(data_type));
	numa_free(remote_array_b, array_total_size*sizeof(data_type));
	return 0;
}
