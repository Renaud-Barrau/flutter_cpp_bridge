#include <cstdio>
#include "flutter_cpp_bridge/service_helpers.h"

FCB_EXPORT_STANDALONE_NOOP()

FCB_EXPORT void hello()
{
    printf("Hello from libalone!\n");
    fflush(stdout);
}
