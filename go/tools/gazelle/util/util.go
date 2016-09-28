// Package util provides common utilities for operating on
// parsed bazel files.
package util

import (
	bzl "github.com/bazelbuild/buildifier/core"
)

// Get returns the value for the 'name = value' entry in the calls arguments
// or "" if not found.
func Get(name string, c *bzl.CallExpr) string {
	v := GetValue(name, c)
	if v == nil {
		return ""
	}
	return StringValue(v)
}

// Get returns the bzl.Expr on the RHS of a 'name = ?' in the kwargs.
// returns nil if no such key found.
func GetValue(name string, c *bzl.CallExpr) bzl.Expr {
	for _, arg := range c.List {
		kv, ok := arg.(*bzl.BinaryExpr)
		if !ok {
			continue
		}
		if kv.Op != "=" {
			continue
		}
		if Literal(kv.X) == name {
			return kv.Y
		}
	}
	return nil
}

// Literal extracts the Token from the LiteralExpr else returns ""
func Literal(e bzl.Expr) string {
	l, ok := e.(*bzl.LiteralExpr)
	if !ok {
		return ""
	}
	return l.Token
}

// StringValue extracts the quoted StringExpr else ""
func StringValue(e bzl.Expr) string {
	s, ok := e.(*bzl.StringExpr)
	if !ok {
		return ""
	}
	return s.Value
}
