"""Configuration for the SYCL toolchain."""

load(
    "@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl",
    "action_config",
    "feature",
    "flag_group",
    "flag_set",
    "tool",
    "tool_path",
    "variable_with_value",
    "with_feature_set",
)
load("@rules_cc//cc:action_names.bzl", "ACTION_NAMES")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")

def _iterate_flag_group(iterate_over, flags = [], flag_groups = []):
    return flag_group(
        iterate_over = iterate_over,
        expand_if_available = iterate_over,
        flag_groups = flag_groups,
        flags = flags,
    )

def all_assembly_actions():
    return [
        ACTION_NAMES.assemble,
        ACTION_NAMES.preprocess_assemble,
    ]

def all_compile_actions():
    return [
        ACTION_NAMES.assemble,
        ACTION_NAMES.c_compile,
        ACTION_NAMES.cpp_compile,
        ACTION_NAMES.cpp_header_parsing,
        ACTION_NAMES.cpp_module_codegen,
        ACTION_NAMES.cpp_module_compile,
        ACTION_NAMES.linkstamp_compile,
        ACTION_NAMES.preprocess_assemble,
    ]

def all_c_compile_actions():
    return [
        ACTION_NAMES.c_compile,
    ]

def all_cpp_compile_actions():
    return [
        ACTION_NAMES.cpp_compile,
        ACTION_NAMES.cpp_header_parsing,
        ACTION_NAMES.cpp_module_codegen,
        ACTION_NAMES.cpp_module_compile,
        ACTION_NAMES.linkstamp_compile,
    ]

def all_preprocessed_actions():
    return [
        ACTION_NAMES.c_compile,
        ACTION_NAMES.cpp_compile,
        ACTION_NAMES.cpp_header_parsing,
        ACTION_NAMES.cpp_module_codegen,
        ACTION_NAMES.cpp_module_compile,
        ACTION_NAMES.linkstamp_compile,
        ACTION_NAMES.preprocess_assemble,
    ]

def all_link_actions():
    return [
        ACTION_NAMES.cpp_link_executable,
        ACTION_NAMES.cpp_link_dynamic_library,
        ACTION_NAMES.cpp_link_nodeps_dynamic_library,
    ]

def all_executable_link_actions():
    return [
        ACTION_NAMES.cpp_link_executable,
    ]

def all_shared_library_link_actions():
    return [
        ACTION_NAMES.cpp_link_dynamic_library,
        ACTION_NAMES.cpp_link_nodeps_dynamic_library,
    ]

def all_archive_actions():
    return [ACTION_NAMES.cpp_link_static_library]

def all_strip_actions():
    return [ACTION_NAMES.strip]

def _library_to_link(flag_prefix, value, iterate = None):
    return flag_group(
        flags = [
            "{}%{{libraries_to_link.{}}}".format(
                flag_prefix,
                iterate if iterate else "name",
            ),
        ],
        iterate_over = ("libraries_to_link." + iterate if iterate else None),
        expand_if_equal = variable_with_value(
            name = "libraries_to_link.type",
            value = value,
        ),
    )

def _surround_static_library(prefix, suffix):
    return [
        flag_group(
            flags = [prefix, "%{libraries_to_link.name}", suffix],
            expand_if_true = "libraries_to_link.is_whole_archive",
        ),
        flag_group(
            flags = ["%{libraries_to_link.name}"],
            expand_if_false = "libraries_to_link.is_whole_archive",
        ),
    ]

def _prefix_static_library(prefix):
    return [
        flag_group(
            flags = ["%{libraries_to_link.name}"],
            expand_if_false = "libraries_to_link.is_whole_archive",
        ),
        flag_group(
            flags = [prefix + "%{libraries_to_link.name}"],
            expand_if_true = "libraries_to_link.is_whole_archive",
        ),
    ]

def _static_library_to_link(alwayslink_prefix, alwayslink_suffix = None):
    if alwayslink_suffix:
        flag_groups = _surround_static_library(alwayslink_prefix, alwayslink_suffix)
    else:
        flag_groups = _prefix_static_library(alwayslink_prefix)
    return flag_group(
        flag_groups = flag_groups,
        expand_if_equal = variable_with_value(
            name = "libraries_to_link.type",
            value = "static_library",
        ),
    )

def _libraries_to_link_group(flavour):
    if flavour == "linux":
        return _iterate_flag_group(
            iterate_over = "libraries_to_link",
            flag_groups = [
                flag_group(
                    flags = ["-Wl,--start-lib"],
                    expand_if_equal = variable_with_value(
                        name = "libraries_to_link.type",
                        value = "object_file_group",
                    ),
                ),
                _library_to_link("", "object_file_group", "object_files"),
                flag_group(
                    flags = ["-Wl,--end-lib"],
                    expand_if_equal = variable_with_value(
                        name = "libraries_to_link.type",
                        value = "object_file_group",
                    ),
                ),
                _library_to_link("", "object_file"),
                _library_to_link("", "interface_library"),
                _static_library_to_link("-Wl,-whole-archive", "-Wl,-no-whole-archive"),
                _library_to_link("-l", "dynamic_library"),
                _library_to_link("-l:", "versioned_dynamic_library"),
            ],
        )
    else:
        fail("Unsupported flavour!")

