package main

import (
	"os"
	"syscall"
)

func main() {
	args := os.Args[1:]
	newArgs := make([]string, 0, len(args))
	for i := 0; i < len(args); i++ {
		arg := args[i]
		if arg == "-buildid" {
			i++
			continue
		}
		newArgs = append(newArgs, arg)
	}
	syscall.Exec(newArgs[0], newArgs, os.Environ())
}
