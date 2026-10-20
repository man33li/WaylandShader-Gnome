cmake_minimum_required(VERSION 3.25)
project(WaylandShaderGNOME VERSION 0.1.0 LANGUAGES C)

include(GNUInstallDirs)
find_program(ODIN odin REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(MUTTER REQUIRED IMPORTED_TARGET libmutter-18)
pkg_check_modules(NATIVE_LIBS REQUIRED IMPORTED_TARGET libmutter-18 mutter-clutter-18 mutter-cogl-18 mutter-mtk-18 graphene-gobject-1.0 egl gio-2.0)
pkg_check_modules(GTK3 REQUIRED gtk+-3.0)
if(MUTTER_VERSION VERSION_LESS "50" OR MUTTER_VERSION VERSION_GREATER_EQUAL "51")
    message(FATAL_ERROR "This native GNOME backend targets GNOME 50 / Mutter ABI 18; rebuild and port for a different major release.")
endif()
find_path(LIBRASHADER_INCLUDE_DIR librashader.h PATH_SUFFIXES librashader REQUIRED)
find_library(LIBRASHADER_LIBRARY waylandshader-rashader REQUIRED)
get_filename_component(LIBRASHADER_LIBRARY_DIR "${LIBRASHADER_LIBRARY}" DIRECTORY)
find_program(G_IR_SCANNER g-ir-scanner REQUIRED)
find_program(G_IR_COMPILER g-ir-compiler REQUIRED)
# The module lives inside the extension, not in the package's lib directory.
execute_process(COMMAND ${G_IR_SCANNER} --help OUTPUT_VARIABLE GIR_SCANNER_HELP COMMAND_ERROR_IS_FATAL ANY)
if(GIR_SCANNER_HELP MATCHES "--fallback-library-path")
    set(GIR_RELOCATABLE_OPTION "--fallback-library-path=")
endif()
find_program(GLIB_COMPILE_SCHEMAS glib-compile-schemas REQUIRED)
pkg_get_variable(MUTTER_PREFIX libmutter-18 prefix)
set(MUTTER_GIR_DIR "${MUTTER_PREFIX}/lib/mutter-18")

set(ODIN_FLAGS -o:speed -vet -strict-style -define:GL_DEBUG=false)
set(ODIN_LIBRARY_DIRS ${NATIVE_LIBS_LIBRARY_DIRS} ${GTK3_LIBRARY_DIRS} "${LIBRASHADER_LIBRARY_DIR}")
list(REMOVE_DUPLICATES ODIN_LIBRARY_DIRS)
# Odin uses -l:/absolute/path for vendor archives; retain its root search through Nix wrappers.
set(ODIN_LDFLAGS "-pthread -Wl,--library-path=/")
foreach(dir IN LISTS ODIN_LIBRARY_DIRS)
    string(APPEND ODIN_LDFLAGS " -L${dir} -Wl,-rpath,${dir}")
endforeach()
set(NATIVE_LDFLAGS "${ODIN_LDFLAGS} -Wl,--no-undefined -Wl,-soname,libwaylandshader-gnome.so -Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/native/exports.map")
add_library(gnome_abi_check OBJECT native/abi-check.c)
target_link_libraries(gnome_abi_check PRIVATE PkgConfig::NATIVE_LIBS)
target_include_directories(gnome_abi_check PRIVATE ${LIBRASHADER_INCLUDE_DIR})

target_compile_definitions(gnome_abi_check PRIVATE LIBRA_RUNTIME_OPENGL)
file(GLOB_RECURSE ODIN_SOURCES CONFIGURE_DEPENDS native/*.odin runtime/*.odin common/*.odin glib/*.odin controller/*.odin)
add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/libwaylandshader-gnome.so"
    COMMAND ${ODIN} build ${CMAKE_CURRENT_SOURCE_DIR}/native -build-mode:dll
        -out:${CMAKE_CURRENT_BINARY_DIR}/libwaylandshader-gnome.so ${ODIN_FLAGS}
        "-extra-linker-flags:${NATIVE_LDFLAGS}"
    DEPENDS gnome_abi_check ${ODIN_SOURCES} native/exports.map VERBATIM)
add_custom_target(gnome_native ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/libwaylandshader-gnome.so")

function(odin_executable target package output)
    add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/${output}"
        COMMAND ${ODIN} build ${CMAKE_CURRENT_SOURCE_DIR}/${package}
            -out:${CMAKE_CURRENT_BINARY_DIR}/${output} ${ODIN_FLAGS}
            "-extra-linker-flags:${ODIN_LDFLAGS}"
        DEPENDS ${ODIN_SOURCES} ${ARGN} VERBATIM)
    add_custom_target(${target} ALL DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/${output}")
endfunction()
odin_executable(gnome_ctl controller/ctl waylandshader-gnomectl)
odin_executable(gnome_gui controller/gui waylandshader-gnome-controller controller/gui/controller.ui)

set(GIR_FILE "${CMAKE_CURRENT_BINARY_DIR}/WaylandShader-1.0.gir")
set(TYPELIB_FILE "${CMAKE_CURRENT_BINARY_DIR}/WaylandShader-1.0.typelib")
add_custom_command(
    OUTPUT ${GIR_FILE}
    COMMAND ${CMAKE_COMMAND} -E env
        "LD_LIBRARY_PATH=${CMAKE_CURRENT_BINARY_DIR}:$ENV{LD_LIBRARY_PATH}"
        "GI_TYPELIB_PATH=${MUTTER_GIR_DIR}:$ENV{GI_TYPELIB_PATH}"
        ${G_IR_SCANNER} --quiet --warn-all --no-libtool ${GIR_RELOCATABLE_OPTION}
        --namespace=WaylandShader --nsversion=1.0
        --identifier-prefix=WaylandShader --symbol-prefix=wayland_shader
        --include=GObject-2.0 --include=Clutter-18
        --add-include-path=${MUTTER_GIR_DIR}
        --pkg=libmutter-18
        --library=waylandshader-gnome
        --library-path=${CMAKE_CURRENT_BINARY_DIR}
        --c-include=waylandshader-effect.h
        --output=${GIR_FILE}
        ${CMAKE_CURRENT_SOURCE_DIR}/native/waylandshader-effect.h
    DEPENDS gnome_native native/waylandshader-effect.h
    VERBATIM)
add_custom_command(
    OUTPUT ${TYPELIB_FILE}
    COMMAND ${G_IR_COMPILER} --includedir=${MUTTER_GIR_DIR} ${GIR_FILE} --output=${TYPELIB_FILE}
    DEPENDS ${GIR_FILE}
    VERBATIM)
add_custom_target(gnome_introspection ALL DEPENDS ${TYPELIB_FILE})

option(WAYLANDSHADER_BUILD_TESTS "Build GNOME regressions" OFF)
if(WAYLANDSHADER_BUILD_TESTS)
    enable_testing()
    find_program(GJS gjs REQUIRED)
    add_test(NAME gnome_effect_lifecycle
        COMMAND ${CMAKE_COMMAND} -E env
            "GI_TYPELIB_PATH=${MUTTER_GIR_DIR}:$ENV{GI_TYPELIB_PATH}"
            ${GJS} -m ${CMAKE_CURRENT_SOURCE_DIR}/tests/effect-lifecycle.js
            ${CMAKE_CURRENT_BINARY_DIR}
            ${CMAKE_CURRENT_SOURCE_DIR}/../tests/fixtures/temporal.slangp)
    foreach(test recent_presets native_contract)
        string(REPLACE "_" "-" script "${test}")
        add_test(NAME gnome_${test}
            COMMAND ${CMAKE_COMMAND} -E env
                "GI_TYPELIB_PATH=${MUTTER_GIR_DIR}:$ENV{GI_TYPELIB_PATH}"
                ${GJS} -m ${CMAKE_CURRENT_SOURCE_DIR}/tests/${script}.js ${CMAKE_CURRENT_BINARY_DIR})
    endforeach()
    set_tests_properties(gnome_effect_lifecycle gnome_recent_presets gnome_native_contract PROPERTIES TIMEOUT 10)
    foreach(package common native controller/client controller/ctl controller/gui)
        get_filename_component(name "${package}" NAME)
        add_test(NAME gnome_${name}_units COMMAND ${ODIN} test ${CMAKE_CURRENT_SOURCE_DIR}/${package}
            -out:${CMAKE_CURRENT_BINARY_DIR}/${name}-units ${ODIN_FLAGS} -define:ODIN_TEST_THREADS=1
            "-extra-linker-flags:${ODIN_LDFLAGS}")
        set_tests_properties(gnome_${name}_units PROPERTIES WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
    endforeach()
    odin_executable(gnome_gltest runtime/gltest shader-runtime-gltest)
    foreach(test gnome_shader_runtime_gl gnome_shader_runtime_gl33)
        add_test(NAME ${test} COMMAND ${CMAKE_CURRENT_BINARY_DIR}/shader-runtime-gltest ${CMAKE_CURRENT_SOURCE_DIR}/../tests/fixtures)
        set_tests_properties(${test} PROPERTIES SKIP_RETURN_CODE 77 TIMEOUT 120)
    endforeach()
    set_tests_properties(gnome_shader_runtime_gl33 PROPERTIES ENVIRONMENT "MESA_GL_VERSION_OVERRIDE=3.3")
    add_test(NAME gnome_cli_golden COMMAND sh ${CMAKE_CURRENT_SOURCE_DIR}/tests/cli-golden.sh check ${CMAKE_CURRENT_BINARY_DIR}/waylandshader-gnomectl)
    add_test(NAME gnome_elf COMMAND sh ${CMAKE_CURRENT_SOURCE_DIR}/tests/elf-check.sh
        ${CMAKE_CURRENT_BINARY_DIR}/libwaylandshader-gnome.so
        ${CMAKE_CURRENT_BINARY_DIR}/waylandshader-gnomectl
        ${CMAKE_CURRENT_BINARY_DIR}/waylandshader-gnome-controller)
    add_test(NAME gnome_ban COMMAND sh ${CMAKE_CURRENT_SOURCE_DIR}/tests/ban-check.sh ${CMAKE_CURRENT_SOURCE_DIR})
endif()

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

install(FILES "${CMAKE_CURRENT_BINARY_DIR}/libwaylandshader-gnome.so" DESTINATION "${EXTENSION_DIR}/native")
install(FILES ${GIR_FILE} ${TYPELIB_FILE} DESTINATION "${EXTENSION_DIR}/native")
install(FILES extension/metadata.json extension/extension.js DESTINATION "${EXTENSION_DIR}")
install(FILES extension/schemas/org.gnome.shell.extensions.waylandshader.gschema.xml
    "${CMAKE_CURRENT_BINARY_DIR}/schemas/gschemas.compiled" DESTINATION "${EXTENSION_DIR}/schemas")
install(PROGRAMS "${CMAKE_CURRENT_BINARY_DIR}/waylandshader-gnome-controller" "${CMAKE_CURRENT_BINARY_DIR}/waylandshader-gnomectl" DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES org.waylandshader.GnomeController.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
