""" IDK """

load(
    "//sycl:common.bzl",
    "err_out",
    "files_exist",
    "get_host_environ",
    "raw_exec",
    "read_dir",
    "realpath",
    "which",
)

_GCC_HOST_COMPILER_PATH = "GCC_HOST_COMPILER_PATH"
_GCC_HOST_COMPILER_PREFIX = "GCC_HOST_COMPILER_PREFIX"
_INC_DIR_MARKER_BEGIN = "#include <...>"

def _is_clang(repository_ctx, cc):
    return "clang" in repository_ctx.execute([cc, "-v"]).stderr

def _is_gcc(repository_ctx, cc):
    # GCC's version output uses the basename of argv[0] as the program name:
    # https://gcc.gnu.org/git/?p=gcc.git;a=blob;f=gcc/gcc.cc;h=158461167951c1b9540322fb19be6a89d6da07fc;hb=HEAD#l8728
    cc_stdout = repository_ctx.execute([cc, "--version"]).stdout
    return cc_stdout.startswith("gcc ") or cc_stdout.startswith("gcc-")

def _get_compiler_name(repository_ctx, cc):
    if _is_clang(repository_ctx, cc):
        return "clang"
    if _is_gcc(repository_ctx, cc):
        return "gcc"
    return "compiler"

def escape_string(arg):
    """Escape percent sign (%) in the string so it can appear in the Crosstool."""
    if arg != None:
        return str(arg).replace("%", "%%")
    else:
        return None

def auto_configure_warning(msg):
    """Output warning message during auto configuration."""
    yellow = "\033[1;33m"
    no_color = "\033[0m"

    # buildifier: disable=print
    print("\n%sAuto-Configuration Warning:%s %s\n" % (yellow, no_color, msg))

def get_env_var(repository_ctx, name, default = None, enable_warning = True):
    """Find an environment variable in system path. Doesn't %-escape the value!

    Args:
      repository_ctx: The repository context.
      name: Name of the environment variable.
      default: Default value to be used when such environment variable is not present.
      enable_warning: Show warning if the variable is not present.
    Returns:
      value of the environment variable or default.
    """

    if name in repository_ctx.os.environ:
        return repository_ctx.os.environ[name]
    if default != None:
        if enable_warning:
            auto_configure_warning("'%s' environment variable is not set, using '%s' as default" % (name, default))
        return default
    auto_configure_fail("'%s' environment variable is not set" % name)
    return None

def _norm_path(path):
    """Returns a path with '/' and remove the trailing slash."""
    path = path.replace("\\", "/")
    if path[-1] == "/":
        path = path[:-1]
    return path

def make_copy_files_rule(repository_ctx, name, srcs, outs):
    """Returns a rule to copy a set of files."""
    cmds = []

    # Copy files.
    for src, out in zip(srcs, outs):
        cmds.append('cp -f "%s" "$(location %s)"' % (src, out))
    outs = [('        "%s",' % out) for out in outs]
    return """genrule(
    name = "%s",
    outs = [
%s
    ],
    cmd = \"""%s \""",
)""" % (name, "\n".join(outs), " && \\\n".join(cmds))

def make_copy_dir_rule(repository_ctx, name, src_dir, out_dir, exceptions = None):
    """Returns a rule to recursively copy a directory.
    If exceptions is not None, it must be a list of files or directories in
    'src_dir'; these will be excluded from copying.
    """
    src_dir = _norm_path(src_dir)
    out_dir = _norm_path(out_dir)
    outs = read_dir(repository_ctx, src_dir)
    post_cmd = ""
    if exceptions != None:
        outs = [x for x in outs if not any([
            x.startswith(src_dir + "/" + y)
            for y in exceptions
        ])]
    outs = [('        "%s",' % out.replace(src_dir, out_dir)) for out in outs]

    # '@D' already contains the relative path for a single file, see
    # http://docs.bazel.build/versions/master/be/make-variables.html#predefined_genrule_variables
    out_dir = "$(@D)/%s" % out_dir if len(outs) > 1 else "$(@D)"
    if exceptions != None:
        for x in exceptions:
            post_cmd += " ; rm -fR " + out_dir + "/" + x
    return """genrule(
    name = "%s",
    outs = [
%s
    ],
    cmd = \"""cp -rLf "%s/." "%s/" %s\""",
)""" % (name, "\n".join(outs), src_dir, out_dir, post_cmd)

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

