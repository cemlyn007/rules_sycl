"""This module provides extension-related functions for Bazel."""

load("//sycl:repositories.bzl", "sycl_repository")

def _sycl_impl(ctx):
    print("ctx.modules", ctx.modules)
    sycl_repository(name = "sycl", url = "hellos", sha256 = "123")

sycl_extension = module_extension(
    implementation = _sycl_impl,
)
