// C APIs used by the native backend, translated to Zig by build.zig (addTranslateC).
#define SDL_DISABLE_OLD_NAMES
#include <SDL3/SDL.h>

#include <webgpu/webgpu.h>
#include <webgpu/wgpu.h>

// The OpenXR loader is optional and loaded at runtime (xr.zig), so only types are needed here.
#define XR_NO_PROTOTYPES
#include <openxr/openxr.h>