def _sysroot_group():
    return flag_group(
        flags = ["--sysroot=%{sysroot}"],
        expand_if_available = "sysroot",
    )

def _no_canonical_prefixes_group(extra_flags):
    return flag_group(
        flags = [
            "-no-canonical-prefixes",
        ] + extra_flags,
    )

def _features(cpu, compiler, ctx):
    if cpu == "k8":
        isystem_flags = []
        for cxx_builtin_include_directory in ctx.attr.cxx_builtin_include_directories:
            isystem_flags.append("-isystem")
            isystem_flags.append(cxx_builtin_include_directory)

        return [
            feature(name = "no_legacy_features"),
            feature(
                name = "all_compile_flags",
                enabled = True,
                flag_sets = [
                    flag_set(
                        actions = all_compile_actions(),
                        flag_groups = [
                            flag_group(
                                flags = ["-MD", "-MF", "%{dependency_file}"],
                                expand_if_available = "dependency_file",
                            ),
                            flag_group(
                                flags = ["-gsplit-dwarf"],
                                expand_if_available = "per_object_debug_info_file",
                            ),
                        ],
                    ),
                    flag_set(
                        actions = all_preprocessed_actions(),
                        flag_groups = [
                            flag_group(
                                flags = ["-frandom-seed=%{output_file}"],
                                expand_if_available = "output_file",
                            ),
                            _iterate_flag_group(
                                flags = ["-D%{preprocessor_defines}"],
                                iterate_over = "preprocessor_defines",
                            ),
                            _iterate_flag_group(
                                flags = ["-include", "%{includes}"],
                                iterate_over = "includes",
                            ),
                            _iterate_flag_group(
                                flags = ["-iquote", "%{quote_include_paths}"],
                                iterate_over = "quote_include_paths",
                            ),
                            _iterate_flag_group(
                                flags = ["-I%{include_paths}"],
                                iterate_over = "include_paths",
                            ),
                            _iterate_flag_group(
                                flags = ["-isystem", "%{system_include_paths}"],
                                iterate_over = "system_include_paths",
                            ),
                            flag_group(
                                flags = isystem_flags,
                            ),
                            _iterate_flag_group(
                                flags = ["-F", "%{framework_include_paths}"],
                                iterate_over = "framework_include_paths",
                            ),
                        ] + ([
                            flag_group(flags = ctx.attr.host_unfiltered_compile_flags),
                        ] if ctx.attr.host_unfiltered_compile_flags else []),
                    ),
                    flag_set(
                        actions = all_cpp_compile_actions(),
                        flag_groups = [
                            flag_group(flags = [
                                "-fmerge-all-constants",
                            ]),
                        ] if compiler == "clang" else [],
                    ),
                    flag_set(
                        actions = all_compile_actions(),
                        flag_groups = [
                            flag_group(
                                flags = [
                                    "-Wno-builtin-macro-redefined",
                                    "-D__DATE__=\"redacted\"",
                                    "-D__TIMESTAMP__=\"redacted\"",
                                    "-D__TIME__=\"redacted\"",
                                ],
                            ),
                            flag_group(
                                flags = [
                                    "-U_FORTIFY_SOURCE",
                                    "-D_FORTIFY_SOURCE=1",
                                    "-fstack-protector",
                                    "-Wall",
                                ] + ctx.attr.host_compiler_warnings + [
                                    "-fno-omit-frame-pointer",
                                ],
                            ),
                            _no_canonical_prefixes_group(
                                ctx.attr.extra_no_canonical_prefixes_flags,
                            ),
                        ],
                    ),
                    flag_set(
                        actions = all_compile_actions(),
                        flag_groups = [flag_group(flags = ["-DNDEBUG"])],
                        with_features = [with_feature_set(features = ["disable-assertions"])],
                    ),
                    flag_set(
                        actions = all_compile_actions(),
                        flag_groups = [
                            flag_group(
                                flags = [
                                    "-g0",
                                    "-O2",
                                    "-ffunction-sections",
                                    "-fdata-sections",
                                ],
                            ),
                        ],
                        with_features = [with_feature_set(features = ["opt"])],
                    ),
                    flag_set(
                        actions = all_compile_actions(),
                        flag_groups = [flag_group(flags = ["-g"])],
                        with_features = [with_feature_set(features = ["dbg"])],
                    ),
                ] + [
                    flag_set(
                        actions = all_compile_actions(),
                        flag_groups = [
                            _iterate_flag_group(
                                flags = ["%{user_compile_flags}"],
                                iterate_over = "user_compile_flags",
                            ),
                            _sysroot_group(),
                            flag_group(
                                expand_if_available = "source_file",
                                flags = ["-c", "%{source_file}"],
                            ),
                            flag_group(
                                expand_if_available = "output_assembly_file",
                                flags = ["-S"],
                            ),
                            flag_group(
                                expand_if_available = "output_preprocess_file",
                                flags = ["-E"],
                            ),
                            flag_group(
                                expand_if_available = "output_file",
                                flags = ["-o", "%{output_file}"],
                            ),
                        ],
                    ),
                ],
            ),
            feature(
                name = "all_archive_flags",
                enabled = True,
                flag_sets = [
                    flag_set(
                        actions = all_archive_actions(),
                        flag_groups = [
                            flag_group(
                                expand_if_available = "linker_param_file",
                                flags = ["@%{linker_param_file}"],
                            ),
                            flag_group(flags = ["rcsD"]),
                            flag_group(
                                flags = ["%{output_execpath}"],
                                expand_if_available = "output_execpath",
                            ),
                            flag_group(
                                iterate_over = "libraries_to_link",
                                flag_groups = [
                                    flag_group(
                                        flags = ["%{libraries_to_link.name}"],
                                        expand_if_equal = variable_with_value(
                                            name = "libraries_to_link.type",
                                            value = "object_file",
                                        ),
                                    ),
                                    flag_group(
                                        flags = ["%{libraries_to_link.object_files}"],
                                        iterate_over = "libraries_to_link.object_files",
                                        expand_if_equal = variable_with_value(
                                            name = "libraries_to_link.type",
                                            value = "object_file_group",
                                        ),
                                    ),
                                ],
                                expand_if_available = "libraries_to_link",
                            ),
                        ],
                    ),
                ],
            ),
            feature(
                name = "all_link_flags",
                enabled = True,
                flag_sets = [
                    flag_set(
                        actions = all_shared_library_link_actions(),
                        flag_groups = [flag_group(flags = ["-shared"])],
                    ),
                    flag_set(
                        actions = all_link_actions(),
                        flag_groups = ([
                            flag_group(flags = ["-Wl,-no-as-needed"]),
                        ] if cpu == "k8" else []) + ([
                            flag_group(flags = ["-B" + ctx.attr.linker_bin_path]),
                        ] if ctx.attr.linker_bin_path else []) + [
                            flag_group(
                                flags = ["@%{linker_param_file}"],
                                expand_if_available = "linker_param_file",
                            ),
                            _iterate_flag_group(
                                flags = ["%{linkstamp_paths}"],
                                iterate_over = "linkstamp_paths",
                            ),
                            flag_group(
                                flags = ["-o", "%{output_execpath}"],
                                expand_if_available = "output_execpath",
                            ),
                            _iterate_flag_group(
                                flags = ["-L%{library_search_directories}"],
                                iterate_over = "library_search_directories",
                            ),
                            _iterate_flag_group(
                                iterate_over = "runtime_library_search_directories",
                                flags = [
                                    "-Wl,-rpath,$ORIGIN/%{runtime_library_search_directories}",
                                ] if cpu == "k8" else [
                                    "-Wl,-rpath,@loader_path/%{runtime_library_search_directories}",
                                ],
                            ),
                            _libraries_to_link_group("linux"),
                            _iterate_flag_group(
                                flags = ["%{user_link_flags}"],
                                iterate_over = "user_link_flags",
                            ),
                            flag_group(
                                flags = ["-Wl,--gdb-index"],
                                expand_if_available = "is_using_fission",
                            ),
                            flag_group(
                                flags = ["-Wl,-S"],
                                expand_if_available = "strip_debug_symbols",
                            ),
                            flag_group(flags = ["-lstdc++"]),
                            _no_canonical_prefixes_group(
                                ctx.attr.extra_no_canonical_prefixes_flags,
                            ),
                        ],
                    ),
                ] + ([
                    flag_set(
                        actions = all_link_actions(),
                        flag_groups = [flag_group(flags = [
                            "-Wl,-z,relro,-z,now",
                        ])],
                    ),
                ]) + ([
                    flag_set(
                        actions = all_link_actions(),
                        flag_groups = [
                            flag_group(flags = ["-Wl,--gc-sections"]),
                            flag_group(
                                flags = ["-Wl,--build-id=md5", "-Wl,--hash-style=gnu"],
                            ),
                        ],
                    ),
                ]) + [
                    flag_set(
                        actions = all_link_actions(),
                        flag_groups = [
                            _sysroot_group(),
                        ],
                    ),
                ],
            ),
            feature(name = "disable-assertions"),
            feature(
                name = "opt",
                implies = ["disable-assertions"],
            ),
            feature(name = "fastbuild"),
            feature(name = "dbg"),
            feature(name = "supports_dynamic_linker", enabled = True),
            feature(name = "has_configured_linker_path", enabled = True),
        ]
    else:
        fail("Unreachable")

