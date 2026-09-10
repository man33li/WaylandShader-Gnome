cmake_minimum_required(VERSION 3.25)
project(WaylandShaderGNOME VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_AUTOMOC ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE)
include(GNUInstallDirs)

find_package(Qt6 6.10 REQUIRED COMPONENTS Core Gui Widgets DBus)
find_package(Threads REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(MUTTER REQUIRED IMPORTED_TARGET libmutter-18)
pkg_check_modules(EPOXY REQUIRED IMPORTED_TARGET epoxy)
if(MUTTER_VERSION VERSION_LESS "50" OR MUTTER_VERSION VERSION_GREATER_EQUAL "51")
    message(FATAL_ERROR "This native GNOME backend targets GNOME 50 / Mutter ABI 18; rebuild and port for a different major release.")
endif()
find_path(LIBRASHADER_INCLUDE_DIR librashader.h PATH_SUFFIXES librashader REQUIRED)
find_library(LIBRASHADER_LIBRARY waylandshader-rashader REQUIRED)
find_program(G_IR_SCANNER g-ir-scanner REQUIRED)
find_program(G_IR_COMPILER g-ir-compiler REQUIRED)
# Nix's scanner otherwise bakes $out/lib into GIR, but this module lives inside
# the extension and is loaded through its explicitly registered library path.
execute_process(COMMAND ${G_IR_SCANNER} --help OUTPUT_VARIABLE GIR_SCANNER_HELP COMMAND_ERROR_IS_FATAL ANY)
if(GIR_SCANNER_HELP MATCHES "--fallback-library-path")
    set(GIR_RELOCATABLE_OPTION "--fallback-library-path=")
endif()
find_program(GLIB_COMPILE_SCHEMAS glib-compile-schemas REQUIRED)
pkg_get_variable(MUTTER_PREFIX libmutter-18 prefix)
set(MUTTER_GIR_DIR "${MUTTER_PREFIX}/lib/mutter-18")

add_library(gnome_shader_runtime STATIC ../src/shader_runtime.cpp)
set_target_properties(gnome_shader_runtime PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(gnome_shader_runtime PUBLIC ../src PRIVATE ${LIBRASHADER_INCLUDE_DIR})
target_link_libraries(gnome_shader_runtime PUBLIC Qt6::Core PkgConfig::EPOXY PRIVATE ${LIBRASHADER_LIBRARY})

# Mutter 50's C SDK forward-declares an enum before its definition, which is
# invalid C++. Move that unchanged definition in build-local header copies;
# the installed SDK and the compositor's ABI remain untouched.
find_path(CLUTTER_SDK_INCLUDE_DIR clutter/clutter-types.h HINTS ${MUTTER_INCLUDE_DIRS} REQUIRED)
file(READ "${CLUTTER_SDK_INCLUDE_DIR}/clutter/clutter-types.h" CLUTTER_TYPES_HEADER)
file(READ "${CLUTTER_SDK_INCLUDE_DIR}/clutter/clutter-paint-context.h" CLUTTER_PAINT_HEADER)
string(REGEX MATCH "typedef enum _ClutterPaintFlag[ \t]+ClutterPaintFlag;" CLUTTER_FLAG_FORWARD "${CLUTTER_TYPES_HEADER}")
if(CLUTTER_FLAG_FORWARD)
    string(REGEX MATCH "typedef enum _ClutterPaintFlag[\n\r\t ]*\\{[^}]+\\} ClutterPaintFlag;"
        CLUTTER_FLAG_DEFINITION "${CLUTTER_PAINT_HEADER}")
    if(NOT CLUTTER_FLAG_DEFINITION)
        message(FATAL_ERROR "Mutter's ClutterPaintFlag layout changed; update the C++ SDK integration.")
    endif()
    string(REPLACE "${CLUTTER_FLAG_FORWARD}" "${CLUTTER_FLAG_DEFINITION}" CLUTTER_TYPES_HEADER "${CLUTTER_TYPES_HEADER}")
    string(REPLACE "${CLUTTER_FLAG_DEFINITION}" "" CLUTTER_PAINT_HEADER "${CLUTTER_PAINT_HEADER}")
    file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/mutter-cxx/clutter")
    file(CONFIGURE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/mutter-cxx/clutter/clutter-types.h" CONTENT "${CLUTTER_TYPES_HEADER}" @ONLY)
    file(CONFIGURE OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/mutter-cxx/clutter/clutter-paint-context.h" CONTENT "${CLUTTER_PAINT_HEADER}" @ONLY)
endif()

add_library(waylandshader_gnome SHARED native/waylandshader-effect.cpp)
set_target_properties(waylandshader_gnome PROPERTIES OUTPUT_NAME waylandshader-gnome)
target_compile_definitions(waylandshader_gnome PRIVATE QT_NO_KEYWORDS)
target_include_directories(waylandshader_gnome PUBLIC native)
if(CLUTTER_FLAG_FORWARD)
    target_include_directories(waylandshader_gnome BEFORE PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/mutter-cxx")
endif()
target_link_libraries(waylandshader_gnome PRIVATE gnome_shader_runtime PkgConfig::MUTTER Threads::Threads)
target_link_options(waylandshader_gnome PRIVATE -Wl,--no-undefined)

set(GIR_FILE "${CMAKE_CURRENT_BINARY_DIR}/WaylandShader-1.0.gir")
set(TYPELIB_FILE "${CMAKE_CURRENT_BINARY_DIR}/WaylandShader-1.0.typelib")
add_custom_command(
    OUTPUT ${GIR_FILE}
    COMMAND ${CMAKE_COMMAND} -E env
        "LD_LIBRARY_PATH=$<TARGET_FILE_DIR:waylandshader_gnome>:$ENV{LD_LIBRARY_PATH}"
        "GI_TYPELIB_PATH=${MUTTER_GIR_DIR}:$ENV{GI_TYPELIB_PATH}"
        ${G_IR_SCANNER} --quiet --warn-all --no-libtool ${GIR_RELOCATABLE_OPTION}
        --namespace=WaylandShader --nsversion=1.0
        --identifier-prefix=WaylandShader --symbol-prefix=wayland_shader
        --include=GObject-2.0 --include=Clutter-18
        --add-include-path=${MUTTER_GIR_DIR}
        --pkg=libmutter-18
        --library=waylandshader-gnome
        --library-path=$<TARGET_FILE_DIR:waylandshader_gnome>
        --c-include=waylandshader-effect.h
        --output=${GIR_FILE}
        ${CMAKE_CURRENT_SOURCE_DIR}/native/waylandshader-effect.h
    DEPENDS waylandshader_gnome native/waylandshader-effect.h
    VERBATIM)
add_custom_command(
    OUTPUT ${TYPELIB_FILE}
    COMMAND ${G_IR_COMPILER} --includedir=${MUTTER_GIR_DIR} ${GIR_FILE} --output=${TYPELIB_FILE}
    DEPENDS ${GIR_FILE}
    VERBATIM)
add_custom_target(gnome_introspection ALL DEPENDS ${TYPELIB_FILE})

option(WAYLANDSHADER_BUILD_TESTS "Build GNOME effect lifecycle regressions" OFF)
if(WAYLANDSHADER_BUILD_TESTS)
    enable_testing()
    find_program(GJS gjs REQUIRED)
    add_test(NAME gnome_effect_lifecycle
        COMMAND ${CMAKE_COMMAND} -E env
            "GI_TYPELIB_PATH=${MUTTER_GIR_DIR}:$ENV{GI_TYPELIB_PATH}"
            ${GJS} -m ${CMAKE_CURRENT_SOURCE_DIR}/tests/effect-lifecycle.js
            $<TARGET_FILE_DIR:waylandshader_gnome>
            ${CMAKE_CURRENT_SOURCE_DIR}/../tests/fixtures/temporal.slangp)
    set_tests_properties(gnome_effect_lifecycle PROPERTIES TIMEOUT 10)
endif()

add_library(gnome_controller_client STATIC ../src/controller_client.cpp)
target_include_directories(gnome_controller_client PUBLIC ../src)
target_compile_definitions(gnome_controller_client PUBLIC WAYLANDSHADER_GNOME)
target_link_libraries(gnome_controller_client PUBLIC Qt6::Core Qt6::DBus)
add_executable(waylandshader_gnome_controller ../src/controller_main.cpp)
set_target_properties(waylandshader_gnome_controller PROPERTIES OUTPUT_NAME waylandshader-gnome-controller)
target_link_libraries(waylandshader_gnome_controller PRIVATE gnome_controller_client Qt6::Widgets)
add_executable(waylandshader_gnomectl ../src/ctl_main.cpp)
set_target_properties(waylandshader_gnomectl PROPERTIES OUTPUT_NAME waylandshader-gnomectl)
target_link_libraries(waylandshader_gnomectl PRIVATE gnome_controller_client)

set(EXTENSION_UUID "waylandshader@man33li.github.com")
set(EXTENSION_DIR "${CMAKE_INSTALL_DATADIR}/gnome-shell/extensions/${EXTENSION_UUID}")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/schemas")
configure_file(extension/schemas/org.gnome.shell.extensions.waylandshader.gschema.xml
    schemas/org.gnome.shell.extensions.waylandshader.gschema.xml COPYONLY)
add_custom_command(
    OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/schemas/gschemas.compiled"
    COMMAND ${GLIB_COMPILE_SCHEMAS} --strict "${CMAKE_CURRENT_BINARY_DIR}/schemas"
    DEPENDS extension/schemas/org.gnome.shell.extensions.waylandshader.gschema.xml
    VERBATIM)
add_custom_target(gnome_schemas ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/schemas/gschemas.compiled")

install(TARGETS waylandshader_gnome LIBRARY DESTINATION "${EXTENSION_DIR}/native")
install(FILES ${GIR_FILE} ${TYPELIB_FILE} DESTINATION "${EXTENSION_DIR}/native")
install(FILES extension/metadata.json extension/extension.js DESTINATION "${EXTENSION_DIR}")
install(FILES extension/schemas/org.gnome.shell.extensions.waylandshader.gschema.xml
    "${CMAKE_CURRENT_BINARY_DIR}/schemas/gschemas.compiled" DESTINATION "${EXTENSION_DIR}/schemas")
install(TARGETS waylandshader_gnome_controller waylandshader_gnomectl RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.waylandshader.GnomeController.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
