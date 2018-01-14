# Copyright 2016 The Bazel Go Rules Authors. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

load(
    "@io_bazel_rules_go//go/private:providers.bzl",
    "GoStdLib",
)
load("@io_bazel_rules_go//go/private:context.bzl",
    "go_context",
)
load(
    "@io_bazel_rules_go//go/private:rules/rule.bzl",
    "go_rule",
)

_STDLIB_BUILD = """
load("@io_bazel_rules_go//go/private:rules/stdlib.bzl", "stdlib")

stdlib(
    name = "{name}",
    goos = "{goos}",
    goarch = "{goarch}",
    race = {race},
    pure = {pure},
    visibility = ["//visibility:public"],
)
"""

def _apple_min_version(platform, version):
  return "-m" + platform.name_in_plist.lower() + "-version-min=" + version

def _apple_update_env(ctx, env):
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
  env["SDKROOT"] = "$(/usr/bin/xcrun -sdk {} --show-sdk-path)".format(
      # ctx.attr._xcrunwrapper.files_to_run.executable.path,
      platform.name_in_plist.lower())
  if platform in [apple_common.platform.ios_device, apple_common.platform.ios_simulator]:
    min_version = _apple_min_version(platform, "6.1")
    env.update({
      "CGO_CFLAGS": "{} {}".format(env.get("CGO_CFLAGS", ""), min_version),
      "CGO_CPPFLAGS": "{} {}".format(env.get("CGO_CPPFLAGS", ""), min_version),
      "CGO_LDFLAGS": "{} {}".format(env.get("CGO_LDFLAGS", ""), min_version),
    })
  xcode_config = ctx.attr._xcode_config[apple_common.XcodeVersionConfig]
  env.update(apple_common.target_apple_env(xcode_config, platform))

def _stdlib_impl(ctx):
  go = go_context(ctx)
  pkg = ctx.actions.declare_directory("pkg")
  root_file = ctx.actions.declare_file("ROOT")
  files = [root_file, go.go, pkg]
  args = go.args(go)
  args.add(["-out", root_file.dirname])
  if ctx.attr.race:
    args.add("-race")
  ctx.actions.write(root_file, "")
  go.actions.run(
      inputs = go.sdk_files + go.sdk_tools + [go.package_list, root_file],
      outputs = [pkg],
      mnemonic = "GoStdlib",
      executable = ctx.executable._stdlib_builder,
      arguments = [args],
  )

  return [
      DefaultInfo(
          files = depset(files),
      ),
      GoStdLib(
          root_file = root_file,
          mode = go.mode,
          libs = [pkg],
          headers = [pkg],
          files = files,
      ),
  ]

stdlib = go_rule(
    _stdlib_impl,
    bootstrap = True,
    attrs = {
        "goos": attr.string(mandatory = True),
        "goarch": attr.string(mandatory = True),
        "race": attr.bool(mandatory = True),
        "pure": attr.bool(mandatory = True),
        "_stdlib_builder": attr.label(
            executable = True,
            cfg = "host",
            default = Label("@io_bazel_rules_go//go/tools/builders:stdlib"),
        ),
        "_xcode_config": attr.label(default=Label("@bazel_tools//tools/osx:current_xcode_config")),
        "_xcrunwrapper": attr.label(
            executable=True,
            cfg="host",
            default=Label("@bazel_tools//tools/objc:xcrunwrapper"),
        ),
    },
    fragments = ["cpp", "apple"],
)

def _go_stdlib_impl(ctx):
    ctx.file("BUILD.bazel", _STDLIB_BUILD.format(
        name = ctx.name,
        goos = ctx.attr.goos,
        goarch = ctx.attr.goarch,
        race = ctx.attr.race,
        pure = ctx.attr.pure,
    ))

go_stdlib = repository_rule(
    implementation = _go_stdlib_impl,
    attrs = {
        "goos": attr.string(mandatory = True),
        "goarch": attr.string(mandatory = True),
        "race": attr.bool(mandatory = True),
        "pure": attr.bool(mandatory = True),
    },
)
"""See /go/toolchains.rst#go-sdk for full documentation."""
