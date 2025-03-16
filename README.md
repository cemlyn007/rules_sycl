# rules_sycl
This repository contains a non-hermatic Bazel toolchain for using Intel OneAPI SYCL C++ for Linux x64_86. It also makes available the
SYCL library via `"@local_config_sycl//sycl"`. Note that you need to install Intel OneAPI and CUDA (if you want CUDA) in order to use this at the moment.

## Example

I intend on this running out of the box, but you will need to install the Intel OneAPI manually to it's default location. Then you should be able to run this example:
```
ONEAPI_DEVICE_SELECTOR="cuda:gpu" SYCL_UR_TRACE=1 bazel run //example:cpu_or_cuda
```
And if success should see:
```
Running on NVIDIA GeForce RTX 4090
Hello World! My ID is {0}
Hello World! My ID is {5}
Hello World! My ID is {7}
Hello World! My ID is {6}
Hello World! My ID is {1}
Hello World! My ID is {9}
Hello World! My ID is {8}
Hello World! My ID is {2}
Hello World! My ID is {3}
Hello World! My ID is {4}
```
Feel free to try `ONEAPI_DEVICE_SELECTOR="opencl:cpu"` instead, it did work for me but note you might need to set `LD_LIBRARY_PATH="/opt/intel/oneapi/2025.0/lib"` to stop the binary from trying to use `/usr/local/cuda/targets/x86_64-linux/lib/libOpenCL.so.1`, this is something I am working on addressing.

## Disclaimer
1. Code has heavily been inspired and copied from TensorFlow and cc_rules, I take no credit for the authors who contributed to those Git repositories, and thank them very much!
2. This is the classic it works on my machine, but I hope it works on yours as well! There are few things I have not ironned out,

    a. I doubt I have configured this to offload to the CPU.
    
    b. I have only tested this on Bazel 8.1.1 with an NVIDIA GPU with CUDA 12.8 on Ubuntu Linux x64_86.

    c. I currently have hardcoded the location of Intel OneAPI and the version to 2025.0.

    d. Whilst intellisense is detecting all the files nicely, I am getting a couple of intellisense errors in the example script... :'(
3. I am a Bazel noob, so if anyone notices anything obviously non-sensical, then please make a PR / contact me and we can address it.
