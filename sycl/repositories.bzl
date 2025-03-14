"""Module docstring for repository definitions."""

def _impl(repository_ctx):
    content = "Hello from the mocked repository!"
    print("The name of this repository is", repository_ctx.name)
    repository_ctx.file("hello.txt", content)
    repository_ctx.file(
        "BUILD.bazel",
        'exports_files(["hello.txt"], visibility = ["//visibility:public"])\n',
    )
    print("hello", repository_ctx.attr.sha256)

sycl_repository = repository_rule(
    implementation = _impl,
    attrs = {
        "url": attr.string(mandatory = True),
        "sha256": attr.string(mandatory = True),
    },
)
