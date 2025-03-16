load(":sycl_toolchain_config.bzl", "sycl_toolchain_config")

package(default_visibility = ["//visibility:public"])

licenses(["notice"])

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
    cpu = "%{target_cpu}",
    compiler = "%{compiler}",
    toolchain_identifier = "%{sycl_toolchain_identifier}",
    host_system_name = "%{host_system_name}",
    target_system_name = "%{target_system_name}",
    target_libc = "%{target_libc}",
    abi_version = "%{abi_version}",
    abi_libc_version = "%{abi_libc_version}",
    cxx_builtin_include_directories = [%{cxx_builtin_include_directories}],
    extra_no_canonical_prefixes_flags = [%{extra_no_canonical_prefixes_flags}],
    host_c_compiler_path = "%{host_c_compiler_path}",
    host_cc_compiler_path = "%{host_cc_compiler_path}",
    host_compiler_prefix = "%{host_compiler_prefix}",
    host_unfiltered_compile_flags = [%{unfiltered_compile_flags}],
    linker_bin_path = "%{linker_bin_path}",
)

toolchain(
    name = "sycl-toolchain",
    exec_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
    target_compatible_with = [
        "@platforms//cpu:x86_64",
        "@platforms//os:linux",
    ],
    toolchain = "@local_config_sycl//:sycl-compiler-%{name}",
    toolchain_type = "@bazel_tools//tools/cpp:toolchain_type",
)
