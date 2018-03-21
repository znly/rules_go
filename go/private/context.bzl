# Copyright 2017 The Bazel Authors. All rights reserved.
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
    "GoLibrary",
    "GoSource",
    "GoAspectProviders",
    "GoStdLib",
    "GoBuilders",
    "get_source",
)
load(
    "@io_bazel_rules_go//go/platform:list.bzl",
    "GOOS_GOARCH",
)
load(
    "@io_bazel_rules_go//go/private:mode.bzl",
    "get_mode",
    "mode_string",
)
load(
    "@io_bazel_rules_go//go/private:common.bzl",
    "paths",
    "structs",
    "goos_to_extension",
    "goos_to_shared_extension",
    "as_iterable",
)

GoContext = provider()

EXPLICIT_PATH = "explicit"

INFERRED_PATH = "inferred"

EXPORT_PATH = "export"

_COMPILER_OPTIONS_BLACKLIST = {
  "-fcolor-diagnostics": None,
  "-Wall": None,
  "-g0": None, # symbols are needed by Go, so keep them
}

_LINKER_OPTIONS_BLACKLIST = {
  "-Wl,--gc-sections": None
}

def _filter_options(options, blacklist):
  return [option for option in options if option not in blacklist]

def _child_name(go, path, ext, name):
  childname = mode_string(go.mode) + "/"
  childname += name if name else go._ctx.label.name
  if path:
    childname += "~/" + path
  if ext:
    childname += ext
  return childname

def _declare_file(go, path="", ext="", name = ""):
  return go.actions.declare_file(_child_name(go, path, ext, name))

def _declare_directory(go, path="", ext="", name = ""):
  return go.actions.declare_directory(_child_name(go, path, ext, name))

def _new_args(go):
  args = go.actions.args()
  if go.stdlib:
    root_file = go.stdlib.root_file
  else:
    root_file = go.package_list
  args.add([
      "-go", go.go,
      "-root_file", root_file,
      "-goos", go.mode.goos,
      "-goarch", go.mode.goarch,
      "-cgo=" + ("0" if go.mode.pure else "1"),
  ])
  if len(go.tags) > 0:
    args.add("-tags")
    args.add(go.tags, join_with = ",")
  if go.cgo_tools:
    args.add([
      "-compiler_path", go.cgo_tools.compiler_path,
      "-cc", go.cgo_tools.compiler_executable,
    ])
    args.add(go.cgo_tools.compiler_options, before_each = "-cpp_flag")
    args.add(go.cgo_tools.linker_options, before_each = "-ld_flag")
  return args

def _new_library(go, name=None, importpath=None, resolver=None, importable=True, testfilter=None, **kwargs):
  if not importpath:
    importpath = go.importpath
  importmap = getattr(go._ctx.attr, "importmap", "")
  if not importmap:
    importmap = importpath
  return GoLibrary(
      name = go._ctx.label.name if not name else name,
      label = go._ctx.label,
      importpath = importpath,
      importmap = importmap,
      pathtype = go.pathtype if importable else EXPORT_PATH,
      resolve = resolver,
      testfilter = testfilter,
      **kwargs
  )

def _merge_embed(source, embed):
  s = get_source(embed)
  source["srcs"] = s.srcs + source["srcs"]
  source["cover"] = source["cover"] + s.cover
  source["deps"] = source["deps"] + s.deps
  source["x_defs"].update(s.x_defs)
  source["gc_goopts"] = source["gc_goopts"] + s.gc_goopts
  source["runfiles"] = source["runfiles"].merge(s.runfiles)
  source["cgo_deps"] = source["cgo_deps"] + s.cgo_deps
  source["cgo_exports"] = source["cgo_exports"] + s.cgo_exports
  if s.cgo_archives:
    if source["cgo_archives"]:
      fail("multiple libraries with cgo_archives embedded")
    source["cgo_archives"] = s.cgo_archives

def _library_to_source(go, attr, library, coverage_instrumented):
  #TODO: stop collapsing a depset in this line...
  attr_srcs = [f for t in getattr(attr, "srcs", []) for f in as_iterable(t.files)]
  generated_srcs = getattr(library, "srcs", [])
  source = {
      "library" : library,
      "mode" : go.mode,
      "srcs" : generated_srcs + attr_srcs,
      "cover" : [],
      "x_defs" : {},
      "deps" : getattr(attr, "deps", []),
      "gc_goopts" : getattr(attr, "gc_goopts", []),
      "runfiles" : go._ctx.runfiles(collect_data = True),
      "cgo_archives" : [],
      "cgo_deps" : [],
      "cgo_exports" : [],
  }
  if coverage_instrumented and not attr.testonly:
    source["cover"] = attr_srcs
  for e in getattr(attr, "embed", []):
    _merge_embed(source, e)
  x_defs = source["x_defs"]
  for k,v in getattr(attr, "x_defs", {}).items():
    if "." not in k:
      k = "{}.{}".format(library.importmap, k)
    x_defs[k] = v
  source["x_defs"] = x_defs
  if library.resolve:
    library.resolve(go, attr, source, _merge_embed)
  return GoSource(**source)

