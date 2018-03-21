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
    "@io_bazel_rules_go//go/private:common.bzl",
    "split_srcs",
    "join_srcs",
    "pkg_dir",
    "sets",
    "as_set",
    "as_list",
    "as_iterable",
)
load(
    "@io_bazel_rules_go//go/private:providers.bzl",
    "GoLibrary",
)
load(
    "@io_bazel_rules_go//go/private:rules/rule.bzl",
    "go_rule",
)
load(
    "@io_bazel_rules_go//go/private:mode.bzl",
    "LINKMODE_C_SHARED",
    "LINKMODE_C_ARCHIVE",
)

_CgoCodegen = provider()

# Maximum number of characters in stem of base name for mangled cgo files.
# Some file systems have fairly short limits (eCryptFS has a limit of 143),
# and this should be kept below those to accomodate number suffixes and
# extensions.
MAX_STEM_LENGTH = 130

def _mangle(src, stems):
  """_mangle returns a file stem and extension for a source file that will
  be passed to cgo. The stem will be unique among other sources in the same
  library. It will not contain any separators, so cgo's name mangling algorithm
  will be a no-op."""
  stem, _, ext = src.basename.rpartition('.')
  if len(stem) > MAX_STEM_LENGTH:
    stem = stem[:MAX_STEM_LENGTH]
  if stem in stems:
    for i in range(100):
      next_stem = "{}_{}".format(stem, i)
      if next_stem not in stems:
        break
    if next_stem in stems:
      fail("could not find unique mangled name for {}".format(src.path))
    stem = next_stem
  stems[stem] = True
  return stem, ext


_DEFAULT_PLATFORM_COPTS = select({
    "@io_bazel_rules_go//go/platform:darwin": [],
    "@io_bazel_rules_go//go/platform:windows_amd64": ["-mthreads"],
    "//conditions:default": ["-pthread"],
})

def _c_filter_options(options, blacklist):
  return [opt for opt in options
        if not any([opt.startswith(prefix) for prefix in blacklist])]

def _select_archives(files):
  """Selects a single archive from a list of files produced by a
  static cc_library.

  In some configurations, cc_library can produce multiple files, and the
  order isn't guaranteed, so we can't simply pick the first one.
  """
  # list of file extensions in descending order or preference.
  outs = []
  exts = [".pic.lo", ".lo", ".a"]
  for ext in exts:
    for f in files:
      if f.basename.endswith(ext):
        outs.append(f)
  if not outs:
    fail("cc_library did not produce any files")
  return outs

