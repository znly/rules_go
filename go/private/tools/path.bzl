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
    "@io_bazel_rules_go//go/private:context.bzl",
    "go_context",
)
load(
    "@io_bazel_rules_go//go/private:providers.bzl",
    "GoArchive",
    "GoPath",
    "effective_importpath_pkgpath",
    "get_archive",
)
load(
    "@io_bazel_rules_go//go/private:common.bzl",
    "as_iterable",
    "as_list",
)
load(
    "@io_bazel_rules_go//go/private:rules/rule.bzl",
    "go_rule",
)
load(
    "@io_bazel_rules_go//go/private:rules/aspect.bzl",
    "go_archive_aspect",
)
load(
    "@io_bazel_rules_go//go/platform:list.bzl",
    "GOOS",
    "GOARCH",
)
load(
    "@io_bazel_rules_go//go/private:mode.bzl",
    "LINKMODE_NORMAL",
    "LINKMODES",
)

def _go_path_impl(ctx):
    # Gather all archives. Note that there may be multiple packages with the same
    # importpath (e.g., multiple vendored libraries, internal tests).
    go = go_context(ctx)
    direct_archives = []
    transitive_archives = []
    for dep in ctx.attr.deps:
        archive = get_archive(dep)
        direct_archives.append(archive.data)
        transitive_archives.append(archive.transitive)
    archives = depset(direct = direct_archives, transitive = transitive_archives)

    # Collect sources and data files from archives. Merge archives into packages.
    pkg_map = {}  # map from package path to structs
    pkg_prefix = "pkg/" + go.mode.goos + "_" + go.mode.goarch + "/"
    for archive in as_iterable(archives):
        importpath, pkgpath = effective_importpath_pkgpath(archive)
        if importpath == "":
            continue  # synthetic archive or inferred location
        out_prefix = "src/" + pkgpath
        pkg_out_prefix = pkg_prefix + pkgpath
        pkg = struct(
            importpath = importpath,
            dir = out_prefix,
            pkgdir = pkg_out_prefix,
            srcs = as_list(archive.orig_srcs),
            data = as_list(archive.data_files),
            file = archive.file,
        )
        if pkgpath in pkg_map:
            _merge_pkg(pkg_map[pkgpath], pkg)
        else:
            pkg_map[pkgpath] = pkg

    # Build a manifest file that includes all files to copy/link/zip.
    inputs = []
    manifest_entries = []
    manifest_entry_map = {}
    for pkg in pkg_map.values():
        for f in pkg.srcs:
            dst = pkg.dir + "/" + f.basename
            _add_manifest_entry(manifest_entries, manifest_entry_map, inputs, f, dst)
        if ctx.attr.include_pkg:
            manifest_entries.append(struct(
                src = pkg.file.path,
                dst = pkg.pkgdir + "." + pkg.file.extension,
            ))
            inputs.append(pkg.file)
    if ctx.attr.include_data:
        for pkg in pkg_map.values():
            for f in pkg.data:
                parts = f.path.split("/")
                if "testdata" in parts:
                    i = parts.index("testdata")
                    dst = pkg.dir + "/" + "/".join(parts[i:])
                else:
                    dst = pkg.dir + "/" + f.basename
                _add_manifest_entry(manifest_entries, manifest_entry_map, inputs, f, dst)
    for f in ctx.files.data:
        _add_manifest_entry(
            manifest_entries,
            manifest_entry_map,
            inputs,
            f,
            f.basename,
        )
    manifest_file = ctx.actions.declare_file(ctx.label.name + "~manifest")
    manifest_entries_json = [e.to_json() for e in manifest_entries]
    manifest_content = "[\n  " + ",\n  ".join(manifest_entries_json) + "\n]"
    ctx.actions.write(manifest_file, manifest_content)
    inputs.append(manifest_file)

    # Execute the builder
    if ctx.attr.mode == "archive":
        out = ctx.actions.declare_file(ctx.label.name + ".zip")
        out_path = out.path
        out_short_path = out.short_path
        outputs = [out]
        out_file = out
    elif ctx.attr.mode == "copy":
        out = ctx.actions.declare_directory(ctx.label.name)
        out_path = out.path
        out_short_path = out.short_path
        outputs = [out]
        out_file = out
    else:  # link
        # Declare individual outputs in link mode. Symlinks can't point outside
        # tree artifacts.
        outputs = [
            ctx.actions.declare_file(ctx.label.name + "/" + e.dst)
            for e in manifest_entries
        ]
        tag = ctx.actions.declare_file(ctx.label.name + "/.tag")
        ctx.actions.write(tag, "")
        out_path = tag.dirname
        out_short_path = tag.short_path.rpartition("/")[0]
        out_file = tag
    args = [
        "-manifest=" + manifest_file.path,
        "-out=" + out_path,
        "-mode=" + ctx.attr.mode,
    ]
    ctx.actions.run(
        outputs = outputs,
        inputs = inputs,
        mnemonic = "GoPath",
        executable = ctx.executable._go_path,
        arguments = args,
    )

    return [
        DefaultInfo(
            files = depset(outputs),
            runfiles = ctx.runfiles(files = outputs),
        ),
        GoPath(
            gopath = out_short_path,
            gopath_file = out_file,
            packages = pkg_map.values(),
        ),
    ]

go_path = go_rule(
    _go_path_impl,
    attrs = {
        "deps": attr.label_list(
            providers = [GoArchive],
            aspects = [go_archive_aspect],
        ),
        "data": attr.label_list(
            allow_files = True,
            cfg = "data",
        ),
        "mode": attr.string(
            default = "copy",
            values = [
                "archive",
                "copy",
                "link",
            ],
        ),
        "include_data": attr.bool(default = True),
        "include_pkg": attr.bool(default = False),
        "pure": attr.string(
            values = [
                "on",
                "off",
                "auto",
            ],
            default = "auto",
        ),
        "static": attr.string(
            values = [
                "on",
                "off",
                "auto",
            ],
            default = "auto",
        ),
        "race": attr.string(
            values = [
                "on",
                "off",
                "auto",
            ],
            default = "auto",
        ),
        "msan": attr.string(
            values = [
                "on",
                "off",
                "auto",
            ],
            default = "auto",
        ),
        "gc_goopts": attr.string_list(),
        "linkmode": attr.string(values = LINKMODES, default = LINKMODE_NORMAL),
        "_go_path": attr.label(
            default = "@io_bazel_rules_go//go/tools/builders:go_path",
            executable = True,
            cfg = "host",
        ),
    },
)

def _merge_pkg(x, y):
    x_srcs = {f.path: None for f in x.srcs}
    x_data = {f.path: None for f in x.data}
    x.srcs.extend([f for f in y.srcs if f.path not in x_srcs])
    x.data.extend([f for f in y.data if f.path not in x_srcs])

def _add_manifest_entry(entries, entry_map, inputs, src, dst):
    if dst in entry_map:
        if entry_map[dst] != src.path:
            fail("{}: references multiple files ({} and {})".format(dst, entry_map[dst], src.path))
        return
    entries.append(struct(src = src.path, dst = dst))
    entry_map[dst] = src.path
    inputs.append(src)
