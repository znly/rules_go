# Copyright 2014 The Bazel Authors. All rights reserved.
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
    "@io_bazel_rules_go//go/private:common.bzl",
    "env_execute",
    "executable_path",
)
load(
    "@io_bazel_rules_go//go/platform:list.bzl",
    "generate_toolchain_names",
)

def _go_host_sdk_impl(ctx):
    goroot = _detect_host_sdk(ctx)
    platform = _detect_sdk_platform(ctx, goroot)
    _sdk_build_file(ctx, platform)
    _local_sdk(ctx, goroot)

_go_host_sdk = repository_rule(
    _go_host_sdk_impl,
    environ = ["GOROOT"],
)

def go_host_sdk(name, **kwargs):
    _go_host_sdk(name = name, **kwargs)
    _register_toolchains(name)

def _go_download_sdk_impl(ctx):
    sdks = ctx.attr.sdks
    if not ctx.attr.goos and not ctx.attr.goarch:
        platform = _detect_host_platform(ctx)
    else:
        platform = ctx.attr.goos + "_" + ctx.attr.goarch
    if platform not in sdks:
        fail("Unsupported platform {}".format(platform))
    filename, sha256 = ctx.attr.sdks[platform]
    _sdk_build_file(ctx, platform)
    _remote_sdk(ctx, [url.format(filename) for url in ctx.attr.urls], ctx.attr.strip_prefix, sha256)

_go_download_sdk = repository_rule(
    _go_download_sdk_impl,
    attrs = {
        "goos": attr.string(),
        "goarch": attr.string(),
        "sdks": attr.string_list_dict(),
        "urls": attr.string_list(default = ["https://dl.google.com/go/{}"]),
        "strip_prefix": attr.string(default = "go"),
    },
)

def go_download_sdk(name, **kwargs):
    _go_download_sdk(name = name, **kwargs)
    _register_toolchains(name)

def _go_local_sdk_impl(ctx):
    goroot = ctx.attr.path
    platform = _detect_sdk_platform(ctx, goroot)
    _sdk_build_file(ctx, platform)
    _local_sdk(ctx, goroot)

_go_local_sdk = repository_rule(
    _go_local_sdk_impl,
    attrs = {
        "path": attr.string(),
    },
)

def go_local_sdk(name, **kwargs):
    _go_local_sdk(name = name, **kwargs)
    _register_toolchains(name)

def _go_wrap_sdk_impl(ctx):
    goroot = str(ctx.path(ctx.attr.root_file).dirname)
    platform = _detect_sdk_platform(ctx, goroot)
    _sdk_build_file(ctx, platform)
    _local_sdk(ctx, goroot)

_go_wrap_sdk = repository_rule(
    _go_wrap_sdk_impl,
    attrs = {
        "root_file": attr.label(
            mandatory = True,
            doc = "A file in the SDK root direcotry. Used to determine GOROOT.",
        ),
    },
)

def go_wrap_sdk(name, **kwargs):
    _go_wrap_sdk(name = name, **kwargs)
    _register_toolchains(name)

def _register_toolchains(repo):
    labels = [
        "@{}//:{}".format(repo, name)
        for name in generate_toolchain_names()
    ]
    native.register_toolchains(*labels)

def _remote_sdk(ctx, urls, strip_prefix, sha256):
    # TODO(bazelbuild/bazel#7055): download_and_extract fails to extract
    # archives containing files with non-ASCII names. Go 1.12b1 has a test
    # file like this. Remove this workaround when the bug is fixed.
    if len(urls) == 0:
        fail("no urls specified")
    if urls[0].endswith(".tar.gz"):
        if strip_prefix != "go":
            fail("strip_prefix not supported")
        ctx.download(
            url = urls,
            sha256 = sha256,
            output = "go_sdk.tar.gz",
        )
        res = ctx.execute(["tar", "-xf", "go_sdk.tar.gz", "--strip-components=1"])
        if res.return_code:
            fail("error extracting Go SDK:\n" + res.stdout + res.stderr)
        ctx.execute(["rm", "go_sdk.tar.gz"])
    else:
        ctx.download_and_extract(
            url = urls,
            stripPrefix = strip_prefix,
            sha256 = sha256,
        )
    _patch_nix(ctx)

