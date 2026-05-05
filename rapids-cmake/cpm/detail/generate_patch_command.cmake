# =============================================================================
# cmake-format: off
# SPDX-FileCopyrightText: Copyright (c) 2022-2026, NVIDIA CORPORATION.
# SPDX-License-Identifier: Apache-2.0
# cmake-format: on
# =============================================================================
include_guard(GLOBAL)

#[=======================================================================[.rst:
rapids_cpm_generate_patch_command
---------------------------------

.. versionadded:: v22.10.00

Applies any relevant patches to the provided CPM package

.. code-block:: cmake

  rapids_cpm_generate_patch_command(<pkg> <version> patch_command build_patch_only)

#]=======================================================================]
# cmake-lint: disable=R0912,R0915,E1120
function(rapids_cpm_generate_patch_command package_name version patch_command build_patch_only)
  list(APPEND CMAKE_MESSAGE_CONTEXT "rapids.cpm.generate_patch_command")

  include("${rapids-cmake-dir}/cpm/detail/load_preset_versions.cmake")
  rapids_cpm_load_preset_versions()

  include("${rapids-cmake-dir}/cpm/detail/get_default_json.cmake")
  include("${rapids-cmake-dir}/cpm/detail/get_override_json.cmake")
  get_default_json(${package_name} full_default_json)
  get_override_json(${package_name} full_override_json)

  string(TOLOWER "${package_name}" normalized_pkg_name)
  get_property(json_path GLOBAL PROPERTY rapids_cpm_${normalized_pkg_name}_json_file)
  get_property(override_json_path GLOBAL
               PROPERTY rapids_cpm_${normalized_pkg_name}_override_json_file)

  string(JSON json_data ERROR_VARIABLE no_default_patch GET "${full_default_json}" patches)
  string(JSON override_json_data ERROR_VARIABLE no_override_patch GET "${full_override_json}"
         patches)
  if(no_default_patch AND no_override_patch)
    return() # no patches
  endif()
  if(NOT no_override_patch)
    set(json_data "${override_json_data}")
    set(json_path "${override_json_path}")
  endif()

  # Need the current_json_dir variable populated before we parse any json entries so that we
  # properly evaluate this placeholder
  cmake_path(GET json_path PARENT_PATH current_json_dir)

  # Parse required fields
  function(rapids_cpm_json_get_value json_data_ name)
    string(JSON value ERROR_VARIABLE have_error GET "${json_data_}" ${name})
    if(NOT have_error)
      set(${name} ${value} PARENT_SCOPE)
    endif()
  endfunction()

  # Determine if the package uses git or URL (tarball) mode to select the patch tool. An override
  # that specifies git fields switches the package to git mode; an override that specifies url
  # fields switches it to url mode. Otherwise fall back to the default JSON.
  set(use_git_patch TRUE)
  if(full_override_json)
    string(JSON _v ERROR_VARIABLE no_url GET "${full_override_json}" url)
    string(JSON _v ERROR_VARIABLE no_git_url GET "${full_override_json}" git_url)
    if(no_url AND no_git_url)
      string(JSON _v ERROR_VARIABLE no_url GET "${full_default_json}" url)
    endif()
  else()
    string(JSON _v ERROR_VARIABLE no_url GET "${full_default_json}" url)
  endif()
  if(NOT no_url)
    set(use_git_patch FALSE)
  endif()

  if(use_git_patch)
    find_package(Git REQUIRED)
    if(NOT GIT_EXECUTABLE)
      message(WARNING "Unable to apply git patches to ${package_name}, git not found")
      return()
    endif()
  else()
    find_package(Patch REQUIRED)
    if(NOT Patch_EXECUTABLE)
      message(WARNING "Unable to apply patches to ${package_name}, patch not found")
      return()
    endif()
  endif()
  # For each project cache the subset of the json
  set(patch_files_to_run)
  set(patch_issues_to_ref)
  set(patch_required_to_apply)
  set(${build_patch_only} BUILD_PATCH_ONLY PARENT_SCOPE)

  # Gather number of patches
  string(JSON patch_count LENGTH "${json_data}")
  if(patch_count GREATER_EQUAL 1)
    math(EXPR patch_count "${patch_count} - 1")
    foreach(index RANGE ${patch_count})
      string(JSON patch_data GET "${json_data}" ${index})
      rapids_cpm_json_get_value(${patch_data} fixed_in)
      if(NOT fixed_in OR version VERSION_LESS fixed_in)
        set(build)

        rapids_cpm_json_get_value(${patch_data} file)
        rapids_cpm_json_get_value(${patch_data} inline_patch)
        rapids_cpm_json_get_value(${patch_data} issue)
        rapids_cpm_json_get_value(${patch_data} build)

        # Convert any embedded patch to a file.
        if(inline_patch)
          include("${rapids-cmake-dir}/cpm/detail/convert_patch_json.cmake")
          rapids_cpm_convert_patch_json(FROM_JSON_TO_FILE inline_patch FILE_VAR file PACKAGE_NAME
                                        ${package_name} INDEX ${index})
        endif()

        if(NOT build)
          set(${build_patch_only} PARENT_SCOPE)
        endif()

        if(file AND issue)
          cmake_language(EVAL CODE "set(file ${file})")
          cmake_path(IS_RELATIVE file is_relative)
          if(is_relative)
            set(file "${rapids-cmake-dir}/cpm/patches/${file}")
          endif()
          list(APPEND patch_files_to_run "${file}")
          list(APPEND patch_issues_to_ref "${issue}")

          set(required FALSE)
          rapids_cpm_json_get_value(${patch_data} required)
          list(APPEND patch_required_to_apply "${required}")
        endif()
        unset(file)
        unset(inline_patch)
        unset(issue)
      endif()
    endforeach()
  endif()

  set(patch_script "${CMAKE_BINARY_DIR}/rapids-cmake/patches/${package_name}/patch.cmake")
  set(log_file "${CMAKE_BINARY_DIR}/rapids-cmake/patches/${package_name}/log")
  set(err_file "${CMAKE_BINARY_DIR}/rapids-cmake/patches/${package_name}/err")
  if(patch_files_to_run)
    string(TIMESTAMP current_year "%Y" UTC)
    configure_file(${rapids-cmake-dir}/cpm/patches/command_template.cmake.in "${patch_script}"
                   @ONLY)
    set(${patch_command} PATCH_COMMAND ${CMAKE_COMMAND} -P ${patch_script} PARENT_SCOPE)
  else()
    # remove any old patch / log files that exist and are no longer needed due to a change in the
    # package version / version.json
    file(REMOVE "${patch_script}" "${log_file}" "${err_file}")
  endif()
endfunction()
