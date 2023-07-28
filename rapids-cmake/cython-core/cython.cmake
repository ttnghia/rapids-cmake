# =============================================================================
# Copyright (c) 2023 CORPORATION.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
# in compliance with the License. You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed under the License
# is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
# or implied. See the License for the specific language governing permissions and limitations under
# the License.
# =============================================================================

include_guard(GLOBAL)

#[=======================================================================[.rst:
rapids_cython_compile
---------------------

.. versionadded:: v22.08.00

Invoke the `cython` compiler to transpile a pyx file.
The arguments to this function mirror the arguments to the Cython CLI.
The only exceptions are:
- Inputs are provided via the SOURCE_FILES parameter
- The output filename is determined automatically from the input and cannot be customized

.. code-block:: cmake

  rapids_cython_compile()

.. note::
  Use of this module assumes that Cython has been independently installed on the system.

#]=======================================================================]
function(rapids_cython_compile)
  list(APPEND CMAKE_MESSAGE_CONTEXT "rapids.cython.compile")

  find_program(CYTHON "cython" REQUIRED)

  set(_rapids_cython_options)
  set(_rapids_cython_one_value TARGET_LANGUAGE LANGUAGE_LEVEL)
  set(_rapids_cython_multi_value CYTHON_ARGS SOURCE_FILES)

  cmake_parse_arguments(_RAPIDS_COMPILE "${_rapids_cython_options}" "${_rapids_cython_one_value}"
                        "${_rapids_cython_multi_value}" ${ARGN})

  # Match the Cython default language level.
  set(language_level -3str)
  if(${_RAPIDS_COMPILE_LANGUAGE_LEVEL} STREQUAL "2")
    set(language_level -2)
  elseif(${_RAPIDS_COMPILE_LANGUAGE_LEVEL} STREQUAL "3")
    set(language_level -3)
  elseif(NOT ${_RAPIDS_COMPILE_LANGUAGE_LEVEL} STREQUAL "3str")
    message(FATAL_ERROR "LANGUAGE_LEVEL must be one of 2, 3, or 3str")
  endif()

  set(target_language "")
  set(extension ".c")
  if(${_RAPIDS_COMPILE_TARGET_LANGUAGE} STREQUAL "CXX")
    set(target_language "--cplus")
    set(extension ".cxx")
  elseif(NOT ${_RAPIDS_COMPILE_TARGET_LANGUAGE} STREQUAL "C")
    message(FATAL_ERROR "TARGET_LANGUAGE must be one of C or CXX")
  endif()

  # Maintain list of generated targets
  set(CREATED_FILES "")

  foreach(cython_filename IN LISTS _RAPIDS_COMPILE_SOURCE_FILES)
    cmake_path(GET cython_filename FILENAME cython_module)
    cmake_path(REPLACE_EXTENSION cython_module "${extension}" OUTPUT_VARIABLE cpp_filename)
    cmake_path(REPLACE_FILENAME cython_filename ${cpp_filename} OUTPUT_VARIABLE cpp_filename)
    cmake_path(REMOVE_EXTENSION cython_module)

    add_custom_command(
      OUTPUT ${cpp_filename}
      DEPENDS ${cython_filename}
      VERBATIM
      # TODO: Is setting the input and output paths this way a robust solution,
      # or are there cases where it might be problematic?
      COMMAND "${CYTHON}" ${target_language} ${language_level} ${_RAPIDS_COMPILE_CYTHON_ARGS} "${CMAKE_CURRENT_SOURCE_DIR}/${cython_filename}" --output-file
              "${CMAKE_CURRENT_BINARY_DIR}/${cpp_filename}")

    list(APPEND CREATED_FILES "${CMAKE_CURRENT_BINARY_DIR}/${cpp_filename}")
  endforeach()

  set(RAPIDS_COMPILE_CREATED_FILES ${CREATED_FILES} PARENT_SCOPE)
endfunction()
