// Compile-time ABI checks: the C++ view of sbd.h must match the Zig core and the C# binding.
#pragma once

#include "sbd.h"

static_assert(sizeof(sbd_vec3) == 12, "sbd_vec3 layout");
static_assert(sizeof(sbd_config) == 48, "sbd_config layout");
static_assert(sizeof(sbd_cmd) == 24, "sbd_cmd layout");
static_assert(sizeof(sbd_event) == 28, "sbd_event layout");
static_assert(SBD_ABI_VERSION == 1u, "sbd_core ABI version");
