
# source /opt/intel/oneapi/2025.0/oneapi-vars.sh
# export LD_LIBRARY_PATH=/opt/intel/oneapi/2025.0/lib:/opt/intel/oneapi/compiler/2025.0/lib
# sycl-ls
bazel build //main
./bazel-bin/main/main
