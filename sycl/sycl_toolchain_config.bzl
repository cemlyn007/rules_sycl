# Copyright 2019 The Bazel Authors. All rights reserved.
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
"""A Starlark cc_toolchain configuration rule"""

load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load(
    "@rules_cc//cc:cc_toolchain_config_lib.bzl",
    "action_config",
    "tool",
    "tool_path",
)
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")

def _impl(ctx):
    tool_paths = [
        tool_path(
            name = "gcc",
            path = "/opt/intel/oneapi/2025.0/bin/icpx",
        ),
        tool_path(
            name = "ld",
            path = "/usr/bin/ld",
        ),
        tool_path(
            name = "ar",
            path = "/usr/bin/ar",
        ),
        tool_path(
            name = "cpp",
            path = "/bin/false",
        ),
        tool_path(
            name = "gcov",
            path = "/bin/false",
        ),
        tool_path(
            name = "nm",
            path = "/bin/false",
        ),
        tool_path(
            name = "objdump",
            path = "/bin/false",
        ),
        tool_path(
            name = "strip",
            path = "/bin/false",
        ),
    ]

    action_configs = [
        action_config(
            ACTION_NAMES.c_compile,
            tools = [tool(path = "/usr/bin/gcc")],
        ),
        action_config(
            ACTION_NAMES.cpp_compile,
            tools = [tool(path = "/opt/intel/oneapi/2025.0/bin/icpx")],
        ),
    ]

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        action_configs = action_configs,
        # TODO: The next steps is to use a repository rule in a repository rule
        #  to automatically get these include directories and inject them here.
        #  We can get inspiration on how to do this from TensorFlow.
        #  We also want to add them as -isystem flags so that intellisense can detect them.
        cxx_builtin_include_directories = ctx.attr.cxx_builtin_include_directories,
        # cxx_builtin_include_directories = [
        #     "/usr/include",
        #     "/usr/lib/gcc/x86_64-linux-gnu/14/include",
        #     "/opt/intel/oneapi/mkl/2025.0/include",
        #     "/opt/intel/oneapi/compiler/2025.0/include",
        #     "/opt/intel/oneapi/compiler/2025.0/include/sycl",
        #     "/opt/intel/oneapi/compiler/2025.0/lib/clang/19/include",
        # ],
        toolchain_identifier = ctx.attr.toolchain_identifier,
        # host_system_name = "local",
        # target_system_name = "local",
        # target_cpu = "k8",
        # target_libc = "unknown",
        compiler = "clang",
        # abi_version = "unknown",
        # abi_libc_version = "unknown",
        tool_paths = tool_paths,
    )

sycl_toolchain_config = rule(
    implementation = _impl,
    attrs = {
        "toolchain_identifier": attr.string(mandatory = True),
        "cxx_builtin_include_directories": attr.string_list(mandatory = True),
    },
    provides = [CcToolchainConfigInfo],
)