_NIX_DYLD_TPL = """\
#!/bin/sh
exec {dyld} {binary} ${{@}}
"""

def _patch_nix(ctx):
    """
    Generates wrappers for the Go SDK binaries to use the correct interpreter
    on Nix/NixOS.
    """
    # Are we on Nix/NixOS? Check via $NIX_CC
    nix_cc = ctx.os.environ.get("NIX_CC", None)
    if not nix_cc:
        return
    # Get the dyld
    res = ctx.execute(["cat", "%s/nix-support/dynamic-linker" % nix_cc])
    if res.return_code:
        fail("error reading the dynamic linker:\n" + res.stdout + res.stderr)
    dyld = res.stdout.rstrip()
    # Generate the wrappers. Unfortunately we can't use patchelf to do that
    # until patchelf 0.10 is in NixOS. So manually invoke the dyld via wrappers
    # instead.
    # See https://github.com/NixOS/patchelf/issues/66
    for binary in ctx.path("bin").readdir():
        # Does the binary needs a wrapper?
        if ctx.execute(["patchelf", "--print-interpreter", binary]).return_code:
            continue
        orig = "%s.1" % binary
        ctx.execute(["mv", binary, orig])
        ctx.file(binary, _NIX_DYLD_TPL.format(
            dyld = dyld,
            binary = orig,
        ), executable = True)

def _local_sdk(ctx, path):
    for entry in ["src", "pkg", "bin"]:
        ctx.symlink(path + "/" + entry, entry)

def _sdk_build_file(ctx, platform):
    ctx.file("ROOT")
    goos, _, goarch = platform.partition("_")
    ctx.template(
        "BUILD.bazel",
        Label("@io_bazel_rules_go//go/private:BUILD.sdk.bazel"),
        executable = False,
        substitutions = {
            "{goos}": goos,
            "{goarch}": goarch,
            "{exe}": ".exe" if goos == "windows" else "",
        },
    )

def _detect_host_platform(ctx):
    if ctx.os.name == "linux":
        host = "linux_amd64"
        res = ctx.execute(["uname", "-p"])
        if res.return_code == 0:
            uname = res.stdout.strip()
            if uname == "s390x":
                host = "linux_s390x"
            elif uname == "i686":
                host = "linux_386"

        # uname -p is not working on Aarch64 boards
        # or for ppc64le on some distros
        res = ctx.execute(["uname", "-m"])
        if res.return_code == 0:
            uname = res.stdout.strip()
            if uname == "aarch64":
                host = "linux_arm64"
            elif uname == "armv6l":
                host = "linux_arm"
            elif uname == "armv7l":
                host = "linux_arm"
            elif uname == "ppc64le":
                host = "linux_ppc64le"

        # Default to amd64 when uname doesn't return a known value.

    elif ctx.os.name == "mac os x":
        host = "darwin_amd64"
    elif ctx.os.name.startswith("windows"):
        host = "windows_amd64"
    elif ctx.os.name == "freebsd":
        host = "freebsd_amd64"
    else:
        fail("Unsupported operating system: " + ctx.os.name)

    return host

def _detect_host_sdk(ctx):
    root = "@invalid@"
    if "GOROOT" in ctx.os.environ:
        return ctx.os.environ["GOROOT"]
    res = ctx.execute([executable_path(ctx, "go"), "env", "GOROOT"])
    if res.return_code:
        fail("Could not detect host go version")
    root = res.stdout.strip()
    if not root:
        fail("host go version failed to report it's GOROOT")
    return root

def _detect_sdk_platform(ctx, goroot):
    res = ctx.execute(["ls", goroot + "/pkg/tool"])
    if res.return_code != 0:
        fail("Could not detect SDK platform")
    for f in res.stdout.strip().split("\n"):
        if f.find("_") >= 0:
            return f
    fail("Could not detect SDK platform")