def _infer_importpath(ctx):
  DEFAULT_LIB = "go_default_library"
  VENDOR_PREFIX = "/vendor/"
  # Check if import path was explicitly set
  path = getattr(ctx.attr, "importpath", "")
  # are we in forced infer mode?
  if path != "":
    return path, EXPLICIT_PATH
  # See if we can collect importpath from embeded libraries
  # This is the path that fixes tests as well
  for embed in getattr(ctx.attr, "embed", []):
    if GoLibrary not in embed:
      continue
    if embed[GoLibrary].pathtype == EXPLICIT_PATH:
      return embed[GoLibrary].importpath, EXPLICIT_PATH
  # TODO: stop using the prefix
  prefix = getattr(ctx.attr, "_go_prefix", None)
  path = prefix.go_prefix if prefix else ""
  # Guess an import path based on the directory structure
  # This should only really be relied on for binaries
  if path.endswith("/"):
    path = path[:-1]
  if ctx.label.package:
    path += "/" + ctx.label.package
  if ctx.label.name != DEFAULT_LIB and not path.endswith(ctx.label.name):
    path += "/" + ctx.label.name
  if path.rfind(VENDOR_PREFIX) != -1:
    path = path[len(VENDOR_PREFIX) + path.rfind(VENDOR_PREFIX):]
  if path.startswith("/"):
    path = path[1:]
  return path, INFERRED_PATH

def _get_go_binary(context_data):
  for f in context_data.sdk_files:
    parent = paths.dirname(f.path)
    sdk = paths.dirname(parent)
    parent = paths.basename(parent)
    if parent != "bin":
      continue
    basename = paths.basename(f.path)
    name, ext = paths.split_extension(basename)
    if name != "go":
      continue
    return sdk, f
  fail("Could not find go executable in go_sdk")

def go_context(ctx, attr=None):
  toolchain = ctx.toolchains["@io_bazel_rules_go//go:toolchain"]

  if not attr:
    attr = ctx.attr

  builders = getattr(attr, "_builders", None)
  if builders:
    builders = builders[GoBuilders]
  else:
    builders = GoBuilders(compile=None, link=None)
  host_only = getattr(attr, "_hostonly", False)

  context_data = attr._go_context_data
  mode = get_mode(ctx, host_only, toolchain, context_data)
  root, binary = _get_go_binary(context_data)

  stdlib = getattr(attr, "_stdlib", None)
  if stdlib:
    stdlib = get_source(stdlib).stdlib

  importpath, pathtype = _infer_importpath(ctx)
  return GoContext(
      # Fields
      toolchain = toolchain,
      mode = mode,
      root = root,
      go = binary,
      stdlib = stdlib,
      sdk_files = context_data.sdk_files,
      sdk_tools = context_data.sdk_tools,
      actions = ctx.actions,
      exe_extension = goos_to_extension(mode.goos),
      shared_extension = goos_to_shared_extension(mode.goos),
      crosstool = context_data.crosstool,
      package_list = context_data.package_list,
      importpath = importpath,
      pathtype = pathtype,
      cgo_tools = context_data.cgo_tools,
      builders = builders,
      env = context_data.env,
      tags = context_data.tags,
      # Action generators
      archive = toolchain.actions.archive,
      asm = toolchain.actions.asm,
      binary = toolchain.actions.binary,
      compile = toolchain.actions.compile,
      cover = toolchain.actions.cover if ctx.configuration.coverage_enabled else None,
      link = toolchain.actions.link,
      pack = toolchain.actions.pack,

      # Helpers
      args = _new_args,
      new_library = _new_library,
      library_to_source = _library_to_source,
      declare_file = _declare_file,
      declare_directory = _declare_directory,

      # Private
      _ctx = ctx, # TODO: All uses of this should be removed
  )

def _go_context_data(ctx):
  cpp = ctx.fragments.cpp
  features = ctx.features
  compiler_options = _filter_options(
    cpp.compiler_options(features) + cpp.unfiltered_compiler_options(features),
    _COMPILER_OPTIONS_BLACKLIST)
  linker_options = _filter_options(
    cpp.link_options + cpp.mostly_static_link_options(features, False),
    _LINKER_OPTIONS_BLACKLIST)

  env = {}
  tags = []
  if "gotags" in ctx.var:
    tags = ctx.var["gotags"].split(",")
  compiler_path, _ = cpp.ld_executable.rsplit("/", 1)
  return struct(
      strip = ctx.attr.strip,
      crosstool = ctx.files._crosstool,
      package_list = ctx.file._package_list,
      sdk_files = ctx.files._sdk_files,
      sdk_tools = ctx.files._sdk_tools,
      tags = tags,
      env = env,
      cgo_tools = struct(
          compiler_path = compiler_path,
          compiler_executable = cpp.compiler_executable,
          ld_executable = cpp.ld_executable,
          compiler_options = compiler_options,
          linker_options = linker_options,
          options = compiler_options + linker_options,
          c_options = cpp.c_options,
      ),
  )

go_context_data = rule(
    _go_context_data,
    attrs = {
        "strip": attr.string(mandatory = True),
        # Hidden internal attributes
        "_crosstool": attr.label(default = Label("//tools/defaults:crosstool")),
        "_package_list": attr.label(
            allow_files = True,
            single_file = True,
            default = "@go_sdk//:packages.txt",
        ),
        "_sdk_files": attr.label(
            allow_files = True,
            default="@go_sdk//:files",
        ),
        "_sdk_tools": attr.label(
            allow_files = True,
            cfg="host",
            default="@go_sdk//:tools",
        ),
    },
    fragments = ["cpp"],
)
