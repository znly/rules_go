package(
    default_visibility = ["//visibility:public"],
)

load("//go:def.bzl", "go_binary")

go_binary(
    name = "bin",
    srcs = ["bin.go"],
    deps = [
        "//examples/lib:go_default_library",
        "//examples/vendor/github_com/user/vendored:go_default_library",
    ],
)
