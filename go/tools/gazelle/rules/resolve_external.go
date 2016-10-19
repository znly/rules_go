/* Copyright 2016 The Bazel Authors. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package rules

import (
	"strings"

	"golang.org/x/tools/go/vcs"
)

var (
	// repoRootForImportPath is overwritten only in unit test to avoid depending on
	// network communication.
	repoRootForImportPath = vcs.RepoRootForImportPath
)

type externalResolver struct{}

// resolve resolves "importpath" into a label, assuming that it is a label in an
// external repository. It also assumes that the external repository follows the
// recommended reverse-DNS form of workspace name as described in
// http://bazel.io/docs/be/functions.html#workspace.
func (e externalResolver) resolve(importpath, dir string) (label, error) {
	r := specialCases(importpath)
	if r == nil {
		var err error
		if r, err = repoRootForImportPath(importpath, false); err != nil {
			return label{}, err
		}
	}

	prefix := r.Root
	var pkg string
	if importpath != prefix {
		pkg = strings.TrimPrefix(importpath, prefix+"/")
	}

	components := strings.Split(prefix, "/")
	labels := strings.Split(components[0], ".")
	var reversed []string
	for i := range labels {
		l := labels[len(labels)-i-1]
		reversed = append(reversed, l)
	}
	repo := strings.Join(append(reversed, components[1:]...), "_")
	repo = strings.NewReplacer("-", "_", ".", "_").Replace(repo)

	return label{
		repo: repo,
		pkg:  pkg,
		name: defaultLibName,
	}, nil
}

// knownImports are paths which are not static in the vcs package,
// to allow load balancing between actual repos,
// but for our case we only need to break the importpath in a known fashion.
var knownImports = []string{"golang.org/x/", "google.golang.org/", "cloud.google.com/"}

// specialCases looks for matches in knownImports to avoid making a network call.
func specialCases(importpath string) *vcs.RepoRoot {
	for _, known := range knownImports {
		if strings.HasPrefix(importpath, known) {
			l := len(known)
			if idx := strings.Index(importpath[l:], "/"); idx != -1 {
				return &vcs.RepoRoot{
					Root: importpath[:l+idx],
				}
			}
			return &vcs.RepoRoot{
				Root: importpath,
			}
		}
	}
	return nil
}
