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
load(
    "@io_bazel_rules_go//go/private:mode.bzl",
    "LINKMODE_C_SHARED",
    "LINKMODE_C_ARCHIVE",
)

_CGO_ATTRS = {
    "srcs": None,
    "cdeps": [],
    "copts": [],
    "clinkopts": [],
}

def _deprecate(attr, name, ruletype, kwargs, message):
  value = kwargs.pop(attr, None)
  if value and native.repository_name() == "@":
    print("\nDEPRECATED: //{}:{} : the {} attribute on {} is deprecated. {}".format(native.package_name(), name, attr, ruletype, message))
  return value

#TODO(#1208): Remove library attribute
def _deprecate_library(name, ruletype, kwargs):
  value = _deprecate("library", name, ruletype, kwargs, "Please migrate to embed.")
  if value:
    kwargs["embed"] = kwargs.get("embed", []) + [value]

#TODO(#1207): Remove importpath
def _deprecate_importpath(name, ruletype, kwargs):
  _deprecate("importpath", name, ruletype, kwargs, "")

def _cgo(name, kwargs):
  cgo = kwargs.pop("cgo", False)
  if not cgo: return
  cgo_attrs = {"name":name}
  for key, default in _CGO_ATTRS.items():
    cgo_attrs[key] = kwargs.pop(key, default)
  cgo_embed = setup_cgo_library(**cgo_attrs)
  kwargs["embed"] = kwargs.get("embed", []) + [cgo_embed]

def go_library_macro(name, **kwargs):
  """See go/core.rst#go_library for full documentation."""
  _deprecate_library(name, "go_library", kwargs)
  _cgo(name, kwargs)
  go_library(name = name, **kwargs)

def go_binary_macro(name, **kwargs):
  """See go/core.rst#go_binary for full documentation."""
  _deprecate_library(name, "go_binary", kwargs)
  _deprecate_importpath(name, "go_binary", kwargs)
  _cgo(name, kwargs)
  go_binary(name = name, **kwargs)
  _go_binary_c_archive_shared(name, kwargs)

def _go_binary_c_archive_shared(name, kwargs):
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
  )
  native.genrule(
    name = c_hdrs,
    srcs = [cgo_exports],
    outs = [name + ".h"],
    cmd = "cat $(SRCS) > $(@)",
  )
  cc_import_kwargs = {}
  if linkmode == LINKMODE_C_SHARED:
    cc_import_kwargs["shared_library"] = name
  elif linkmode == LINKMODE_C_ARCHIVE:
    cc_import_kwargs["static_library"] = name
  native.cc_import(
    name = cc_import_name,
    alwayslink = 1,
    **cc_import_kwargs
  )
  native.cc_library(
    name = cc_library_name,
    hdrs = [c_hdrs],
    deps = [cc_import_name],
    includes = ["."],
    alwayslink = 1,
    linkstatic = 1,
    copts = select({
        "@io_bazel_rules_go//go/platform:darwin": [],
        "@io_bazel_rules_go//go/platform:windows_amd64": ["-mthreads"],
        "//conditions:default": ["-pthread"],
    }),
    linkopts = select({
        "@io_bazel_rules_go//go/platform:darwin": [],
        "@io_bazel_rules_go//go/platform:windows_amd64": ["-mthreads"],
        "//conditions:default": ["-pthread"],
    }),
    visibility = ["//visibility:public"],
  )

def go_test_macro(name, **kwargs):
  """See go/core.rst#go_test for full documentation."""
  _deprecate_library(name, "go_test", kwargs)
  _deprecate_importpath(name, "go_test", kwargs)
  _cgo(name, kwargs)
  go_test(name = name, **kwargs)
