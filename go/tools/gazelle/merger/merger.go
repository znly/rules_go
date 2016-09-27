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

// Package merger provides methods for merging parsed BUILD files.
package merger

import (
	"fmt"
	"io/ioutil"
	"os"
	"sort"

	bzl "github.com/bazelbuild/buildifier/core"
)

var (
	mergeableFields = map[string]bool{
		"srcs": true,
		"deps": true,
	}
)

// MergeWithExisting looks for an existing BUILD file at file.Path
// loads it, and attempts to merge elements of newfile into it.
// returns newfile, nil if FileNotExists
func MergeWithExisting(newfile *bzl.File) (*bzl.File, error) {
	b, err := ioutil.ReadFile(newfile.Path)
	if err != nil {
		if os.IsNotExist(err) {
			return newfile, nil
		}
		return nil, err
	}
	f, err := bzl.Parse(newfile.Path, b)
	if err != nil {
		return nil, err
	}

	var newStmt []bzl.Expr
	for _, s := range newfile.Stmt {
		c, ok := s.(*bzl.CallExpr)
		if !ok {
			return nil, fmt.Errorf("got %v expected only CallExpr in %q", s, newfile.Path)
		}
		other, err := match(f, c)
		if err != nil {
			return nil, err
		}
		if other == nil {
			newStmt = append(newStmt, c)
			continue
		}
		if literal(c.X) == "load" {
			mergeLoad(c, other, f)
		} else {
			merge(c, other)
		}
	}
	f.Stmt = append(f.Stmt, newStmt...)
	return f, nil
}

// merge takes new info from src and merges into dest.
// pre: these calls are the same X and 'name'
func merge(src, dest *bzl.CallExpr) {
	for _, item := range src.List {
		nkv, ok := item.(*bzl.BinaryExpr)
		if !ok {
			continue
		}
		k := literal(nkv.X)
		if !mergeableFields[k] {
			continue
		}
		// TODO(pmbethe09): allow '# keep' on src files.
		replace(dest, nkv)
	}
}

func replace(dest *bzl.CallExpr, update *bzl.BinaryExpr) {
	k := literal(update.X)
	for i, item := range dest.List {
		okv, ok := item.(*bzl.BinaryExpr)
		if !ok {
			continue
		}
		if k == literal(okv.X) {
			dest.List[i] = update
			return
		}
	}
	dest.List = append(dest.List, update)
}

func mergeLoad(src, dest *bzl.CallExpr, oldfile *bzl.File) {
	vals := make(map[string]bzl.Expr)
	for _, v := range src.List[1:] {
		vals[stringValue(v)] = v
	}
	for _, v := range dest.List[1:] {
		rule := stringValue(v)
		if _, ok := vals[rule]; !ok && ruleUsed(rule, oldfile) {
			vals[rule] = v
		}
	}
	keys := make([]string, 0, len(vals))
	for k := range vals {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	dest.List = dest.List[:1]
	for _, k := range keys {
		dest.List = append(dest.List, vals[k])
	}
}

func ruleUsed(rule string, oldfile *bzl.File) bool {
	for _, s := range oldfile.Stmt {
		c, ok := s.(*bzl.CallExpr)
		if !ok {
			continue
		}
		if rule == literal(c) {
			return true
		}
	}
	return false
}

// match looks for the matching CallExpr in f using X and name
// i.e. two 'go_library(name = "foo", ...)' are considered matches
// despite the values of the other fields.
// exception: if c is a 'load' statement, the match is done on the first value.
func match(f *bzl.File, c *bzl.CallExpr) (*bzl.CallExpr, error) {
	x := literal(c.X)
	if x == "" {
		return nil, fmt.Errorf("expected LiteralExpr, got; %v", c)
	}
	var m matcher
	if x == "load" {
		if len(c.List) == 0 {
			return nil, nil
		}
		m = &loadMatcher{stringValue(c.List[0])}
	} else {
		m = &nameMatcher{x, get("name", c)}
	}
	for _, s := range f.Stmt {
		other, ok := s.(*bzl.CallExpr)
		if !ok {
			continue
		}
		if m.match(other) {
			return other, nil
		}
	}
	return nil, nil
}

type matcher interface {
	match(c *bzl.CallExpr) bool
}

type nameMatcher struct {
	x, name string
}

func (m *nameMatcher) match(c *bzl.CallExpr) bool {
	return m.x == literal(c.X) && m.name == get("name", c)
}

type loadMatcher struct {
	load string
}

func (m *loadMatcher) match(c *bzl.CallExpr) bool {
	return literal(c.X) == "load" && len(c.List) > 0 && m.load == stringValue(c.List[0])
}

// get returns the value for the 'name = value' entry in the calls arguments
// or "" if not found.
func get(name string, c *bzl.CallExpr) string {
	v := getValue(name, c)
	if v == nil {
		return ""
	}
	return stringValue(v)
}

func getValue(name string, c *bzl.CallExpr) bzl.Expr {
	for _, arg := range c.List {
		kv, ok := arg.(*bzl.BinaryExpr)
		if !ok {
			continue
		}
		if kv.Op != "=" {
			continue
		}
		if literal(kv.X) == name {
			return kv.Y
		}
	}
	return nil
}

func literal(e bzl.Expr) string {
	l, ok := e.(*bzl.LiteralExpr)
	if !ok {
		return ""
	}
	return l.Token
}

func stringValue(e bzl.Expr) string {
	s, ok := e.(*bzl.StringExpr)
	if !ok {
		return ""
	}
	return s.Value
}
