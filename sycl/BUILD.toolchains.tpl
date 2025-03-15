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