def _sycl_lib_paths(repository_ctx, lib, basedir, version = ""):
    file_name = _lib_name(lib, version = version, static = False)
    return [
        repository_ctx.path("%s/lib/%s" % (basedir, file_name)),
        repository_ctx.path("%s/lib/intel64/%s" % (basedir, file_name)),
    ]

def _batch_files_exist(repository_ctx, libs_paths, bash_bin):
    all_paths = []
    for _, lib_paths in libs_paths:
        for lib_path in lib_paths:
            all_paths.append(lib_path)
    return files_exist(repository_ctx, all_paths, bash_bin)

def _select_sycl_lib_paths(repository_ctx, libs_paths, bash_bin):
    test_results = _batch_files_exist(repository_ctx, libs_paths, bash_bin)

    libs = {}
    i = 0
    for name, lib_paths in libs_paths:
        print(name, lib_paths)
        selected_path = None
        for path in lib_paths:
            if test_results[i] and selected_path == None:
                # For each lib select the first path that exists.
                selected_path = path
            i = i + 1
        if selected_path == None:
            auto_configure_fail("Cannot find sycl library %s in %s" % (name, path))

        # sycl_libs["sycl"].file_name = "libsycl.so.8"
        # if selected_path.basename == "libsycl.so":
        #     print("hit")
        #     libs[name] = struct(file_name = "libsycl.so.8", path = realpath(repository_ctx, selected_path, bash_bin))
        # else:
        libs[name] = struct(file_name = selected_path.basename, path = realpath(repository_ctx, selected_path, bash_bin))

    return libs

def _lib_name(lib, version = "", static = False):
    """Constructs the platform-specific name of a library.

    Args:
      lib: The name of the library, such as "mkl"
      version: The version of the library.
      static: True the library is static or False if it is a shared object.
    Returns:
      The platform-specific name of the library.
    """
    if static:
        return "lib%s.a" % lib
    else:
        if version:
            version = ".%s" % version
        return "lib%s.so%s" % (lib, version)

# /usr/bin/ld: warning: libsvml.so, needed by bazel-out/k8-fastbuild/bin/_solib_k8/_U_A_A+sycl_Uconfigure_Uextension+local_Uconfig_Usycl_S_Ssycl_Csycl___Uexternal_S+sycl_Uconfigure_Uextension+local_Uconfig_Usycl_Ssycl_Ssycl_Slib/libOpenCL.so, not found (try using -rpath or -rpath-link)
# /usr/bin/ld: warning: libirng.so, needed by bazel-out/k8-fastbuild/bin/_solib_k8/_U_A_A+sycl_Uconfigure_Uextension+local_Uconfig_Usycl_S_Ssycl_Csycl___Uexternal_S+sycl_Uconfigure_Uextension+local_Uconfig_Usycl_Ssycl_Ssycl_Slib/libOpenCL.so, not found (try using -rpath or -rpath-link)
# /usr/bin/ld: warning: libimf.so, needed by bazel-out/k8-fastbuild/bin/_solib_k8/_U_A_A+sycl_Uconfigure_Uextension+local_Uconfig_Usycl_S_Ssycl_Csycl___Uexternal_S+sycl_Uconfigure_Uextension+local_Uconfig_Usycl_Ssycl_Ssycl_Slib/libOpenCL.so, not found (try using -rpath or -rpath-link)
# /usr/bin/ld: warning: libintlc.so.5, needed by bazel-out/k8-fastbuild/bin/_solib_k8/_U_A_A+sycl_Uconfigure_Uextension+local_Uconfig_Usycl_S_Ssycl_Csycl___Uexternal_S+sycl_Uconfigure_Uextension+local_Uconfig_Usycl_Ssycl_Ssycl_Slib/libOpenCL.so, not found (try using -rpath or -rpath-link)
# /usr/bin/ld: warning: libumf.so.0, needed by /opt/intel/oneapi/compiler/2025.0/bin/compiler/../../lib/libur_adapter_opencl.so, not found (try using -rpath or -rpath-link)

