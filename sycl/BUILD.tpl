# Copyright 2016 The Bazel Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This becomes the BUILD file for @local_config_cc// under non-BSD unixes.

load(":sycl_toolchain_config.bzl", "sycl_toolchain_config")
load("@rules_cc//cc/toolchains:cc_toolchain.bzl", "cc_toolchain")
load("@rules_cc//cc/toolchains:cc_toolchain_suite.bzl", "cc_toolchain_suite")

package(default_visibility = ["//visibility:public"])

licenses(["notice"])  # Apache 2.0

filegroup(
    name = "empty",
    srcs = [],
)

cc_toolchain(
    name = "sycl-compiler-%{name}",
    toolchain_identifier = "%{sycl_toolchain_identifier}",
    toolchain_config = ":%{sycl_toolchain_identifier}",
    all_files = ":empty",
    compiler_files = ":empty",
    dwp_files = ":empty",
    linker_files = ":empty",
    objcopy_files = ":empty",
    strip_files = ":empty",
    supports_param_files = 0,
)

sycl_toolchain_config(
    name = "%{sycl_toolchain_identifier}",
    # cpu = "%{target_cpu}",
    # compiler = "%{compiler}",
    toolchain_identifier = "%{sycl_toolchain_identifier}",
    # host_system_name = "%{host_system_name}",
    # target_system_name = "%{target_system_name}",
    # target_libc = "%{target_libc}",
    # abi_version = "%{abi_version}",
    # abi_libc_version = "%{abi_libc_version}",
    # cxx_builtin_include_directories = [%{cxx_builtin_include_directories}],
    # tool_paths = {%{tool_paths}},
    # compile_flags = [%{compile_flags}],
    # opt_compile_flags = [%{opt_compile_flags}],
    # dbg_compile_flags = [%{dbg_compile_flags}],
    # conly_flags = [%{conly_flags}],
    # cxx_flags = [%{cxx_flags}],
    # link_flags = [%{link_flags}],
    # link_libs = [%{link_libs}],
    # opt_link_flags = [%{opt_link_flags}],
    # unfiltered_compile_flags = [%{unfiltered_compile_flags}],
    # coverage_compile_flags = [%{coverage_compile_flags}],
    # coverage_link_flags = [%{coverage_link_flags}],
    # supports_start_end_lib = %{supports_start_end_lib},
    # extra_flags_per_feature = %{extra_flags_per_feature},
)
