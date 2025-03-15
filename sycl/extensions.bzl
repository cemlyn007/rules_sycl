"""This module provides extension-related functions for Bazel."""

load("//sycl:sycl_configure.bzl", "sycl_autoconf", "sycl_autoconf_toolchains")

def _impl(ctx):
    sycl_autoconf_toolchains(name = "local_config_sycl_toolchains")
    sycl_autoconf(name = "local_config_sycl")

sycl_configure_extension = module_extension(
    implementation = _impl,
)
