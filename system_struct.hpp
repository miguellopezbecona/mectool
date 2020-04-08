/*
 * Defines the system structure: how many CPUs are, where is each cpu/thread...
 */
#pragma once

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <numa.h>

#include <vector>
using namespace std;

typedef struct system_struct {
	static int NUM_OF_CPUS;
	static int NUM_OF_MEMORIES;
	static int CPUS_PER_MEMORY;
	static const int FREE_CORE = -1;

	// To know where each CPU is (in terms of memory node)
	static int* cpu_node_map; // cpu_node_map[cpu] = node
	static int** node_cpu_map; // cpu_node_map[node] = list(cpus)

	static int detect_system();
} system_struct_t;

