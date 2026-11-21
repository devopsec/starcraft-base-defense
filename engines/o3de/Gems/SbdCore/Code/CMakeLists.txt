# Repository root is four levels above this file: engines/o3de/Gems/SbdCore/Code
get_filename_component(SBD_REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../../../.." ABSOLUTE)
set(SBD_CORE_DIR "${SBD_REPO_ROOT}/core")

# Prebuilt Zig core (core/build.sh) imported as a shared library.
add_library(SbdCore.Native SHARED IMPORTED GLOBAL)
if(WIN32)
    set_target_properties(SbdCore.Native PROPERTIES
        IMPORTED_IMPLIB "${SBD_CORE_DIR}/zig-out/x86_64-windows/sbd_core.lib"
        IMPORTED_LOCATION "${SBD_CORE_DIR}/zig-out/x86_64-windows/sbd_core.dll")
elseif(ANDROID)
    set_target_properties(SbdCore.Native PROPERTIES
        IMPORTED_LOCATION "${SBD_CORE_DIR}/zig-out/aarch64-android/libsbd_core.so")
else()
    set_target_properties(SbdCore.Native PROPERTIES
        IMPORTED_LOCATION "${SBD_CORE_DIR}/zig-out/x86_64-linux/libsbd_core.so")
endif()
target_include_directories(SbdCore.Native INTERFACE "${SBD_CORE_DIR}/include")

ly_add_target(
    NAME SbdCore.Static STATIC
    NAMESPACE Gem
    FILES_CMAKE sbdcore_files.cmake
    INCLUDE_DIRECTORIES PUBLIC Source
    BUILD_DEPENDENCIES PUBLIC AZ::AzCore AZ::AzFramework
    RUNTIME_DEPENDENCIES SbdCore.Native
)
target_link_libraries(SbdCore.Static PUBLIC SbdCore.Native)

ly_add_target(
    NAME SbdCore ${PAL_TRAIT_MONOLITHIC_DRIVEN_MODULE_TYPE}
    NAMESPACE Gem
    FILES_CMAKE sbdcore_shared_files.cmake
    BUILD_DEPENDENCIES PRIVATE Gem::SbdCore.Static
)
