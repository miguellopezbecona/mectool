#pragma once

#include <string.h>
#include <dirent.h>

#include <vector>
#include <algorithm> // sort, min_element and max_element
using namespace std;

#include "system_struct.hpp"
#include "perf_event.h"

//#define INIT_VERBOSE

typedef struct energy_data {
	static vector<char*> rapl_domain_names;
	static int NUM_RAPL_DOMAINS;

	double** prev_vals; // For increments
	double** curr_vals;
	char** units;

	int** fd;
	double* scale;

	energy_data(){}
	~energy_data();
	void detect_domains();
	void allocate_data();
	int prepare_energy_data();

	int get_domain_pos(const char* domain);

	void read_buffer();
	void print_curr_vals();
	void print_curr_vals_with_time(double elapsed_time);

	// Many aren't used, but can be useful
	double get_curr_val(int node); // Assuming "cores" domain
	double get_curr_val(int node, const char* domain);
	vector<double> get_curr_vals_from_node(int node); // For all domains
	vector<double> get_curr_vals_from_domain(const char* domain); // For all nodes

	double** get_curr_vals(); // Everything

	void close_buffers();
} energy_data_t;

