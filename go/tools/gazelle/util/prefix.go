package util

import (
	"errors"
	"fmt"
	"io/ioutil"
	"path/filepath"

	bzl "github.com/bazelbuild/buildifier/core"
)

// GoPrefix loads the BUILD file from the given directory
// and returns the contents of the go_prefix rule
func GoPrefix(dir string) (string, error) {
	p := filepath.Join(dir, "BUILD")
	b, err := ioutil.ReadFile(p)
	if err != nil {
		return "", err
	}
	f, err := bzl.Parse(p, b)
	if err != nil {
		return "", err
	}
	for _, s := range f.Stmt {
		c, ok := s.(*bzl.CallExpr)
		if !ok {
			continue
		}
		l := Literal(c.X)
		if l != "go_prefix" {
			continue
		}
		if len(c.List) != 1 {
			return "", fmt.Errorf("found go_prefix(%v) with too many args", c.List)
		}
		v := StringValue(c.List[0])
		if v == "" {
			return "", fmt.Errorf("found go_prefix(%v) which is not a string", c.List)
		}
		return v, nil
	}
	return "", errors.New("no go_prefix found in root BUILD file")
}
