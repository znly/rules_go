load("@io_bazel_rules_go//go:def.bzl", "go_library")

go_library(
    name = "go_default_library",
    srcs = [
        "prefix.go",
        "util.go",
    ],
    visibility = ["//visibility:public"],
    deps = ["@io_bazel_buildifier//core:go_default_library"],
)
