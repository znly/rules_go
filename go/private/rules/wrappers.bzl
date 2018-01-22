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

load("@io_bazel_rules_go//go/private:rules/binary.bzl", "go_binary")
load("@io_bazel_rules_go//go/private:rules/library.bzl", "go_library")
load("@io_bazel_rules_go//go/private:rules/test.bzl", "go_test")
load("@io_bazel_rules_go//go/private:rules/cgo.bzl", "setup_cgo_library")
load("@io_bazel_rules_go//go/private:common.bzl", "auto_importpath", "test_library_suffix")
load(
    "@io_bazel_rules_go//go/private:mode.bzl",
    "mode_string",
)
load(
    "@io_bazel_rules_go//go/private:mode.bzl",
    "LINKMODE_NORMAL",
    "LINKMODE_C_SHARED",
    "LINKMODE_C_ARCHIVE",
)

#TODO(#1208): Remove library attribute
def go_library_macro(name, srcs=None, embed=[], cgo=False, cdeps=[], copts=[], clinkopts=[], importpath="", library=None, objc=False, **kwargs):
  """See go/core.rst#go_library for full documentation."""
  if library and native.repository_name() == "@":
    print("\nDEPRECATED: //{}:{} : the library attribute on go_library is deprecated. Please migrate to embed.".format(native.package_name(), name))
    embed = embed + [library]

  if cgo:
    cgo_embed = setup_cgo_library(
        name = name,
        srcs = srcs,
        cdeps = cdeps,
        copts = copts,
        clinkopts = clinkopts,
        objc = objc,
    )
    embed = embed + [cgo_embed]
    srcs = []
  go_library(
      name = name,
      srcs = srcs,
      embed = embed,
      importpath = importpath,
      **kwargs
  )

#TODO(#1207): Remove importpath
#TODO(#1208): Remove library attribute
def go_binary_macro(name, srcs=None, embed=[], cgo=False, cdeps=[], copts=[], clinkopts=[], library=None, importpath="", **kwargs):
  """See go/core.rst#go_binary for full documentation."""
  if library and native.repository_name() == "@":
    print("\nDEPRECATED: //{}:{} : the library attribute on go_binary is deprecated. Please migrate to embed.".format(native.package_name(), name))
    embed = embed + [library]
  #TODO: Turn on the deprecation warning when gazelle stops adding these
  #if importpath and native.repository_name() == "@":
  #  print("\nDEPRECATED: //{}:{} : the importpath attribute on go_binary is deprecated.".format(native.package_name(), name))

  if cgo:
    cgo_embed = setup_cgo_library(
        name = name,
        srcs = srcs,
        cdeps = cdeps,
        copts = copts,
        clinkopts = clinkopts,
    )
    embed = embed + [cgo_embed]
    srcs = []
  go_binary(
      name = name,
      srcs = srcs,
      embed = embed,
      **kwargs
  )
  link = kwargs.get("link")
  if link in [LINKMODE_C_SHARED, LINKMODE_C_ARCHIVE]:
    native.filegroup(
      name = name + "_cgo_exports",
      srcs = [":" + name],
      output_group = "cgo_exports",
    )
    native.genrule(
      name = name + "_c_headers",
      srcs = [":" + name + "_cgo_exports"],
      outs = [name + ".h"],
      cmd = "cat $(SRCS) > $(@)",
    )
    native.filegroup(
      name = name + "_binary",
      srcs = [":" + name],
      output_group = "binary",
    )
    cc_import_kwargs = {}
    if link == LINKMODE_C_SHARED:
      cc_import_kwargs["shared_library"] = ":" + name + "_binary"
    elif link == LINKMODE_C_ARCHIVE:
      cc_import_kwargs["static_library"] = ":" + name + "_binary"
    native.cc_import(
      name = name + "_cc",
      hdrs = [":" + name + "_c_headers"],
      alwayslink = 1,
      visibility = ["//visibility:public"],
      **cc_import_kwargs
    )
    native.objc_import(
      name = name + "_objc",
      hdrs = [":" + name + "_c_headers"],
      alwayslink = 1,
      archives = [":" + name + "_binary"],
      visibility = ["//visibility:public"],
    )

#TODO(#1207): Remove importpath
#TODO(#1208): Remove library attribute
def go_test_macro(name, srcs=None, deps=None, importpath=None, library=None, embed=[], gc_goopts=[], cgo=False, cdeps=[], copts=[], clinkopts=[], x_defs={}, **kwargs):
  """See go/core.rst#go_test for full documentation."""
  if library and native.repository_name() == "@":
    print("\nDEPRECATED: //{}:{} : the library attribute on go_test is deprecated. Please migrate to embed.".format(native.package_name(), name))
    embed = embed + [library]
  if not importpath:
    importpath = auto_importpath
  #TODO: Turn on the deprecation warning when gazelle stops adding these
  #elif native.repository_name() == "@":
  #  print("\nDEPRECATED: //{}:{} : the importpath attribute on go_test is deprecated.".format(native.package_name(), name))


  library_name = name + test_library_suffix
  go_library_macro(
      name = library_name,
      visibility = ["//visibility:private"],
      srcs = srcs,
      deps = deps,
      importpath = importpath,
      embed = embed,
      gc_goopts = gc_goopts,
      testonly = True,
      tags = ["manual"],
      cgo = False,
      cdeps = cdeps,
      copts = copts,
      clinkopts = clinkopts,
      x_defs = x_defs,
  )
  go_test(
      name = name,
      library = library_name,
      gc_goopts = gc_goopts,
      **kwargs
  )
