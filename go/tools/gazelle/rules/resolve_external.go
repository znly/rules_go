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
	"fmt"
	"path"
	"strings"

	"golang.org/x/tools/go/vcs"
)

var (
	// repoRootForImportPath is overwritten only in unit test to avoid depending on
	// network communication.
	repoRootForImportPath = vcs.RepoRootForImportPath
)

// ImportPathToBazelRepoName converts a Go import path into a bazel repo name
// following the guidelines in http://bazel.io/docs/be/functions.html#workspace
func ImportPathToBazelRepoName(importpath string) string {
	components := strings.Split(importpath, "/")
	labels := strings.Split(components[0], ".")
	var reversed []string
	for i := range labels {
		l := labels[len(labels)-i-1]
		reversed = append(reversed, l)
	}
	repo := strings.Join(append(reversed, components[1:]...), "_")
	return strings.NewReplacer("-", "_", ".", "_").Replace(repo)
}

type externalResolver struct{}

// resolve resolves "importpath" into a label, assuming that it is a label in an
// external repository. It also assumes that the external repository follows the
// recommended reverse-DNS form of workspace name as described in
// http://bazel.io/docs/be/functions.html#workspace.
func (e externalResolver) resolve(importpath, dir string) (label, error) {
	prefix, err := findCachedRepoRoot(importpath)
	if err != nil {
		return label{}, err
	}
	if prefix == "" {
		r, err := repoRootForImportPath(importpath, false)
		if err != nil {
			repoRootCache[prefix] = repoRootCacheEntry{prefix: importpath, err: err}
			return label{}, err
		}
		prefix = r.Root
		repoRootCache[prefix] = repoRootCacheEntry{prefix: prefix}
	}

	var pkg string
	if importpath != prefix {
		pkg = strings.TrimPrefix(importpath, prefix+"/")
	}

	return label{
		repo: ImportPathToBazelRepoName(prefix),
		pkg:  pkg,
		name: defaultLibName,
	}, nil
}

func findCachedRepoRoot(importpath string) (string, error) {
	// subpaths contains slices of importpath with components removed. For
	// example:
	//   golang.org/x/tools/go/vcs
	//   golang.org/x/tools/go
	//   golang.org/x/tools
	subpaths := []string{importpath}

	for {
		if e, ok := repoRootCache[importpath]; ok {
			if e.missing >= len(subpaths) {
				return "", fmt.Errorf("import path %q is shorter than the known prefix %q", importpath, e.prefix)
			}
			// Cache hit. Restore n components of the import path to get the
			// repository root.
			return subpaths[len(subpaths)-e.missing-1], e.err
		}

		// Prefix not found. Remove the last component and try again.
		importpath = path.Dir(importpath)
		if importpath == "." || importpath == "/" {
			// Cache miss.
			return "", nil
		}
		subpaths = append(subpaths, importpath)
	}
}

type repoRootCacheEntry struct {
	// prefix is part of an import path that corresponds to a repository root,
	// possibly with some components missing.
	prefix string

	// missing is the number of components missing from prefix to make a full
	// repository root prefix. For most repositories, this is 0, meaning the
	// prefix is the full path to the repository root. For some well-known sites,
	// this is non-zero. For example, we can store the prefix "github.com" with
	// missing as 2, since GitHub always has two path components before the
	// actual repository.
	missing int

	// err is an error we encountered when resolving this prefix. This is used
	// for caching negative results.
	err error
}

// repoRootCache stores the results (both positive and negative) of
// repoRootForImportPath. It is initially populated with some well-known sites.
// externalResolver.resolve will add entries as it looks up new packages.
var repoRootCache map[string]repoRootCacheEntry

// resetRepoRootCache creates repoRootCache and adds special cases. It is
// called during initialization and in tests.
func resetRepoRootCache() {
	repoRootCache = make(map[string]repoRootCacheEntry)
	for _, e := range []repoRootCacheEntry{
		{prefix: "golang.org/x", missing: 1},
		{prefix: "google.golang.org", missing: 1},
		{prefix: "cloud.google.com", missing: 1},
		{prefix: "github.com", missing: 2},
	} {
		repoRootCache[e.prefix] = e
	}
}

func init() {
	resetRepoRootCache()
}
