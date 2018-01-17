"""A basic go_proto_library.

Takes .proto as srcs and go_proto_library as deps
Note: can also work with a go_library(name=name,...)
      and a filegroup of .protos (name=name+"_protos",...)

A go_proto_library can then be a dependency of go_library or another go_proto_library.

Requires/Uses:
@io_bazel_rules_go for go_* macros/rules.

Does:
Generate protos using the open-source protoc and protoc-gen-go.
Handles transitive dependencies.
gRPC for service generation
Handles bazel-style names like 'foo_proto',
and also Go package-style like 'go_default_library'

Does not yet:
Gets confused if local protos use 'option go_package'

Usage:

In the BUILD file where protos are

load("@io_bazel_rules_go//proto:go_proto_library.bzl", "go_proto_library")

go_proto_library(
  name = "my_proto",
  srcs = ["my.proto"],
  deps = [
    ":other_proto",
    "@com_github_golang_protobuf//ptypes/duration:go_default_library",
  ],
)
"""

load("@io_bazel_rules_go//go:def.bzl", "go_library", "go_repository")

_DEFAULT_LIB = "go_default_library"  # matching go_library

_PROTOS_SUFFIX = "_protos"

_GO_GOOGLE_PROTOBUF = "go_google_protobuf"

_WELL_KNOWN_REPO = "@com_github_golang_protobuf//ptypes/"

def _collect_protos_import(ctx):
  """Collect the list of transitive protos and m_import_path.

  Paths of the form Mpath/to.proto=foo.com/bar specify a mapping into the global Go namespace.
  https://github.com/golang/protobuf#parameters

  Args:
    ctx: the standard bazel rule ctx object.

  Returns:
    (list of unique protos, list of m_import paths)
  """
  protos = depset()
  m_import_path = []
  for d in ctx.attr.deps:
    if not hasattr(d, "_protos"):
      # should be a raw filegroup then
      protos += list(d.files)
      continue
    protos += d._protos
    m_import_path.append(d._m_import_path)
  return list(protos), m_import_path

def _drop_external(path):
  """Drop leading '../' indicating an external dir of the form ../$some-repo.

  Non-generated external protos show up in a parallel directory.
  e.g. ptypes/any/any.proto is at ../com_github_golang_protobuf/ptypes/any/any.proto
  So this function detects and drops the 2 leading directories in this case.

  Args:
    path: short_path of a proto file

  Returns:
    A cleaned path.
  """
  if not path.startswith("../"):
    return path
  return "/".join(path.split("/")[2:])

def _check_bazel_style(ctx):
  """If the library name is not 'go_default_library', then we have to create an extra level of indirection."""
  if ctx.label.name == _DEFAULT_LIB + _PROTOS_SUFFIX:
    return ctx.outputs.outs, ""
  proto_outs = [
      ctx.new_file(
          ctx.configuration.bin_dir,
          s.basename[:-len(".proto")] + ".pb.go")
      for s in ctx.files.srcs
  ]
  for proto_out, ctx_out in zip(proto_outs, ctx.outputs.outs):
    ctx.action(
        inputs=[proto_out],
        outputs=[ctx_out],
        command="cp %s %s" % (proto_out.path, ctx_out.path),
        mnemonic="GoProtocGenCp")
  return proto_outs, "/" + ctx.label.name[:-len(_PROTOS_SUFFIX)]

def _add_target_suffix(target, suffix):
  idx = target.find(":")
  if idx != -1:
    return target + suffix
  toks = target.split("/")
  return target + ":" + toks[-1] + suffix

def _well_known_proto_deps(deps, repo):
  for d in deps:
    if d.startswith(_WELL_KNOWN_REPO):
      return [repo + "//:" + _GO_GOOGLE_PROTOBUF]
  return []

def _well_known_import_key(name):
  return "%s%s:go_default_library" % (_WELL_KNOWN_REPO, name)

_well_known_imports = [
    "any",
    "duration",
    "empty",
    "struct",
    "timestamp",
    "wrappers",
]

# If you have well_known proto deps, rules_go will add a magic
# google/protobuf/ directory at the import root
def go_google_protobuf(name = _GO_GOOGLE_PROTOBUF):
  deps = [_add_target_suffix(_well_known_import_key(wk), _PROTOS_SUFFIX)
          for wk in _well_known_imports]
  outs = [wk + ".proto" for wk in _well_known_imports]

  native.genrule(
      name = name,
      srcs = deps,
      outs = ["google/protobuf/"+o for o in outs],
      cmd = "cp $(SRCS) $(@D)/google/protobuf/",
      visibility = ["//visibility:public"],
  )

def go_proto_repositories(shared = 1):
  """Add this to your WORKSPACE to pull in all of the needed dependencies."""
  print("DEPRECATED: go_proto_repositories is redundant and will be removed soon")
