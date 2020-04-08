#ifndef __SYSTEM_STRUCT_H__
#define __SYSTEM_STRUCT_H__

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <numa.h> // numa_alloc_onnode, numa_num_configured_nodes

extern int NUM_OF_CPUS;
extern int NUM_OF_MEMORIES;
extern int CPUS_PER_MEMORY;
extern int** node_cpu_map; // cpu_node_map[node] = list(cpus)

int detect_system();
#endif