def _cgo_codegen_impl(ctx):
  go = go_context(ctx)
  if not go.cgo_tools:
    fail("Go toolchain does not support cgo")
  linkopts = ctx.attr.linkopts[:]
  copts = go.cgo_tools.c_options + go.cgo_tools.compiler_options + ctx.attr.copts
  deps = depset([], order="topological")
  cgo_export_h = go.declare_file(go, path="_cgo_export.h")
  cgo_export_c = go.declare_file(go, path="_cgo_export.c")
  cgo_main = go.declare_file(go, path="_cgo_main.c")
  cgo_types = go.declare_file(go, path="_cgo_gotypes.go")
  out_dir = cgo_main.dirname

  cc = go.cgo_tools.compiler_executable
  args = go.args(go)
  args.add(["-cc", str(cc), "-objdir", out_dir])

  c_outs = [cgo_export_h, cgo_export_c]
  go_outs = [cgo_types]

  source = split_srcs(ctx.files.srcs)
  for src in source.headers:
    copts.extend(['-iquote', src.dirname])
  stems = {}
  for src in source.go:
    mangled_stem, src_ext = _mangle(src, stems)
    gen_file = go.declare_file(go, path=mangled_stem + ".cgo1."+src_ext)
    gen_c_file = go.declare_file(go, path=mangled_stem + ".cgo2.c")
    go_outs.append(gen_file)
    c_outs.append(gen_c_file)
    args.add(["-src", gen_file.path + "=" + src.path])
  for src in source.asm:
    mangled_stem, src_ext = _mangle(src, stems)
    gen_file = go.declare_file(go, path=mangled_stem + ".cgo1."+src_ext)
    go_outs.append(gen_file)
    args.add(["-src", gen_file.path + "=" + src.path])
  for src in source.c:
    mangled_stem, src_ext = _mangle(src, stems)
    gen_file = go.declare_file(go, path=mangled_stem + ".cgo1."+src_ext)
    c_outs.append(gen_file)
    args.add(["-src", gen_file.path + "=" + src.path])

  inputs = sets.union(ctx.files.srcs, go.crosstool, go.stdlib.files,
                      *[d.cc.transitive_headers for d in ctx.attr.deps])
  deps = sets.union(deps, *[d.cc.libs for d in ctx.attr.deps])
  runfiles = ctx.runfiles(collect_data = True)
  for d in ctx.attr.deps:
    runfiles = runfiles.merge(d.data_runfiles)
    copts.extend(['-D' + define for define in d.cc.defines])
    for inc in d.cc.include_directories:
      copts.extend(['-I', inc])
    for inc in d.cc.quote_include_directories:
      copts.extend(['-iquote', inc])
    for inc in d.cc.system_include_directories:
      copts.extend(['-isystem', inc])
    for lib in as_iterable(d.cc.libs):
      if lib.basename.startswith('lib') and lib.basename.endswith('.so'):
        linkopts.extend(['-L', lib.dirname, '-l', lib.basename[3:-3]])
      else:
        linkopts.append(lib.path)
    linkopts.extend(d.cc.link_flags)

  args.add(linkopts, before_each="-ld_flag")

  # The first -- below is to stop the cgo from processing args, the
  # second is an actual arg to forward to the underlying go tool
  args.add(["--", "--"])
  args.add(copts)
  ctx.actions.run(
      inputs = inputs + go.crosstool,
      outputs = c_outs + go_outs + [cgo_main],
      mnemonic = "CGoCodeGen",
      progress_message = "CGoCodeGen %s" % ctx.label,
      executable = go.builders.cgo,
      arguments = [args],
      env = go.env,
  )

  return [
      _CgoCodegen(
          go_files = as_set(go_outs),
          main_c = as_set([cgo_main]),
          deps = as_list(deps),
          exports = [cgo_export_h],
      ),
      DefaultInfo(
          files = depset(),
          runfiles = runfiles,
      ),
      OutputGroupInfo(
          go_files = as_set(go_outs),
          input_go_files = sets.union(source.go, source.asm),
          c_files = sets.union(c_outs, source.headers),
          main_c = as_set([cgo_main]),
      ),
  ]

_cgo_codegen = go_rule(
    _cgo_codegen_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = True),
        "deps": attr.label_list(
            allow_files = False,
            providers = ["cc"],
        ),
        "copts": attr.string_list(),
        "linkopts": attr.string_list(),
    },
)

def _cgo_import_impl(ctx):
  go = go_context(ctx)
  out = go.declare_file(go, path="_cgo_import.go")
  args = go.args(go)
  args.add([
      "-dynout", out,
      "-dynimport", ctx.file.cgo_o,
      "-src", ctx.files.sample_go_srcs[0],
  ])
  ctx.actions.run(
      inputs = [
          ctx.file.cgo_o,
          ctx.files.sample_go_srcs[0],
      ] + go.stdlib.files,
      outputs = [out],
      executable = go.builders.cgo,
      arguments = [args],
      mnemonic = "CGoImportGen",
  )
  return struct(
      files = depset([out]),
  )

