# =============================================================================
# Copyright (c) 2022-2023, NVIDIA CORPORATION.
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
rapids_cython_create_modules
----------------------------

.. versionadded:: v22.06.00

Generate C(++) from Cython and create Python modules.

.. code-block:: cmake

  rapids_cython_create_modules([CXX] [SOURCE_FILES <src1> <src2> ...] [LINKED_LIBRARIES <lib1> <lib2> ... ]  [INSTALL_DIR <install_path>] [MODULE_PREFIX <module_prefix>] )

Creates a Cython target for each provided source file, then adds a
corresponding Python extension module. Each built library has its RPATH set to
$ORIGIN.

.. note::
  Requires :cmake:command:`rapids_cython_init` to be called before usage.

``CXX``
  Flag indicating that the Cython files need to generate C++ rather than C.

``SOURCE_FILES``
  The list of Cython source files to be built into Python extension modules.
  Note that this function assumes that Cython source files have a one-one
  correspondence with extension modules to build, i.e. for every `<Name>.pyx`
  in SOURCE_FILES we assume that `<Name>.pyx` is a Cython source file for which
  an extension module `<Name>` should be built.

``LINKED_LIBRARIES``
  The list of libraries that need to be linked into all modules. In RAPIDS,
  this list usually contains (at minimum) the corresponding C++ libraries.

``INSTALL_DIR``
  The path relative to the installation prefix so that it can be converted to
  an absolute path in a relocatable way. If not provided, defaults to the path
  to CMAKE_CURRENT_SOURCE_DIR relative to PROJECT_SOURCE_DIR.

``MODULE_PREFIX``
  A prefix used to name the generated library targets. This functionality is
  useful when multiple Cython modules in different subpackages of the the same
  project have the same name. The default prefix is the empty string.

``ASSOCIATED_TARGETS``
  A list of targets that are associated with the Cython targets created in this
  function. The target<-->associated target mapping is stored and may be
  leveraged by the following functions:

  - :cmake:command:`rapids_cython_add_rpath_entries` accepts a path for an
    associated target and updates the RPATH of each target with which that
    associated target is associated.

Result Variables
^^^^^^^^^^^^^^^^
  :cmake:variable:`RAPIDS_CYTHON_CREATED_TARGETS` will be set to a list of
  targets created by this function.

#]=======================================================================]
function(rapids_cython_create_modules)
  include(${CMAKE_CURRENT_FUNCTION_LIST_DIR}/detail/verify_init.cmake)
  rapids_cython_verify_init()

  list(APPEND CMAKE_MESSAGE_CONTEXT "rapids.cython.create_modules")

  include(${CMAKE_CURRENT_FUNCTION_LIST_DIR}/cython.cmake)

  set(_rapids_cython_options CXX)
  set(_rapids_cython_one_value INSTALL_DIR MODULE_PREFIX)
  set(_rapids_cython_multi_value SOURCE_FILES LINKED_LIBRARIES ASSOCIATED_TARGETS)
  cmake_parse_arguments(_RAPIDS_CYTHON "${_rapids_cython_options}" "${_rapids_cython_one_value}"
                        "${_rapids_cython_multi_value}" ${ARGN})

  set(language_flag "")
  if(_RAPIDS_CYTHON_CXX)
    set(language_flag CPLUS)
  endif()

  set(CREATED_TARGETS "")

  if(NOT DEFINED _RAPIDS_CYTHON_MODULE_PREFIX)
    set(_RAPIDS_CYTHON_MODULE_PREFIX "")
  endif()

  set(cython_module_prefix "${_RAPIDS_CYTHON_MODULE_PREFIX}cython_")
  message("The module prefix for create_modules is ${_RAPIDS_CYTHON_MODULE_PREFIX}")
  message("The module prefix for cython from create_modules is ${cython_module_prefix}")
  foreach(cython_filename IN LISTS _RAPIDS_CYTHON_SOURCE_FILES)
    rapids_cython_compile(SOURCE_FILES ${cython_filename} PY3 ${language_flag} DIRECTIVES binding=True embedsignature=True always_allow_keywords=True TARGET_PREFIX ${cython_module_prefix})

    # Generate a reasonable module name.
    cmake_path(GET cython_filename FILENAME extension_module)
    cmake_path(REMOVE_EXTENSION extension_module)

    # Save the name of the module without the provided prefix so that we can control the output.
    set(cython_module_filename "${extension_module}")
    string(PREPEND extension_module ${_RAPIDS_CYTHON_MODULE_PREFIX})

    list(GET RAPIDS_COMPILE_CREATED_TARGETS 0 cython_module)
    message("Creating extension module ${extension_module} from target ${cython_module}")
    python_add_library(${extension_module} MODULE ${cython_module})

    # The final library name must match the original filename and must ignore the prefix.
    set_target_properties(${extension_module} PROPERTIES LIBRARY_OUTPUT_NAME ${extension_module_filename})

    # Link the module to the requested libraries
    if(DEFINED _RAPIDS_CYTHON_LINKED_LIBRARIES)
      target_link_libraries(${extension_module} PUBLIC ${_RAPIDS_CYTHON_LINKED_LIBRARIES})
    endif()

    # Compute the install directory relative to the source and rely on installs being relative to
    # the CMAKE_PREFIX_PATH for e.g. editable installs.
    if(NOT DEFINED _RAPIDS_CYTHON_INSTALL_DIR)
      cmake_path(RELATIVE_PATH CMAKE_CURRENT_SOURCE_DIR BASE_DIRECTORY "${PROJECT_SOURCE_DIR}"
                 OUTPUT_VARIABLE _RAPIDS_CYTHON_INSTALL_DIR)
    endif()
    install(TARGETS ${extension_module} DESTINATION ${_RAPIDS_CYTHON_INSTALL_DIR})

    # Default the INSTALL_RPATH for all modules to $ORIGIN.
    if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
      set(platform_rpath_origin "@loader_path")
    else()
      set(platform_rpath_origin "$ORIGIN")
    endif()
    set_target_properties(${extension_module} PROPERTIES INSTALL_RPATH "${platform_rpath_origin}")

    # Store any provided associated targets in a global list
    foreach(associated_target IN LISTS _RAPIDS_CYTHON_ASSOCIATED_TARGETS)
      set_property(GLOBAL PROPERTY "rapids_cython_associations_${associated_target}"
                                   "${extension_module}" APPEND)
    endforeach()

    list(APPEND CREATED_TARGETS "${extension_module}")
  endforeach()

  set(RAPIDS_CYTHON_CREATED_TARGETS ${CREATED_TARGETS} PARENT_SCOPE)
endfunction()