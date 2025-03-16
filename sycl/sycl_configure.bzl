""" IDK """

load(
    "//sycl:common.bzl",
    "err_out",
    "files_exist",
    "get_host_environ",
    "raw_exec",
    "which",
)

_GCC_HOST_COMPILER_PATH = "GCC_HOST_COMPILER_PATH"
_INC_DIR_MARKER_BEGIN = "#include <...>"

def auto_configure_fail(msg):
    """Output failure message when auto configuration fails."""
    red = "\033[0;31m"
    no_color = "\033[0m"
    fail("\n%sAuto-Configuration Error:%s %s\n" % (red, no_color, msg))

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

def to_list_of_strings(elements):
    """Convert the list of ["a", "b", "c"] into '"a", "b", "c"'.

    This is to be used to put a list of strings into the bzl file templates
    so it gets interpreted as list of strings in Starlark.

    Args:
      elements: list of string elements

    Returns:
      single string of elements wrapped in quotes separated by a comma."""
    quoted_strings = ["\"" + element + "\"" for element in elements]
    return ", ".join(quoted_strings)

def _cxx_inc_convert(path):
    """Convert path returned by cc -E xc++ in a complete path."""
    path = path.strip()
    return path

def _get_cxx_inc_directories_impl(repository_ctx, cc, lang_is_cpp):
    """Compute the list of default C or C++ include directories."""
    if lang_is_cpp:
        lang = "c++"
    else:
        lang = "c"

    result = raw_exec(repository_ctx, [
        cc,
        "-no-canonical-prefixes",
        "-E",
        "-x" + lang,
        "-",
        "-v",
    ])
    stderr = err_out(result)
    index1 = stderr.find(_INC_DIR_MARKER_BEGIN)
    if index1 == -1:
        return []
    index1 = stderr.find("\n", index1)
    if index1 == -1:
        return []
    index2 = stderr.rfind("\n ")
    if index2 == -1 or index2 < index1:
        return []
    index2 = stderr.find("\n", index2 + 1)
    if index2 == -1:
        inc_dirs = stderr[index1 + 1:]
    else:
        inc_dirs = stderr[index1 + 1:index2].strip()

    return [
        str(repository_ctx.path(_cxx_inc_convert(p)))
        for p in inc_dirs.split("\n")
    ]

def get_cxx_inc_directories(repository_ctx, cc):
    """Compute the list of default C and C++ include directories.

    Args:
      repository_ctx: The repository context.
      cc: The path to the C++ compiler.

    Returns:
      A list of default C and C++ include directories.
    """

    # For some reason `clang -xc` sometimes returns include paths that are
    # different from the ones from `clang -xc++`. (Symlink and a dir)
    # So we run the compiler with both `-xc` and `-xc++` and merge resulting lists
    includes_cpp = _get_cxx_inc_directories_impl(repository_ctx, cc, True)
    includes_c = _get_cxx_inc_directories_impl(repository_ctx, cc, False)

    includes_cpp_set = depset(includes_cpp)
    return includes_cpp + [
        inc
        for inc in includes_c
        if inc not in includes_cpp_set.to_list()
    ]

def _mkl_path(sycl_config):
    return sycl_config.sycl_basekit_path + "/mkl/" + sycl_config.sycl_basekit_version_number

def _sycl_header_path(repository_ctx, sycl_config, bash_bin):
    sycl_header_path = sycl_config.sycl_basekit_path + "/compiler/" + sycl_config.sycl_basekit_version_number
    include_dir = sycl_header_path + "/include"
    if not files_exist(repository_ctx, [include_dir], bash_bin)[0]:
        sycl_header_path = sycl_header_path + "/linux"
        include_dir = sycl_header_path + "/include"
        if not files_exist(repository_ctx, [include_dir], bash_bin)[0]:
            auto_configure_fail("Cannot find sycl headers in {}".format(include_dir))
    return sycl_header_path

