cmake_minimum_required(VERSION 3.24)

find_package(Python3 3.11 REQUIRED COMPONENTS Interpreter)
execute_process(
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/scripts/sdk-prefix.py"
    RESULT_VARIABLE cwhip_settings_result
    OUTPUT_VARIABLE cwhip_sdk_prefix
    ERROR_VARIABLE cwhip_settings_error)
if(NOT cwhip_settings_result STREQUAL "0")
    message(FATAL_ERROR "${cwhip_settings_error}")
endif()

if(NOT cwhip_sdk_prefix STREQUAL "")
    unset(Cwhip_DIR CACHE)
    unset(Cwhip_DIR)
    find_package(Cwhip 0.0.2 EXACT CONFIG REQUIRED
        PATHS "${cwhip_sdk_prefix}" NO_DEFAULT_PATH)
else()
    find_package(Cwhip 0.0.2 EXACT CONFIG REQUIRED)
endif()
if(NOT Cwhip_SDK_ABI STREQUAL "numeric-v2")
    message(FATAL_ERROR
        "The selected Cwhip SDK at '${Cwhip_PREFIX}' must provide "
        "Cwhip_SDK_ABI=numeric-v2 (reported '${Cwhip_SDK_ABI}'). "
        "Rebuild and reinstall the numeric-v2 Cwhip SDK, or select it with CWHIP_SDK.")
endif()
if(NOT COMMAND cwhip_apply_application_defaults)
    message(FATAL_ERROR
        "The selected Cwhip SDK at '${Cwhip_PREFIX}' is missing the "
        "application-defaults capability (cwhip_apply_application_defaults()). "
        "Rebuild and reinstall an updated Cwhip SDK at this prefix, or select "
        "an updated SDK with CWHIP_SDK, then rerun configuration.")
endif()
cwhip_apply_application_defaults()

project(cmacros VERSION 1.0 LANGUAGES C)

include(CTest)

set(CWHIP_BIN_DIR "${PROJECT_SOURCE_DIR}/bin" CACHE PATH
    "Directory for project executables")
set(CWHIP_LIB_DIR "${PROJECT_SOURCE_DIR}/lib" CACHE PATH
    "Directory for project libraries and archives")
get_filename_component(CWHIP_BIN_DIR "${CWHIP_BIN_DIR}" ABSOLUTE
    BASE_DIR "${PROJECT_SOURCE_DIR}")
get_filename_component(CWHIP_LIB_DIR "${CWHIP_LIB_DIR}" ABSOLUTE
    BASE_DIR "${PROJECT_SOURCE_DIR}")

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CWHIP_BIN_DIR}")
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY "${CWHIP_LIB_DIR}")
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY "${CWHIP_LIB_DIR}")
foreach(configuration DEBUG RELEASE RELWITHDEBINFO MINSIZEREL)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_${configuration} "${CWHIP_BIN_DIR}")
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY_${configuration} "${CWHIP_LIB_DIR}")
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY_${configuration} "${CWHIP_LIB_DIR}")
endforeach()

if(NOT Cwhip_APPLICATION_OUTPUT_DIRECTORIES)
    message(FATAL_ERROR
        "The selected Cwhip SDK does not support configurable application output directories.")
endif()

# Entry point includes types.cw, processor.cw, conditions.cw, and io.cw from src/.
cwhip_add_program(cmacros
    SOURCE "${PROJECT_SOURCE_DIR}/src/main.cw"
    OUTPUT_DIRECTORY "${CWHIP_BIN_DIR}")
get_target_property(cmacros_executable cmacros CWHIP_EXECUTABLE)
install(PROGRAMS "${cmacros_executable}" DESTINATION bin)

if(BUILD_TESTING)
    add_test(NAME cmacros-sdk-discovery
        COMMAND "${Python3_EXECUTABLE}" "${PROJECT_SOURCE_DIR}/tests/test_sdk_discovery.py"
            "${CMAKE_COMMAND}")
    add_test(NAME cmacros-original-examples
        COMMAND "${Python3_EXECUTABLE}" "${PROJECT_SOURCE_DIR}/examples/run_examples.py"
            "${cmacros_executable}")
    add_test(NAME cmacros-conformance
        COMMAND "${Python3_EXECUTABLE}" "${PROJECT_SOURCE_DIR}/tests/test_cli.py"
            "${cmacros_executable}")
    add_test(NAME cmacros-cwhip-output
        COMMAND "${Python3_EXECUTABLE}" "${PROJECT_SOURCE_DIR}/tests/test_cwhip_output.py"
            "${cmacros_executable}" "${CMAKE_COMMAND}" "${Cwhip_PREFIX}")
    add_test(NAME cmacros-install-relocation
        COMMAND "${Python3_EXECUTABLE}" "${PROJECT_SOURCE_DIR}/tests/test_install.py"
            "${CMAKE_COMMAND}" "${CMAKE_BINARY_DIR}" "$<CONFIG>")
endif()
