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
    "@io_bazel_rules_go//go/private:platforms.bzl",
    "PLATFORMS",
    _GOARCH = "GOARCH_CONSTRAINTS",
    _GOOS = "GOOS_CONSTRAINTS",
    _GOOS_GOARCH = "GOOS_GOARCH",
    _MSAN_GOOS_GOARCH = "MSAN_GOOS_GOARCH",
    _RACE_GOOS_GOARCH = "RACE_GOOS_GOARCH",
)

GOOS_GOARCH = _GOOS_GOARCH
GOOS = _GOOS
GOARCH = _GOARCH
RACE_GOOS_GOARCH = _RACE_GOOS_GOARCH
MSAN_GOOS_GOARCH = _MSAN_GOOS_GOARCH

def declare_config_settings():
    """Generates config_setting targets for each goos, goarch, and valid
    goos_goarch pair. These targets may be used in select expressions.
    Each target refers to a corresponding constraint_value in //go/toolchain.
    """
    for goos in GOOS:
        native.config_setting(
            name = goos,
            constraint_values = ["@io_bazel_rules_go//go/toolchain:" + goos],
        )
    for goarch in GOARCH:
        native.config_setting(
            name = goarch,
            constraint_values = ["@io_bazel_rules_go//go/toolchain:" + goarch],
        )
    for goos, goarch in GOOS_GOARCH:
        native.config_setting(
            name = goos + "_" + goarch,
            constraint_values = [
                "@io_bazel_rules_go//go/toolchain:" + goos,
                "@io_bazel_rules_go//go/toolchain:" + goarch,
            ],
        )

    # Used to detect when CGo is disabled, thus removing the need for a C/C++
    # toolchain.
    native.config_setting(
        name = "cgo_off",
        constraint_values = ["@io_bazel_rules_go//go/toolchain:cgo_off"],
    )

    # Additional settings for ios. Unfortunately, we cannot have a "darwin"
    # setting that covers both operating systems, so "darwin" here means macOS.
    # The "darwin" build tag will be true for both during execution; this only
    # matters when evaluating select expressions.
    native.config_setting(
        name = "ios",
        constraint_values = [
            "@bazel_tools//platforms:ios",
        ],
    )
    for goarch in ("arm", "arm64", "386", "amd64"):
        native.config_setting(
            name = "ios_" + goarch,
            constraint_values = [
                "@bazel_tools//platforms:ios",
                "@io_bazel_rules_go//go/toolchain:" + goarch,
            ]
        )
