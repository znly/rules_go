package objc

/*
#import "add.h"
*/
import "C"

func Add(a, b int32) int32 {
	return int32(C.add(C.int(a), C.int(b)))
}

func AddLambda(a, b int32) int32 {
	return int32(C.add_lambda(C.int(a), C.int(b)))
}
