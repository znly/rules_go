package(
    default_visibility = ["//visibility:public"],
)

load("//go:def.bzl", "go_library", "go_test")

go_library(
    name = "go_default_library",
    srcs = [
        "lib.go",
    ],
)

go_test(
    name = "lib_test",
    srcs = [
        "lib_test.go",
    ],
    library = ":go_default_library",
)
