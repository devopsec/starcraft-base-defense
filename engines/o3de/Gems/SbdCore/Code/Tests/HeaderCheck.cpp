#include "sbd.h"

static_assert(sizeof(sbd_event) > 0, "sbd.h must be usable from C++");

int main()
{
    sbd_config config;
    sbd_config_default(&config);
    return 0;
}