def _sycl_include_path(repository_ctx, sycl_config, bash_bin):
    """Generates cxx_builtin_include_directory entries for sycl include directories.

    Args:
      repository_ctx: The repository context.
      sycl_config: The sycl config struct.
      bash_bin: The path to the bash binary.
    Returns:
      A list of include directories.
    """
    inc_dirs = []

    inc_dirs.append(_mkl_path(sycl_config) + "/include")
    inc_dirs.append(_sycl_header_path(repository_ctx, sycl_config, bash_bin) + "/include")
    inc_dirs.append(_sycl_header_path(repository_ctx, sycl_config, bash_bin) + "/include/sycl")

    return inc_dirs

def find_cc(repository_ctx):
    """Find the C++ compiler.

    Args:
      repository_ctx: The repository context.

    Returns:
      The path to the C++ compiler.
    """

    # Return a dummy value for GCC detection here to avoid error
    target_cc_name = "gcc"
    cc_path_envvar = _GCC_HOST_COMPILER_PATH
    cc_name = target_cc_name

    cc_name_from_env = get_host_environ(repository_ctx, cc_path_envvar)
    if cc_name_from_env:
        cc_name = cc_name_from_env
    if cc_name.startswith("/"):
        # Absolute path, maybe we should make this supported by our which function.
        return cc_name
    cc = which(repository_ctx, cc_name)
    if cc == None:
        fail(("Cannot find {}, either correct your path or set the {}" +
              " environment variable").format(target_cc_name, cc_path_envvar))
    return cc

def find_sycl_root(repository_ctx, sycl_config):
    sycl_name = str(repository_ctx.path(sycl_config.sycl_toolkit_path.strip()).realpath)
    if sycl_name.startswith("/"):
        return sycl_name
    fail("Cannot find SYCL compiler, please correct your path")

def find_sycl_include_path(repository_ctx, sycl_config):
    """Find the include paths for the SYCL compiler.

    Args:
      repository_ctx: The repository context.
      sycl_config: The sycl config struct.

    Returns:
      A list of include directories.
    """
    base_path = find_sycl_root(repository_ctx, sycl_config)
    bin_path = repository_ctx.path(base_path + "/" + "bin" + "/" + "icpx")
    icpx_extra = ""
    if not bin_path.exists:
        bin_path = repository_ctx.path(base_path + "/" + "bin" + "/" + "clang")
        if not bin_path.exists:
            fail("Cannot find SYCL compiler, please correct your path")
    else:
        icpx_extra = "-fsycl"
    gcc_path = repository_ctx.which("gcc")
    gcc_install_dir = repository_ctx.execute([gcc_path, "-print-libgcc-file-name"])
    gcc_install_dir_opt = "--gcc-install-dir=" + str(repository_ctx.path(gcc_install_dir.stdout.strip()).dirname)
    cmd_out = repository_ctx.execute([bin_path, icpx_extra, gcc_install_dir_opt, "-xc++", "-E", "-v", "/dev/null", "-o", "/dev/null"])
    outlist = cmd_out.stderr.split("\n")
    include_dirs = []
    for l in outlist:
        if l.startswith(" ") and l.strip().startswith("/") and str(repository_ctx.path(l.strip()).realpath) not in include_dirs:
            include_dirs.append(str(repository_ctx.path(l.strip()).realpath))
    return include_dirs

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

    # TODO: Don't hard code?
    bash_bin = "/usr/bin/bash"
    sycl_config = struct(
        sycl_basekit_path = "/opt/intel/oneapi",
        sycl_basekit_version_number = "2025.0",
        sycl_toolkit_path = "/opt/intel/oneapi/compiler/2025.0",
        sycl_version_number = "80000",
    )

    cc = find_cc(repository_ctx)
    host_compiler_includes = get_cxx_inc_directories(repository_ctx, cc)
    sycl_internal_inc_dirs = find_sycl_include_path(repository_ctx = repository_ctx, sycl_config = sycl_config)
    cxx_builtin_includes_list = sycl_internal_inc_dirs + _sycl_include_path(repository_ctx, sycl_config, bash_bin) + host_compiler_includes

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
            "%{cxx_builtin_include_directories}": to_list_of_strings(cxx_builtin_includes_list),
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
