def _apple_min_version(platform, version):
  return "-m" + platform.name_in_plist.lower() + "-version-min=" + version

def ensure_apple_options(ctx, env, tags, compiler_options, linker_options):
  system_name = ctx.fragments.cpp.target_gnu_system_name
  if "-apple-" not in system_name:
    return

  if system_name.endswith("-ios"):
      tags.append("ios")

  platforms = {}
  for cpu in ["armv7k"]:
    platforms[cpu + "-apple-watchos"] = apple_common.platform.watchos_device
  for cpu in ["armv7", "arm64"]:
    platforms[cpu + "-apple-ios"] = apple_common.platform.ios_device
    platforms[cpu + "-apple-tvos"] = apple_common.platform.tvos_device
  for cpu in ["i386", "x86_64"]:
    platforms[cpu + "-apple-ios"] = apple_common.platform.ios_simulator
    platforms[cpu + "-apple-macosx"] = apple_common.platform.macos
    platforms[cpu + "-apple-tvos"] = apple_common.platform.tvos_simulator
    platforms[cpu + "-apple-watchos"] = apple_common.platform.watchos_simulator
  platform = platforms.get(ctx.fragments.cpp.target_gnu_system_name)
  if platform == None:
    return
  if platform in [apple_common.platform.ios_device, apple_common.platform.ios_simulator]:
    min_version = _apple_min_version(platform, "6.1")
    compiler_options.append(min_version)
    linker_options.append(min_version)
  xcode_config = ctx.attr._xcode_config[apple_common.XcodeVersionConfig]
  env.update(apple_common.target_apple_env(xcode_config, platform))
