## Overview
This folder contains the following applications:
* `mectool.cpp`: a C++ profiler that uses Running Average Power Limit (RAPL) to read energy consumptions for all the nodes and RAPL domains from the system. It has two modes: `ONE_MEASURE` and a incremental profiling, depending whether the mentioned macro is commented or not. The first mode, as the name suggests, opens the counters and only reads its values when the profiler ends (needs `SIGINT` (Ctrl+C) signal), so metrics like total consumption or mean consumption per second (for each node, domain, and in total) are obtained. The other mode reads the counters periodically (the period can be customized in one of the parameters), so it can print the information and dump the data into CSV files (if `DUMP_TO_FILE` macro is uncommented) to be analyzed a posteriori with `rapl.R` file provided. This C++ app is partially merged with the main thread/page migration tool. In fact, the RAPL profiler uses a copy of the `system_struct_t` component of the other one. Its parameters are the following:
  - `-p`: period for incremental reading in milliseconds (default: 1000).
  - `-d`: RAPL domains to be read, separated by an underscore and without "energy-" (e.g: "pkg_ram"). If this parameter is not specified, the profiler tries to detect all the available RAPL domains dynamically.
* `my_test.c`: a test application, heavily based on the `ABC` test program in `migration_tool` folder, that intends to help understanding energy consumption in a system by parametrizing specific operations such as read/write operations, remote data reads/writes, floating point operations, etc. It uses a simplified version of the `system_struct_t` component from the main migration tool to be C-compliant. Its parameters are the following:
  - `-i`: main iterations. It affects the size of the arrays. (default: 1000).
  - `-l`: elements read/written from local arrays per iteration. These elements are from different cache lines (default: 1).
  - `-r`: elements read/written from remote arrays per iteration. These elements are from different cache lines (default: 0).
  - `-o`: floating point operations per iteration (default: 1).
  - `-t`: number of threads, which would work in different chunks of the arrays. It will be set to `CPUS_PER_MEMORY` if an upper out of bound value is provided, because threads will be pinned to CPUs from the same (local) node (default: 1).
  - `-m`: local node reference. Will be set to 0 if an upper out of bound value is provided (default: 0).
  - `-M`: remote node reference. Will be set to `NUM_OF_MEMORIES-1` if an upper out of bound value is provided (default: 1).
  - The total array size depends on `-l` and `-t` parameters.
Note that operational intensity is defined as the relation between FLOPS and the number of bytes read by the DRAM, so for this application it may be estimated as O/(4*N) (4 because each element is a float, which is stored in 4 bytes).
* `my_test_mod.c`: a variation from the previous application. The main difference is that the three main operations (read/write local elements, read/write remote elements, and floating operations) are mixed rather than having a phase for just reading/writing local elements, then another one just for floating operations, and so on. Also, in each `i` iteration the work is repeated (full arrays are looped), instead of advancing one element.

Some macros can be commented/uncommented in both applications to increase/decrease the amount of printing, they all have a `OUTPUT`-like name.

## Compiling and executing
Using RAPL requires a Linux system with a 3.13+ kernel version. RAPL values are read using a `perf_event_open` fashion so, unless you are root, `perf_event_paranoid` system file should contain a zero or else the profiler will not be able to read the hardware counters. You can solve it with the following command:
```bash
echo "0" | sudo tee /proc/sys/kernel/perf_event_paranoid > /dev/null
```

The two apps require `libnuma-dev` package as well, so you need to install it first.

If you just want to build the profiler, you can use the Makefile inside the source code folder. I have already facilitated a bash script to also execute it along with the test program. Just go to the source code folder and execute `test` script:
```bash
bash test.sh
```

In normal conditions, the profiler never ends and needs a `SIGINT` (Ctrl+C) signal to end in a clean way.

Regarding the R file, you can execute it from a terminal with the following command:
```bash
Rscript rapl.R data_file.csv [incr_cons_file.csv]
```
In that way, if will export the generated plots into PNG files with identifiable names.

## Experiments folder
To be documented.

## License
Do whatever you want with this code.