def _action_configs_with_tool(path, actions):
    return [
        action_config(
            action_name = name,
            enabled = True,
            tools = [tool(path = path)],
        )
        for name in actions
    ]

def _action_configs(assembly_path, c_compiler_path, cc_compiler_path, archiver_path, linker_path, strip_path):
    return _action_configs_with_tool(
        assembly_path,
        all_assembly_actions(),
    ) + _action_configs_with_tool(
        c_compiler_path,
        all_c_compile_actions(),
    ) + _action_configs_with_tool(
        cc_compiler_path,
        all_cpp_compile_actions(),
    ) + _action_configs_with_tool(
        archiver_path,
        all_archive_actions(),
    ) + _action_configs_with_tool(
        linker_path,
        all_link_actions(),
    ) + _action_configs_with_tool(
        strip_path,
        all_strip_actions(),
    )

def _tool_paths(cpu, ctx):
    if cpu == "k8":
        return [
            tool_path(name = "gcc", path = ctx.attr.host_compiler_path),
            tool_path(name = "ar", path = ctx.attr.host_compiler_prefix + "/ar"),
            tool_path(name = "compat-ld", path = ctx.attr.host_compiler_prefix + "/ld"),
            tool_path(name = "cpp", path = ctx.attr.host_compiler_prefix + "/cpp"),
            tool_path(name = "dwp", path = ctx.attr.host_compiler_prefix + "/dwp"),
            tool_path(name = "gcov", path = ctx.attr.host_compiler_prefix + "/gcov"),
            tool_path(name = "ld", path = ctx.attr.host_compiler_prefix + "/ld"),
            tool_path(name = "nm", path = ctx.attr.host_compiler_prefix + "/nm"),
            tool_path(name = "objcopy", path = ctx.attr.host_compiler_prefix + "/objcopy"),
            tool_path(name = "objdump", path = ctx.attr.host_compiler_prefix + "/objdump"),
            tool_path(name = "strip", path = ctx.attr.host_compiler_prefix + "/strip"),
        ]
    else:
        fail("Unreachable")