def _find_libs(repository_ctx, sycl_config, bash_bin):
    """Finds the SYCL libraries on the system.

    Args:
      repository_ctx: The repository context.
      sycl_config: The SYCL config as returned by _get_sycl_config
      bash_bin: the path to the bash interpreter
    Returns:
      Map of library names to structs of filename and path
    """
    mkl_path = _mkl_path(sycl_config)
    sycl_path = _sycl_header_path(repository_ctx, sycl_config, bash_bin)
    print(mkl_path)
    print(sycl_path)  # /opt/intel/oneapi
    print(sycl_config.sycl_basekit_path + "/" + sycl_config.sycl_basekit_version_number + "/lib")

    oneapi_version_path = sycl_config.sycl_basekit_path + "/" + sycl_config.sycl_basekit_version_number

    # oneapi/2025.0/lib/libumf.so
    libs_paths = [
        (name, _sycl_lib_paths(repository_ctx, name, path, version))
        for name, path, version in [
            ("sycl", sycl_path, "8"),
            ("OpenCL", sycl_path, "1"),
            ("svml", oneapi_version_path, ""),
            ("irng", oneapi_version_path, ""),
            ("imf", oneapi_version_path, ""),
            ("intlc", oneapi_version_path, "5"),
            ("umf", oneapi_version_path, "0"),
            ("hwloc", oneapi_version_path, "15"),
            # ur_loader
            # ur_adapter_opencl
            ("ur_loader", oneapi_version_path, "0"),
            ("ur_adapter_opencl", oneapi_version_path, "0"),
            ("mkl_intel_ilp64", mkl_path, ""),
            ("mkl_sequential", mkl_path, ""),
            ("mkl_core", mkl_path, ""),
        ]
    ]
    if sycl_config.sycl_basekit_version_number < "2024":
        libs_paths.append(("mkl_sycl", _sycl_lib_paths(repository_ctx, "mkl_sycl", mkl_path)))
    else:
        libs_paths.append(("mkl_sycl_blas", _sycl_lib_paths(repository_ctx, "mkl_sycl_blas", mkl_path)))
        libs_paths.append(("mkl_sycl_lapack", _sycl_lib_paths(repository_ctx, "mkl_sycl_lapack", mkl_path)))
        libs_paths.append(("mkl_sycl_sparse", _sycl_lib_paths(repository_ctx, "mkl_sycl_sparse", mkl_path)))
        libs_paths.append(("mkl_sycl_dft", _sycl_lib_paths(repository_ctx, "mkl_sycl_dft", mkl_path)))
        libs_paths.append(("mkl_sycl_vm", _sycl_lib_paths(repository_ctx, "mkl_sycl_vm", mkl_path)))
        libs_paths.append(("mkl_sycl_rng", _sycl_lib_paths(repository_ctx, "mkl_sycl_rng", mkl_path)))
        libs_paths.append(("mkl_sycl_stats", _sycl_lib_paths(repository_ctx, "mkl_sycl_stats", mkl_path)))
        libs_paths.append(("mkl_sycl_data_fitting", _sycl_lib_paths(repository_ctx, "mkl_sycl_data_fitting", mkl_path)))
    return _select_sycl_lib_paths(repository_ctx, libs_paths, bash_bin)

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
        "@rules_sycl//sycl/sycl:BUILD.tpl",
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

    # Copy header and library files to execroot.
    copy_rules = [
        make_copy_dir_rule(
            repository_ctx,
            name = "sycl-include",
            src_dir = _sycl_header_path(repository_ctx, sycl_config, bash_bin) + "/include",
            out_dir = "sycl/include",
        ),
    ]
    copy_rules.append(make_copy_dir_rule(
        repository_ctx,
        name = "mkl-include",
        src_dir = _mkl_path(sycl_config) + "/include",
        out_dir = "sycl/include",
    ))

    sycl_libs = _find_libs(repository_ctx, sycl_config, bash_bin)
    print("CEMLYN: ", sycl_libs)
    sycl_lib_srcs = []
    sycl_lib_outs = []
    for lib in sycl_libs.values():
        sycl_lib_srcs.append(lib.path)
        sycl_lib_outs.append("sycl/lib/" + lib.file_name)
    copy_rules.append(make_copy_files_rule(
        repository_ctx,
        name = "sycl-lib",
        srcs = sycl_lib_srcs,
        outs = sycl_lib_outs,
    ))

    if sycl_config.sycl_basekit_version_number < "2024":
        mkl_sycl_libs = '"{}"'.format(
            "sycl/lib/" + sycl_libs["mkl_sycl"].file_name,
        )
    else:
        mkl_sycl_libs = '"{}",\n"{}",\n"{}",\n"{}",\n"{}",\n"{}",\n"{}",\n"{}"'.format(
            "sycl/lib/" + sycl_libs["mkl_sycl_blas"].file_name,
            "sycl/lib/" + sycl_libs["mkl_sycl_lapack"].file_name,
            "sycl/lib/" + sycl_libs["mkl_sycl_sparse"].file_name,
            "sycl/lib/" + sycl_libs["mkl_sycl_dft"].file_name,
            "sycl/lib/" + sycl_libs["mkl_sycl_vm"].file_name,
            "sycl/lib/" + sycl_libs["mkl_sycl_rng"].file_name,
            "sycl/lib/" + sycl_libs["mkl_sycl_stats"].file_name,
            "sycl/lib/" + sycl_libs["mkl_sycl_data_fitting"].file_name,
        )
    core_sycl_libs = to_list_of_strings([
        "sycl/lib/" + sycl_libs["sycl"].file_name,  # .split(".so")[0],
        "sycl/lib/" + sycl_libs["OpenCL"].file_name,  # .split(".so")[0],
        "sycl/lib/" + sycl_libs["svml"].file_name,  # .split(".so")[0],
        "sycl/lib/" + sycl_libs["irng"].file_name,  # .split(".so")[0],
        "sycl/lib/" + sycl_libs["imf"].file_name,  # .split(".so")[0],
        "sycl/lib/" + sycl_libs["intlc"].file_name,  # .split(".so")[0],
        "sycl/lib/" + sycl_libs["umf"].file_name,  # .split(".so")[0],
        "sycl/lib/" + sycl_libs["hwloc"].file_name,  # .split(".so")[0],
        "sycl/lib/" + sycl_libs["ur_loader"].file_name,  # .split(".so")[0],
        "sycl/lib/" + sycl_libs["ur_adapter_opencl"].file_name,  # .split(".so")[0],
    ])
    repository_dict = {
        "%{mkl_intel_ilp64_lib}": sycl_libs["mkl_intel_ilp64"].file_name,
        "%{mkl_sequential_lib}": sycl_libs["mkl_sequential"].file_name,
        "%{mkl_core_lib}": sycl_libs["mkl_core"].file_name,
        "%{mkl_sycl_libs}": mkl_sycl_libs,
        "%{core_sycl_libs}": core_sycl_libs,
        "%{copy_rules}": "\n".join(copy_rules),
        "%{sycl_headers}": ('":mkl-include",\n":sycl-include",\n'),
    }

    # TODO: I don't like double folder sycl/sycl!
    repository_ctx.template(
        "sycl/BUILD",
        paths["@rules_sycl//sycl/sycl:BUILD.tpl"],
        repository_dict,
    )

    cc = find_cc(repository_ctx)
    host_compiler_includes = get_cxx_inc_directories(repository_ctx, cc)
    host_compiler_prefix = get_host_environ(repository_ctx, _GCC_HOST_COMPILER_PREFIX, "/usr/bin")
    sycl_internal_inc_dirs = find_sycl_include_path(repository_ctx = repository_ctx, sycl_config = sycl_config)
    cxx_builtin_includes_list = sycl_internal_inc_dirs + _sycl_include_path(repository_ctx, sycl_config, bash_bin) + host_compiler_includes

    sycl_toolchain_identifier = "k8"
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
            "%{compiler}": escape_string(get_env_var(
                repository_ctx,
                "BAZEL_COMPILER",
                _get_compiler_name(repository_ctx, cc),
                False,
            )),
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
            "%{target_cpu}": escape_string(get_env_var(
                repository_ctx,
                "BAZEL_TARGET_CPU",
                cpu_value,
                False,
            )),
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
            # Google did this, looks like gcc argument, might not be clang argument allowed
            # "%{extra_no_canonical_prefixes_flags}": to_list_of_strings(["-fno-canonical-system-headers"]),
            "%{extra_no_canonical_prefixes_flags}": to_list_of_strings([]),
            "%{host_compiler_path}": "/opt/intel/oneapi/compiler/2025.0/bin/icpx",
            "%{host_compiler_prefix}": host_compiler_prefix,
            # TODO: maybe name change it in build.tpl?
            "%{unfiltered_compile_flags}": to_list_of_strings([
                "-DTENSORFLOW_USE_SYCL=1",
                "-DMKL_ILP64",
                # "-fPIC",
            ]),
            "%{linker_bin_path}": escape_string("/usr/bin"),
            # "%{builtin_sysroot}": "",
        },
    )

sycl_autoconf = repository_rule(
    implementation = sycl_autoconf_impl,
    configure = True,
)
