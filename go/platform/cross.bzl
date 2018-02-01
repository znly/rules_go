load(
    "@io_bazel_rules_go//go/platform:list.bzl",
    "GOOS",
    "GOARCH",
)
load(
    "@io_bazel_rules_go//go/platform:apple.bzl",
    "APPLE_GOOS",
    "APPLE_GOARCH",
)

_GOOS = {
    "//conditions:default": "auto",
}
_GOOS.update(APPLE_GOOS)

_GOARCH = {
    "//conditions:default": "auto",
}
_GOARCH.update(APPLE_GOARCH)

GOOS_CROSS = select(_GOOS)
GOARCH_CROSS = select(_GOARCH)
