SELECT_GOOS = {
    "@io_bazel_rules_go//go/platform:ios_i386": "darwin",
    "@io_bazel_rules_go//go/platform:ios_x86_64": "darwin",
    "@io_bazel_rules_go//go/platform:ios_arm64": "darwin",
    "@io_bazel_rules_go//go/platform:ios_armv7": "darwin",
    "//conditions:default": "auto",
}

SELECT_GOARCH = {
    "@io_bazel_rules_go//go/platform:ios_i386": "386",
    "@io_bazel_rules_go//go/platform:ios_x86_64": "amd64",
    "@io_bazel_rules_go//go/platform:ios_arm64": "arm64",
    "@io_bazel_rules_go//go/platform:ios_armv7": "arm",
    "//conditions:default": "auto",
}

def declare_config_settings():
  for cpu in ["i386", "x86_64", "armv7", "arm64"]:
    native.config_setting(
      name = "ios_" + cpu,
      values = {"cpu": "ios_" + cpu},
      visibility = ["//visibility:public"],
    )
