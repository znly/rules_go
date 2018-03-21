// Copyright 2017 The Bazel Authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"flag"
	"fmt"
	"go/build"
	"os"
	"path/filepath"
	"strings"
)

var (
	// goBuildTags holds the build tags with which Go was built as a map.
	// This is useful for detecting the presence of a particular build tag.
	goBuildTags = map[string]bool{}

	// goReleaseTags holds the release tags with which Go was built as a map.
	// This is useful for detecting mininum required Go versions.
	goReleaseTags = map[string]bool{}

	cgoAbsoluteArgs = map[string]bool{
		"-I":             true,
		"-L":             true,
		"-isysroot":      true,
		"-isystem":       true,
		"-iquote":        true,
		"-include":       true,
		"-gcc-toolchain": true,
		"--sysroot":      true,
	}
)

// GoEnv holds the go environment as specified on the command line.
type GoEnv struct {
	// Go is the path to the go executable.
	Go string
	// Verbose debugging print control
	Verbose      bool
	rootFile     string
	rootPath     string
	cgo          bool
	compilerPath string
	goos         string
	goarch       string
	tags         string
	cc           string
	c_flags      multiFlag
	cxx_flags    multiFlag
	cpp_flags    multiFlag
	ld_flags     multiFlag
	shared       bool
}

func init() {
	for _, tag := range build.Default.BuildTags {
		goBuildTags[tag] = true
	}
	for _, tag := range build.Default.ReleaseTags {
		goReleaseTags[tag] = true
	}
}

// abs returns the absolute representation of path. Some tools/APIs require
// absolute paths to work correctly. Most notably, golang on Windows cannot
// handle relative paths to files whose absolute path is > ~250 chars, while
// it can handle absolute paths. See http://goo.gl/eqeWjm.
func abs(path string) string {
	if abs, err := filepath.Abs(path); err != nil {
		return path
	} else {
		return abs
	}
}

func absoluteCgoFlags(flags []string) []string {
	ret := make([]string, len(flags))
	for i := 0; i < len(flags); i++ {
		f := flags[i]
		ret[i] = f
		// simple case, exact match
		if cgoAbsoluteArgs[f] {
			ret[i+1] = abs(flags[i+1])
			i++ // skip next
			continue
		}
		// slower, need to check for prefix
		for wf, _ := range cgoAbsoluteArgs {
			if strings.HasPrefix(f, wf) {
				// check for in the form of "-key=value"
				if len(f) > len(wf) && f[len(wf):len(wf)+1] == "=" {
					wf += "="
				}
				ret[i] = wf[:len(wf)] + abs(flags[i][len(wf):])
				break
			}
		}
	}
	return ret
}

func envUpdate(oldEnv, newEnv []string) []string {
	retEnvMap := map[string]string{}
	retEnv := []string{}
	for _, e := range oldEnv {
		pair := strings.SplitN(e, "=", 2)
		k, v := pair[0], pair[1]
		retEnvMap[k] = v
	}
	for _, e := range newEnv {
		pair := strings.SplitN(e, "=", 2)
		k, v := pair[0], pair[1]
		retEnvMap[k] = v
	}
	for k, v := range retEnvMap {
		retEnv = append(retEnv, k+"="+v)
	}
	return retEnv
}

func envFlags(flags *flag.FlagSet) *GoEnv {
	env := &GoEnv{}
	flags.StringVar(&env.Go, "go", "", "The path to the go tool.")
	flags.StringVar(&env.rootFile, "root_file", "", "The go root file to use.")
	flags.BoolVar(&env.cgo, "cgo", false, "The value for CGO_ENABLED.")
	flags.StringVar(&env.compilerPath, "compiler_path", "", "The value for PATH.")
	flags.StringVar(&env.goos, "goos", "", "The value for GOOS.")
	flags.StringVar(&env.goarch, "goarch", "", "The value for GOARCH.")
	flags.BoolVar(&env.Verbose, "v", false, "Enables verbose debugging prints.")
	flags.StringVar(&env.tags, "tags", "", "Only pass through files that match these tags.")
	flags.BoolVar(&env.shared, "shared", false, "Build in shared mode")
	flags.StringVar(&env.cc, "cc", "", "Sets the c compiler to use")
	flags.Var(&env.c_flags, "c_flag", "An entry to add to the C compiler flags")
	flags.Var(&env.cxx_flags, "cxx_flag", "An entry to add to the C++ compiler flags")
	flags.Var(&env.cpp_flags, "cpp_flag", "An entry to add to the CPP compiler flags")
	flags.Var(&env.ld_flags, "ld_flag", "An entry to add to the c linker flags")
	return env
}

func (env *GoEnv) update() error {
	if env.rootFile != "" {
		env.rootFile = abs(env.rootFile)
		env.rootPath = env.rootFile
		if s, err := os.Stat(env.rootFile); err == nil {
			if !s.IsDir() {
				env.rootPath = filepath.Dir(env.rootFile)
			}
		}
	}
	if env.compilerPath != "" {
		env.compilerPath = abs(env.compilerPath)
	}
	return nil
}

func (env *GoEnv) Env() []string {
	return envUpdate(os.Environ(), env.env())
}

func (env *GoEnv) env() []string {
	cgoEnabled := "0"
	if env.cgo {
		cgoEnabled = "1"
	}
	result := []string{
		fmt.Sprintf("GOROOT=%s", env.rootPath),
		"GOROOT_FINAL=GOROOT",
		fmt.Sprintf("GOOS=%s", env.goos),
		fmt.Sprintf("GOARCH=%s", env.goarch),
		fmt.Sprintf("CGO_ENABLED=%s", cgoEnabled),
		fmt.Sprintf("PATH=%s", env.compilerPath),
		fmt.Sprintf("COMPILER_PATH=%s", env.compilerPath),
	}
	if env.cc != "" {
		cc := abs(env.cc)
		result = append(result,
			fmt.Sprintf("CC=%s", cc),
			fmt.Sprintf("CXX=%s", cc),
		)
	}
	cgoFlags := map[string]multiFlag{
		"CGO_CFLAGS":   env.c_flags,
		"CGO_CXXFLAGS": env.cxx_flags,
		"CGO_CPPFLAGS": env.cpp_flags,
		"CGO_LDFLAGS":  env.ld_flags,
	}
	for envVar, flags := range cgoFlags {
		v := strings.Join(absoluteCgoFlags(flags), " ")
		result = append(result, envVar+"="+v)
	}
	return result
}

func (env *GoEnv) BuildContext() build.Context {
	bctx := build.Default
	bctx.GOROOT = env.rootPath
	bctx.GOOS = env.goos
	bctx.GOARCH = env.goarch
	bctx.CgoEnabled = env.cgo
	bctx.BuildTags = strings.Split(env.tags, ",")
	return bctx
}
