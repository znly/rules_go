// Package workspace provides functions to locate and modify a bazel WORKSPACE file.
package workspace

import (
	"os"
	"path/filepath"
)

const workspaceFile = "WORKSPACE"

// Find
func Find(dir string) (string, error) {
	if dir == "" || dir == "/" {
		return "", os.ErrNotExist
	}
	_, err := os.Stat(filepath.Join(dir, workspaceFile))
	if err == nil {
		return dir, nil
	}
	if !os.IsNotExist(err) {
		return "", err
	}
	return Find(filepath.Dir(dir))
}
