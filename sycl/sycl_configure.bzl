""" IDK """

def resolve_labels(repository_ctx, labels):
    """Resolves a collection of labels to their paths.

    Label resolution can cause the evaluation of Starlark functions to restart.
    For functions with side-effects (like the auto-configuration functions, which
    inspect the system and touch the file system), such restarts are costly.
    We cannot avoid the restarts, but we can minimize their penalty by resolving
    all labels upfront.

    Among other things, doing less work on restarts can cut analysis times by
    several seconds and may also prevent tickling kernel conditions that cause
    build failures.  See https://github.com/bazelbuild/bazel/issues/5196 for
    more details.

    Args:
      repository_ctx: The context with which to resolve the labels.
      labels: Labels to be resolved expressed as a list of strings.

    Returns:
      A dictionary with the labels as keys and their paths as values.
    """
    return dict([(label, repository_ctx.path(Label(label))) for label in labels])

def get_cpu_value(repository_ctx):
    """Compute the cpu_value based on the OS name. Doesn't %-escape the result!

    Args:
      repository_ctx: The repository context.
    Returns:
      One of (darwin, freebsd, x64_windows, ppc, s390x, arm, aarch64, k8, piii)
    """
    os_name = repository_ctx.os.name
    arch = repository_ctx.os.arch
    if os_name.startswith("mac os"):
        # Check if we are on x86_64 or arm64 and return the corresponding cpu value.
        return "darwin_" + ("arm64" if arch == "aarch64" else "x86_64")
    if os_name.find("freebsd") != -1:
        return "freebsd"
    if os_name.find("openbsd") != -1:
        return "openbsd"
    if os_name.find("windows") != -1:
        if arch == "aarch64":
            return "arm64_windows"
        else:
            return "x64_windows"

    if arch in ["power", "ppc64le", "ppc", "ppc64"]:
        return "ppc"
    if arch in ["s390x"]:
        return "s390x"
    if arch in ["mips64"]:
        return "mips64"
    if arch in ["riscv64"]:
        return "riscv64"
    if arch in ["arm", "armv7l"]:
        return "arm"
    if arch in ["aarch64"]:
        return "aarch64"
    return "k8" if arch in ["amd64", "x86_64", "x64"] else "piii"

def sycl_autoconf_toolchains_impl(repository_ctx):
    """Generate BUILD file with 'toolchain' targets for the local host C++ toolchain.

    Args:
      repository_ctx: repository context
    """
    paths = resolve_labels(repository_ctx, [
        "@rules_sycl//sycl:BUILD.toolchains.tpl",
    ])
    repository_ctx.template(
        "BUILD",
        paths["@rules_sycl//sycl:BUILD.toolchains.tpl"],
        {"%{name}": get_cpu_value(repository_ctx)},
    )

sycl_autoconf_toolchains = repository_rule(
    implementation = sycl_autoconf_toolchains_impl,
    configure = True,
)

