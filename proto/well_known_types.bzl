load("@io_bazel_rules_go//proto:def.bzl", "go_proto_library")

WELL_KNOWN_TYPES_MAP = {
    "any": ("github.com/golang/protobuf/ptypes/any", []),
    "api": ("github.com/golang/protobuf/ptypes/api", ["source_context", "type"]),
    "compiler_plugin": ("github.com/golang/protobuf/protoc-gen-go/plugin", ["descriptor"]),
    "descriptor": ("github.com/golang/protobuf/protoc-gen-go/descriptor", []),
    "duration": ("github.com/golang/protobuf/ptypes/duration", []),
    "empty": ("github.com/golang/protobuf/ptypes/empty", []),
    "field_mask": ("google.golang.org/genproto/protobuf/field_mask", []),
    "source_context": ("google.golang.org/genproto/protobuf/source_context", []),
    "struct": ("github.com/golang/protobuf/ptypes/struct", []),
    "timestamp": ("github.com/golang/protobuf/ptypes/timestamp", []),
    "type": ("google.golang.org/genproto/protobuf/ptype", ["any", "source_context"]),
    "wrappers": ("github.com/golang/protobuf/ptypes/wrappers", []),
}

GOGO_WELL_KNOWN_TYPE_REMAPS = [
    "Mgoogle/protobuf/{}.proto=github.com/gogo/protobuf/types".format(wkt)
    for wkt, (go_package, _) in WELL_KNOWN_TYPES_MAP.items() if "protoc-gen-go" not in go_package
] + [
    "Mgoogle/protobuf/descriptor.proto=github.com/gogo/protobuf/protoc-gen-gogo/descriptor",
    "Mgoogle/protobuf/compiler_plugin.proto=github.com/gogo/protobuf/protoc-gen-gogo/plugin",
]

def gen_well_known_types():
    rules = []
    for wkt, (go_package, deps) in WELL_KNOWN_TYPES_MAP.items():
        name = "wkt_{}_proto".format(wkt)
        rules.append("@io_bazel_rules_go//proto:{}".format(name))
        go_proto_library(
            name = name,
            compilers = ["@io_bazel_rules_go//proto:go_proto_bootstrap"],
            importpath = go_package,
            proto = "@com_google_protobuf//:{}_proto".format(wkt),
            visibility = ["//visibility:public"],
            deps = ["@io_bazel_rules_go//proto:wkt_{}_proto".format(dep) for dep in deps],
        )
    return rules