def _impl(ctx):
    cpu = ctx.attr.cpu
    compiler = ctx.attr.compiler

    if (cpu == "k8"):
        target_cpu = "k8"
        target_libc = "k8"
        action_configs = _action_configs(
            assembly_path = ctx.attr.host_compiler_path,
            c_compiler_path = ctx.attr.host_compiler_path,
            cc_compiler_path = ctx.attr.host_compiler_path,
            archiver_path = ctx.attr.host_compiler_prefix + "/ar",
            linker_path = ctx.attr.host_compiler_path,
            strip_path = ctx.attr.host_compiler_prefix + "/strip",
        )
    else:
        fail("Unsupported cpu value")

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        action_configs = action_configs,
        features = _features(cpu, compiler, ctx),
        cxx_builtin_include_directories = ctx.attr.cxx_builtin_include_directories,
        toolchain_identifier = ctx.attr.toolchain_identifier,
        host_system_name = ctx.attr.host_system_name,
        target_system_name = ctx.attr.target_system_name,
        target_cpu = target_cpu,
        target_libc = target_libc,
        compiler = compiler,
        abi_version = ctx.attr.abi_version,
        abi_libc_version = ctx.attr.abi_libc_version,
        tool_paths = _tool_paths(cpu, ctx),
    )

sycl_toolchain_config = rule(
    implementation = _impl,
    attrs = {
        "cpu": attr.string(mandatory = True, values = ["k8"]),
        "compiler": attr.string(mandatory = True),
        "toolchain_identifier": attr.string(mandatory = True),
        "host_system_name": attr.string(mandatory = True),
        "target_system_name": attr.string(mandatory = True),
        "target_libc": attr.string(mandatory = True),
        "abi_version": attr.string(mandatory = True),
        "abi_libc_version": attr.string(mandatory = True),
        "cxx_builtin_include_directories": attr.string_list(mandatory = True),
        "extra_no_canonical_prefixes_flags": attr.string_list(),
        "host_compiler_path": attr.string(),
        "host_compiler_prefix": attr.string(),
        "host_compiler_warnings": attr.string_list(),
        "host_unfiltered_compile_flags": attr.string_list(),
        "linker_bin_path": attr.string(),
    },
    provides = [CcToolchainConfigInfo],
)
