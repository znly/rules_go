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
    "@io_bazel_rules_go//go/private:mode.bzl",
    "LINKMODE_C_SHARED",
    "LINKMODE_C_ARCHIVE",
)

def emit_binary(go,
    name="",
    source = None,
    gc_linkopts = [],
    linkstamp=None,
    version_file=None,
    info_file=None):
  """See go/toolchains.rst#binary for full documentation."""

  if name == "": fail("name is a required parameter")

  archive = go.archive(go, source)
  extension = {
    LINKMODE_C_SHARED: go.shared_extension,
    LINKMODE_C_ARCHIVE: ".a",
  }.get(go.mode.link, go.exe_extension)
  executable = go.declare_file(go, name=name, ext=extension)
  go.link(go,
      archive=archive,
      executable=executable,
      gc_linkopts=gc_linkopts,
      linkstamp=linkstamp,
      version_file=version_file,
      info_file=info_file,
  )

  return archive, executable
