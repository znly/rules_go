package wspace

import (
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"

	bzl "github.com/bazelbuild/buildifier/core"
	"github.com/bazelbuild/rules_go/go/tools/gazelle/rules"
	"github.com/bazelbuild/rules_go/go/tools/gazelle/util"
)

const newGoRepository = "new_go_repository"

var ruleSet = map[string]bool{
	"go_repository": true,
	newGoRepository: true,
}

type Workspace struct {
	f        *bzl.File
	existing map[string]string // existing remote deps by importpath
}

func Load(filename string) (*Workspace, error) {
	fi, err := os.Stat(filename)
	if err != nil {
		return nil, err
	}
	if fi.IsDir() {
		filename = filepath.Join(filename, "WORKSPACE")
	}
	b, err := ioutil.ReadFile(filename)
	if err != nil {
		return nil, err
	}
	f, err := bzl.Parse(filename, b)
	if err != nil {
		return nil, err
	}
	ex, err := existing(f)
	if err != nil {
		return nil, err
	}
	return &Workspace{f, ex}, nil
}

// Notify implements rules.Notifier
func (w *Workspace) Notify(importpath, repoName string) {

}

// Printer returns a rules.Notifier that just prints out any new dependencies.
func (w *Workspace) Printer() rules.Notifier {
	return &printer{w.existing}
}

type printer struct {
	seen map[string]string // existing remote deps by importpath
}

func (p *printer) Notify(importpath, repoName string) {
	if _, ok := p.seen[importpath]; ok {
		return
	}
	p.seen[importpath] = repoName
	fmt.Printf("new_go_repository(name = %q, importpath = %q)\n", repoName, importpath)
}

func existing(f *bzl.File) (map[string]string, error) {
	res := make(map[string]string)
	for _, s := range f.Stmt {
		c, ok := s.(*bzl.CallExpr)
		if !ok {
			continue
		}
		if !ruleSet[util.Literal(c.X)] {
			continue
		}
		i := util.Get("importpath", c)
		name := util.Get("name", c)
		if i == "" || name == "" {
			return nil, fmt.Errorf("go_repository without name+importpath: %v", c)
		}
		res[i] = name
	}
	return res, nil
}
