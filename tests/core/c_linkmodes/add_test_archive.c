#include <assert.h>
#include "tests/core/c_linkmodes/adder_archive.h"

int main(int argc, char** argv) {
    assert(GoAdd(42, 42) == 84);
    return 0;
}
