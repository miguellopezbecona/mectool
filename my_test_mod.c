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
#define DEFAULT_LOCAL_ELEMS 1
#define DEFAULT_REMOTE_ELEMS 0
#define DEFAULT_NUMBER_OPS 1
#define DEFAULT_NUM_THREADS 1
#define DEFAULT_LOCAL_NODE 0
#define DEFAULT_REMOTE_NODE 1

#define CACHE_LINE_SIZE 64
#define ELEMS_PER_CACHE (int) (CACHE_LINE_SIZE / sizeof(data_type))

#define INCR_I index += ELEMS_PER_CACHE
#define L local_array_b[index] = local_array_a[index] // Reads/writes in LOCAL arrays
#define R remote_array_b[index] = remote_array_a[index] // Reads/writes in REMOTE arrays
#define O data_type datum_c = local_array_a[index] * 1.42 + local_array_b[index] * 0.58 // Floating point OPERATIONS

#define DO_CLFLUSH
//#define OUTPUT
//#define DOGETPID

// Main data
bigint array_basic_size; // array_total_size / num_th
bigint array_total_size;
data_type* local_array_a;
data_type* local_array_b;
data_type* remote_array_a;
data_type* remote_array_b;

// Options
bigint main_iters;
bigint local_elems;
bigint remote_elems;
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
	printf("I: %lu\nL: %lu\nR: %lu\nO: %lu\nThs: %d\nArray size: %lu\nLocal node: %d\nRemote node: %d\n\n",main_iters,local_elems,remote_elems,ops,num_th,array_total_size, local_node, remote_node);
}

void usage(char **argv) {
	printf("Usage: %s [-imain_iterations] [-llocal_elements_processed_per_iteration] [-rremote_elements_processed_per_iteration] [-ooperations_per_iteration] [-tnumber_of_threads] [-mlocal_node] [-Mremote_node]\n\n", argv[0]);
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
}

// The kernel operation in the parallel zone. Defined as inline to reduce call overhead
static inline void operation(pid_t my_ompid){
	bigint i, j, l = local_elems, r = remote_elems, o = ops;
	int offset = my_ompid*array_basic_size; // Different work zone for each thread

	// To know how many cache lines are processed in each iteration
	bigint mx_lr = l;
	if(r > mx_lr)
		mx_lr = r;
	size_t sz = mx_lr * ELEMS_PER_CACHE;

	// The three kind of operations will be done many times together as the mininum between them
	bigint mn3 = l;
	if(r < mn3)
		mn3 = r;
	if(o < mn3)
		mn3 = o;
	l -= mn3;
	r -= mn3;
	o -= mn3;

	// Ugly chain of ifs for calculating the limit of the inner loops
	bigint mn_lr, mn_lo, mn_ro, mn_l, mn_r, mn_o;
	mn_lr = mn_lo = mn_ro = mn_l = mn_r = mn_o = 0;
	if(l == 0){ // l was the global minimum
		mn_ro = r;
		if(o < mn_ro){ // o is the next minimum, r operations left
			mn_ro = o;
			mn_r = r-o;
		} else
			mn_o = o-r;
	} else if(r == 0){
		mn_lo = l;
		if(o < mn_lo){
			mn_lo = o;
			mn_l = l-o;
		} else
			mn_o = o-l;
	} else if(o == 0){
		mn_lr = l;
		if(r < mn_lr){
			mn_lr = r;
			mn_l = l-r;
		} else
			mn_r = r-l;
	}

	unsigned max_cache_line = ((my_ompid+1)*array_basic_size) / (int) ELEMS_PER_CACHE;
	unsigned curr_cache_line = offset / (int) ELEMS_PER_CACHE;

	#ifdef OUTPUT
	printf("L:%ld R:%ld O:%ld|mxLR:%ld mn3:%ld sz:%ld|mnLR:%ld mnLO:%ld mnRO:%ld|mnL:%ld mnR:%ld mnO:%ld|initCL:%d mxCL:%d\n", local_elems, remote_elems, ops, mx_lr, mn3, sz, mn_lr, mn_lo, mn_ro, mn_l, mn_r, mn_o, curr_cache_line, max_cache_line);
	#endif

	#pragma omp barrier
	
	for(i=0; i<main_iters; i++){ // How many main iterations will we do?
		int base_index = curr_cache_line * ELEMS_PER_CACHE;
		int index = base_index;
	
		// Three kind of operations made in each iteration
		for(j=0;j<mn3;j++){
			INCR_I; L; R; O;
		}

		// Two kind of operations made in each iteration. Only one of these will be executed
		for(j=0;j<mn_lr;j++){
			INCR_I; L; R;
		}
		for(j=0;j<mn_ro;j++){
			INCR_I; R; O;
		}
		for(j=0;j<mn_lo;j++){
			INCR_I; L; O;
		}

		// One kind of operation made in each iteration. Only one of these will be executed
		for(j=0;j<mn_l;j++){
			INCR_I; L;
		}
		for(j=0;j<mn_r;j++){
			INCR_I; R;
		}
		for(j=0;j<mn_o;j++){
			O;
		}

		curr_cache_line = (curr_cache_line + mx_lr) % max_cache_line;

		#pragma omp barrier

		/// The cache is flushed (not the whole arrays, just what we processed in this iteration) to force fails
		#ifdef DO_CLFLUSH
		cache_flush(&local_array_a[base_index], sz);
		cache_flush(&local_array_b[base_index], sz);
		cache_flush(&remote_array_a[base_index], sz);
		cache_flush(&remote_array_b[base_index], sz);

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
			case 'l': // Local reads/writes per iteration
				local_elems = atol(optarg);
				break;
			case 'r': // Remote reads/writes per iteration
				remote_elems = atol(optarg);
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
	bigint max_p = local_elems;
	if(remote_elems > max_p)
		max_p = remote_elems;
	array_basic_size = max_p*ELEMS_PER_CACHE;

	array_total_size = array_basic_size*num_th; // In this case, the whole array would be proportional to the number of threads
}

int main(int argc, char *argv[]){
	detect_system();

	// Set defaults
	main_iters = DEFAULT_MAIN_ITERS;
	local_elems = DEFAULT_LOCAL_ELEMS;
	remote_elems = DEFAULT_REMOTE_ELEMS;
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
