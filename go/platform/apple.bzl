APPLE_GOOS = {
    "@io_bazel_rules_go//go/platform:ios_i386": "darwin",
    "@io_bazel_rules_go//go/platform:ios_x86_64": "darwin",
    "@io_bazel_rules_go//go/platform:ios_arm64": "darwin",
    "@io_bazel_rules_go//go/platform:ios_armv7": "darwin",
}

APPLE_GOARCH = {
    "@io_bazel_rules_go//go/platform:ios_i386": "386",
    "@io_bazel_rules_go//go/platform:ios_x86_64": "amd64",
    "@io_bazel_rules_go//go/platform:ios_arm64": "arm64",
    "@io_bazel_rules_go//go/platform:ios_armv7": "arm",
}

PLATFORMS = {
    'armv7-apple-ios': apple_common.platform.ios_device,
    'armv7-apple-tvos': apple_common.platform.tvos_device,

    'armv7k-apple-watchos': apple_common.platform.watchos_device,

    'arm64-apple-ios': apple_common.platform.ios_device,
    'arm64-apple-tvos': apple_common.platform.tvos_device,

    'i386-apple-ios': apple_common.platform.ios_simulator,
    'i386-apple-macosx': apple_common.platform.macos,
    'i386-apple-tvos': apple_common.platform.tvos_simulator,
    'i386-apple-watchos': apple_common.platform.watchos_simulator,

    'x86_64-apple-ios': apple_common.platform.ios_simulator,
    'x86_64-apple-macosx': apple_common.platform.macos,
    'x86_64-apple-tvos': apple_common.platform.ios_simulator,
    'x86_64-apple-watchos': apple_common.platform.watchos_simulator,
}

def apple_declare_config_settings():
    for cpu in ["i386", "x86_64", "armv7", "arm64"]:
        native.config_setting(
            name = "ios_" + cpu,
            values = {"cpu": "ios_" + cpu},
            visibility = ["//visibility:public"],
        )

def _apple_version_min(platform, version):
    return "-m" + platform.name_in_plist.lower() + "-version-min=" + version

def apple_ensure_options(ctx, env, tags, compiler_options, linker_options):
    system_name = ctx.fragments.cpp.target_gnu_system_name
    platform = PLATFORMS.get(system_name)
    if platform == None:
        return
    if system_name.endswith("-ios"):
        tags.append("ios") # needed for stdlib building
    if platform in [apple_common.platform.ios_device, apple_common.platform.ios_simulator]:
        min_version = _apple_version_min(platform, "6.1")
        compiler_options.append(min_version)
        linker_options.append(min_version)
    xcode_config = ctx.attr._xcode_config[apple_common.XcodeVersionConfig]
    env.update(apple_common.target_apple_env(xcode_config, platform))
