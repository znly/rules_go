#include <assert.h>
#include "adder_shared.h"

int main(int argc, char** argv) {
    assert(GoAdd(42, 42) == 84);
    return 0;
}