_cgo_import = go_rule(
    _cgo_import_impl,
    attrs = {
        "cgo_o": attr.label(
            allow_files = True,
            single_file = True,
        ),
        "sample_go_srcs": attr.label_list(allow_files = True),
    },
)
"""Generates symbol-import directives for cgo

Args:
  cgo_o: The loadable object to extract dynamic symbols from.
  sample_go_src: A go source which is compiled together with the generated file.
    The generated file will have the same Go package name as this file.
  out: Destination of the generated codes.
"""

def _pure(ctx, mode):
    return mode.pure

def _not_pure(ctx, mode):
    return not mode.pure

def _cgo_library_to_source(go, attr, source, merge):
  library = source["library"]
  if source["mode"].pure:
    source["srcs"] = library.input_go_srcs + source["srcs"]
    return
  source["srcs"] = library.gen_go_srcs + source["srcs"]
  source["cgo_deps"] = source["cgo_deps"] + library.cgo_deps
  source["cgo_exports"] = source["cgo_exports"] + library.cgo_exports
  source["cgo_archives"] = library.cgo_archives
  source["runfiles"] = source["runfiles"].merge(attr.codegen.data_runfiles)

def _cgo_collect_info_impl(ctx):
  go = go_context(ctx)
  codegen = ctx.attr.codegen[_CgoCodegen]
  runfiles = ctx.runfiles(collect_data = True)
  runfiles = runfiles.merge(ctx.attr.codegen.data_runfiles)

  library = go.new_library(go,
      resolver=_cgo_library_to_source,
      input_go_srcs = ctx.files.input_go_srcs,
      gen_go_srcs = ctx.files.gen_go_srcs,
      cgo_deps = ctx.attr.codegen[_CgoCodegen].deps,
      cgo_exports = ctx.attr.codegen[_CgoCodegen].exports,
      cgo_archives = _select_archives(ctx.files.libs),
  )
  source = go.library_to_source(go, ctx.attr, library, ctx.coverage_instrumented())

  return [
      source, library,
      DefaultInfo(files = depset(), runfiles = runfiles),
  ]

_cgo_collect_info = go_rule(
    _cgo_collect_info_impl,
    attrs = {
        "codegen": attr.label(
            mandatory = True,
            providers = [_CgoCodegen],
        ),
        "input_go_srcs": attr.label_list(
            mandatory = True,
            allow_files = [".go"],
        ),
        "gen_go_srcs": attr.label_list(
            mandatory = True,
            allow_files = [".go"],
        ),
        "libs": attr.label_list(
            mandatory = True,
            providers = ["cc"],
        ),
    },
)
"""No-op rule that collects information from _cgo_codegen and cc_library
info into a GoSourceList provider for easy consumption."""

