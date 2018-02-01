package main

import "C"

//export GoAdd
func GoAdd(a, b int) int {
	return a + b
}

func main() {}