def sycl_autoconf_impl(repository_ctx):
    """Function description.

    Args:
        repository_ctx: argument description, can be
        multiline with additional indentation.
    """
    cpu_value = get_cpu_value(repository_ctx)
    paths = resolve_labels(repository_ctx, [
        "@rules_sycl//sycl:BUILD.tpl",
        # "@rules_cc//cc/private/toolchain:generate_system_module_map.sh",
        "@rules_sycl//sycl:sycl_toolchain_config.bzl",
    ])

    repository_ctx.symlink(
        paths["@rules_sycl//sycl:sycl_toolchain_config.bzl"],
        "sycl_toolchain_config.bzl",
    )

    # auto_configure_warning_maybe(repository_ctx, "CC used: " + str(cc))
    # tool_paths = _get_tool_paths(repository_ctx, overridden_tools)

    # cc_toolchain_identifier = escape_string(get_env_var(
    #     repository_ctx,
    #     "CC_TOOLCHAIN_NAME",
    #     "local",
    #     False,
    # ))
    sycl_toolchain_identifier = "local"
    repository_ctx.template(
        "BUILD",
        paths["@rules_sycl//sycl:BUILD.tpl"],
        # @unsorted-dict-items
        {
            # "%{abi_libc_version}": escape_string(get_env_var(
            #     repository_ctx,
            #     "ABI_LIBC_VERSION",
            #     "local",
            #     False,
            # )),
            # "%{abi_version}": escape_string(get_env_var(
            #     repository_ctx,
            #     "ABI_VERSION",
            #     "local",
            #     False,
            # )),
            # "%{cc_compiler_deps}": get_starlark_list([
            #     ":builtin_include_directory_paths",
            #     ":cc_wrapper",
            #     ":deps_scanner_wrapper",
            # ] + (
            #     [":validate_static_library"] if "validate_static_library" in tool_paths else []
            # )),
            "%{sycl_toolchain_identifier}": sycl_toolchain_identifier,
            # "%{compile_flags}": [],
            # "%{compiler}": escape_string(get_env_var(
            #     repository_ctx,
            #     "BAZEL_COMPILER",
            #     _get_compiler_name(repository_ctx, cc),
            #     False,
            # )),
            # "%{conly_flags}": get_starlark_list(conly_opts),
            # "%{coverage_compile_flags}": coverage_compile_flags,
            # "%{coverage_link_flags}": coverage_link_flags,
            # "%{cxx_builtin_include_directories}": get_starlark_list(builtin_include_directories),
            # "%{cxx_flags}": get_starlark_list(cxx_opts + _escaped_cplus_include_paths(repository_ctx)),
            # "%{dbg_compile_flags}": get_starlark_list(["-g"]),
            # "%{extra_flags_per_feature}": repr(extra_flags_per_feature),
            # "%{host_system_name}": escape_string(get_env_var(
            #     repository_ctx,
            #     "BAZEL_HOST_SYSTEM",
            #     "local",
            #     False,
            # )),
            # "%{link_flags}": get_starlark_list(force_linker_flags + (
            #     ["-Wl,-no-as-needed"] if is_as_needed_supported else []
            # ) + _add_linker_option_if_supported(
            #     repository_ctx,
            #     cc,
            #     force_linker_flags,
            #     "-Wl,-z,relro,-z,now",
            #     "-z",
            # ) + (
            #     [
            #         "-headerpad_max_install_names",
            #     ] if darwin else [
            #         # Gold linker only? Can we enable this by default?
            #         # "-Wl,--warn-execstack",
            #         # "-Wl,--detect-odr-violations"
            #     ] + _add_compiler_option_if_supported(
            #         # Have gcc return the exit code from ld.
            #         repository_ctx,
            #         cc,
            #         "-pass-exit-codes",
            #     )
            # ) + link_opts),
            # "%{link_libs}": get_starlark_list(link_libs),
            # "%{modulemap}": ("\":module.modulemap\"" if generate_modulemap else "None"),
            "%{name}": cpu_value,
            # "%{opt_compile_flags}": get_starlark_list(
            #     [
            #         # No debug symbols.
            #         # Maybe we should enable https://gcc.gnu.org/wiki/DebugFission for opt or
            #         # even generally? However, that can't happen here, as it requires special
            #         # handling in Bazel.
            #         "-g0",

            #         # Conservative choice for -O
            #         # -O3 can increase binary size and even slow down the resulting binaries.
            #         # Profile first and / or use FDO if you need better performance than this.
            #         "-O2",

            #         # Security hardening on by default.
            #         # Conservative choice; -D_FORTIFY_SOURCE=2 may be unsafe in some cases.
            #         "-D_FORTIFY_SOURCE=1",

            #         # Disable assertions
            #         "-DNDEBUG",

            #         # Removal of unused code and data at link time (can this increase binary
            #         # size in some cases?).
            #         "-ffunction-sections",
            #         "-fdata-sections",
            #     ],
            # ),
            # "%{opt_link_flags}": get_starlark_list(
            #     ["-Wl,-dead_strip"] if darwin else _add_linker_option_if_supported(
            #         repository_ctx,
            #         cc,
            #         force_linker_flags,
            #         "-Wl,--gc-sections",
            #         "-gc-sections",
            #     ),
            # ),
            # "%{supports_start_end_lib}": "True" if gold_or_lld_linker_path else "False",
            # "%{target_cpu}": escape_string(get_env_var(
            #     repository_ctx,
            #     "BAZEL_TARGET_CPU",
            #     cpu_value,
            #     False,
            # )),
            # "%{target_libc}": "macosx" if darwin else escape_string(get_env_var(
            #     repository_ctx,
            #     "BAZEL_TARGET_LIBC",
            #     "local",
            #     False,
            # )),
            # "%{target_system_name}": escape_string(get_env_var(
            #     repository_ctx,
            #     "BAZEL_TARGET_SYSTEM",
            #     "local",
            #     False,
            # )),
            # "%{tool_paths}": ",\n        ".join(
            #     ['"%s": "%s"' % (k, v) for k, v in tool_paths.items() if v != None],
            # ),
            # "%{unfiltered_compile_flags}": get_starlark_list(
            #     _get_no_canonical_prefixes_opt(repository_ctx, cc) + [
            #         # Make C++ compilation deterministic. Use linkstamping instead of these
            #         # compiler symbols.
            #         "-Wno-builtin-macro-redefined",
            #         "-D__DATE__=\\\"redacted\\\"",
            #         "-D__TIMESTAMP__=\\\"redacted\\\"",
            #         "-D__TIME__=\\\"redacted\\\"",
            #     ],
            # ),
        },
    )

sycl_autoconf = repository_rule(
    implementation = sycl_autoconf_impl,
    configure = True,
)
