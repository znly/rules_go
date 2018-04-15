#include "add.h"

#if !defined(RULES_GO_C) || defined(RULES_GO_CPP)
#error This is a C file, only RULES_GO_C should be defined.
#endif

int add_c(int a, int b) {
    return a + b;
}
