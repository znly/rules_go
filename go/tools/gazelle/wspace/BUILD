load("@io_bazel_rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "go_default_library",
    srcs = [
        "finder.go",
        "load.go",
    ],
    visibility = ["//visibility:public"],
    deps = [
        "//go/tools/gazelle/rules:go_default_library",
        "//go/tools/gazelle/util:go_default_library",
        "@io_bazel_buildifier//core:go_default_library",
    ],
)

go_test(
    name = "go_default_test",
    srcs = ["finder_test.go"],
    library = ":go_default_library",
)
