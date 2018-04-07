#include "add.h"

auto add_cpp(int a, int b) {
    return a + b;
}

int add(int a, int b) {
    return add_cpp(a, b);
}

int add_lambda(int a, int b) {
    auto doadd = [](int a, int b) { return a + b; };
    return doadd(a, b);
}