def setup_cgo_library(name, srcs, cdeps, copts, clinkopts):
  # Apply build constraints to source files (both Go and C) but not to header
  # files. Separate filtered Go and C sources.

  # Run cgo on the filtered Go files. This will split them into pure Go files
  # and pure C files, plus a few other glue files.
  base_dir = pkg_dir(
      "external/" + REPOSITORY_NAME[1:] if len(REPOSITORY_NAME) > 1 else "",
      PACKAGE_NAME)
  copts = copts + ["-I", base_dir]

  cgo_codegen_name = name + ".cgo_codegen"
  _cgo_codegen(
      name = cgo_codegen_name,
      srcs = srcs,
      deps = cdeps,
      copts = copts,
      linkopts = clinkopts,
      visibility = ["//visibility:private"],
  )

  select_go_files = name + ".select_go_files"
  native.filegroup(
      name = select_go_files,
      srcs = [cgo_codegen_name],
      output_group = "go_files",
      visibility = ["//visibility:private"],
  )

  select_input_go_files = name + ".select_input_go_files"
  native.filegroup(
      name = select_input_go_files,
      srcs = [cgo_codegen_name],
      output_group = "input_go_files",
      visibility = ["//visibility:private"],
  )

  select_c_files = name + ".select_c_files"
  native.filegroup(
      name = select_c_files,
      srcs = [cgo_codegen_name],
      output_group = "c_files",
      visibility = ["//visibility:private"],
  )

  select_main_c = name + ".select_main_c"
  native.filegroup(
      name = select_main_c,
      srcs = [cgo_codegen_name],
      output_group = "main_c",
      visibility = ["//visibility:private"],
  )

  # Compile C sources and generated files into a library. This will be linked
  # into binaries that depend on this cgo_library. It will also be used
  # in _cgo_.o.
  platform_copts = _DEFAULT_PLATFORM_COPTS
  platform_linkopts = platform_copts

  cgo_lib_name = name + ".cgo_c_lib"
  native.cc_library(
      name = cgo_lib_name,
      srcs = [select_c_files],
      deps = cdeps,
      copts = copts + platform_copts + [
          # The generated thunks often contain unused variables.
          "-Wno-unused-variable",
      ],
      linkopts = clinkopts + platform_linkopts,
      linkstatic = 1,
      # _cgo_.o needs all symbols because _cgo_import needs to see them.
      alwayslink = 1,
      visibility = ["//visibility:private"],
  )

  # Create a loadable object with no undefined references. cgo reads this
  # when it generates _cgo_import.go.
  cgo_o_name = name + "._cgo_.o"
  native.cc_binary(
      name = cgo_o_name,
      srcs = [select_main_c],
      deps = cdeps + [cgo_lib_name],
      copts = copts,
      linkopts = clinkopts,
      visibility = ["//visibility:private"],
  )

  # Create a Go file which imports symbols from the C library.
  cgo_import_name = name + ".cgo_import"
  _cgo_import(
      name = cgo_import_name,
      cgo_o = cgo_o_name,
      sample_go_srcs = [select_go_files],
      visibility = ["//visibility:private"],
  )

  cgo_embed_name = name + ".cgo_embed"
  _cgo_collect_info(
      name = cgo_embed_name,
      codegen = cgo_codegen_name,
      input_go_srcs = [
          select_input_go_files,
      ],
      gen_go_srcs = [
          select_go_files,
          cgo_import_name,
      ],
      libs = [cgo_c_lib_name],
      visibility = ["//visibility:private"],
  )

  return cgo_embed_name

# Sets up the cc_ targets when a go_binary is built in either c-archive or
# c-shared mode.
def go_binary_c_archive_shared(name, kwargs):
  linkmode = kwargs.get("linkmode")
  if linkmode not in [LINKMODE_C_SHARED, LINKMODE_C_ARCHIVE]:
    return
  cgo_exports = name + ".cgo_exports"
  c_hdrs = name + ".c_hdrs"
  cc_import_name = name + ".cc_import"
  cc_library_name = name + ".cc"
  native.filegroup(
    name = cgo_exports,
    srcs = [name],
    output_group = "cgo_exports",
    visibility = ["//visibility:private"],
  )
  native.genrule(
    name = c_hdrs,
    srcs = [cgo_exports],
    outs = ["%s.h" % name],
    cmd = "cat $(SRCS) > $(@)",
    visibility = ["//visibility:private"],
  )
  cc_import_kwargs = {}
  if linkmode == LINKMODE_C_SHARED:
    cc_import_kwargs["shared_library"] = name
  elif linkmode == LINKMODE_C_ARCHIVE:
    cc_import_kwargs["static_library"] = name
  native.cc_import(
    name = cc_import_name,
    alwayslink = 1,
    visibility = ["//visibility:private"],
    **cc_import_kwargs
  )
  native.cc_library(
    name = cc_library_name,
    hdrs = [c_hdrs],
    deps = [cc_import_name],
    alwayslink = 1,
    linkstatic = (linkmode == LINKMODE_C_ARCHIVE and 1 or 0),
    copts = _DEFAULT_PLATFORM_COPTS,
    linkopts = _DEFAULT_PLATFORM_COPTS,
    visibility = ["//visibility:public"],
  )
