function(qt_internal_write_depends_file target)
    set(module Qt${target})
    set(outfile "${QT_BUILD_DIR}/${INSTALL_INCLUDEDIR}/${module}/${module}Depends")
    message("Generate ${outfile}...")
    set(contents "/* This file was generated by cmake with the info from ${module} target. */\n")
    string(APPEND contents "#ifdef __cplusplus /* create empty PCH in C mode */\n")
    foreach (m ${ARGN})
        string(APPEND contents "#  include <Qt${m}/Qt${m}>\n")
    endforeach()
    string(APPEND contents "#endif\n")

    file(GENERATE OUTPUT "${outfile}" CONTENT "${contents}")
endfunction()

macro(qt_collect_third_party_deps target)
    set(_target_is_static OFF)
    get_target_property(_target_type ${target} TYPE)
    if (${_target_type} STREQUAL "STATIC_LIBRARY")
        set(_target_is_static ON)
    endif()
    unset(_target_type)
    # If we are doing a non-static Qt build, we only want to propagate public dependencies.
    # If we are doing a static Qt build, we need to propagate all dependencies.
    set(depends_var "public_depends")
    if(_target_is_static)
        set(depends_var "depends")
    endif()
    unset(_target_is_static)

    foreach(dep ${${depends_var}})
        # Gather third party packages that should be found when using the Qt module.
        # Also handle nolink target dependencies.
        string(REGEX REPLACE "_nolink$" "" base_dep "${dep}")
        if(NOT base_dep STREQUAL dep)
            # Resets target name like Vulkan_nolink to Vulkan, because we need to call
            # find_package(Vulkan).
            set(dep ${base_dep})
        endif()

        if(TARGET ${dep})
            list(FIND third_party_deps_seen ${dep} dep_seen)

            get_target_property(package_name ${dep} INTERFACE_QT_PACKAGE_NAME)
            if(dep_seen EQUAL -1 AND package_name)
                list(APPEND third_party_deps_seen ${dep})
                get_target_property(package_version ${dep} INTERFACE_QT_PACKAGE_VERSION)
                if(NOT package_version)
                    set(package_version "")
                endif()

                get_target_property(package_components ${dep} INTERFACE_QT_PACKAGE_COMPONENTS)
                if(NOT package_components)
                    set(package_components "")
                endif()

                list(APPEND third_party_deps
                            "${package_name}\;${package_version}\;${package_components}")
            endif()
        endif()
    endforeach()
endmacro()

function(qt_internal_create_module_depends_file target)
    get_target_property(target_type "${target}" TYPE)
    if(target_type STREQUAL "INTERFACE_LIBRARY")
        set(arg_HEADER_MODULE ON)
    else()
        set(arg_HEADER_MODULE OFF)
    endif()

    set(depends "")
    if(target_type STREQUAL "STATIC_LIBRARY" AND NOT arg_HEADER_MODULE)
        get_target_property(depends "${target}" LINK_LIBRARIES)
    endif()

    get_target_property(public_depends "${target}" INTERFACE_LINK_LIBRARIES)

    # Used for collecting Qt module dependencies that should be find_package()'d in
    # ModuleDependencies.cmake.
    get_target_property(target_deps "${target}" _qt_target_deps)
    set(target_deps_seen "")

    if(NOT arg_HEADER_MODULE)
        get_target_property(extra_depends "${target}" QT_EXTRA_PACKAGE_DEPENDENCIES)
    endif()
    if(NOT extra_depends STREQUAL "${extra_depends}-NOTFOUND")
        list(APPEND target_deps "${extra_depends}")
    endif()

    # Used for assembling the content of an include/Module/ModuleDepends.h header.
    set(qtdeps "")

    # Used for collecting third party dependencies that should be find_package()'d in
    # ModuleDependencies.cmake.
    set(third_party_deps "")
    set(third_party_deps_seen "")

    # Used for collecting Qt tool dependencies that should be find_package()'d in
    # ModuleToolsDependencies.cmake.
    set(tool_deps "")
    set(tool_deps_seen "")

    # Used for collecting Qt tool dependencies that should be find_package()'d in
    # ModuleDependencies.cmake.
    set(main_module_tool_deps "")

    qt_internal_get_qt_all_known_modules(known_modules)

    set(all_depends ${depends} ${public_depends})
    foreach (dep ${all_depends})
        # Normalize module by stripping leading "Qt::" and trailing "Private"
        if (dep MATCHES "Qt::(.*)")
            set(dep "${CMAKE_MATCH_1}")
            if (TARGET Qt::${dep})
                get_target_property(dep_type Qt::${dep} TYPE)
                if (NOT dep_type STREQUAL "INTERFACE_LIBRARY")
                    get_target_property(skip_module_depends_include Qt::${dep} QT_MODULE_SKIP_DEPENDS_INCLUDE)
                    if (skip_module_depends_include)
                        continue()
                    endif()
                endif()
            endif()
        endif()
        if (dep MATCHES "(.*)Private")
            set(dep "${CMAKE_MATCH_1}")
        endif()

        list(FIND known_modules "${dep}" _pos)
        if (_pos GREATER -1)
            list(APPEND qtdeps "${dep}")

            # Make the ModuleTool package depend on dep's ModuleTool package.
            list(FIND tool_deps_seen ${dep} dep_seen)
            if(dep_seen EQUAL -1 AND ${dep} IN_LIST QT_KNOWN_MODULES_WITH_TOOLS)
                list(APPEND tool_deps_seen ${dep})
                list(APPEND tool_deps
                            "${INSTALL_CMAKE_NAMESPACE}${dep}Tools\;${PROJECT_VERSION}")
            endif()
        endif()
    endforeach()

    qt_collect_third_party_deps(${target})

    # Add dependency to the main ModuleTool package to ModuleDependencies file.
    if(${target} IN_LIST QT_KNOWN_MODULES_WITH_TOOLS)
        set(main_module_tool_deps
            "${INSTALL_CMAKE_NAMESPACE}${target}Tools\;${PROJECT_VERSION}")
    endif()

    # Dirty hack because https://gitlab.kitware.com/cmake/cmake/issues/19200
    foreach(dep ${target_deps})
        if(dep)
            list(FIND target_deps_seen "${dep}" dep_seen)
            if(dep_seen EQUAL -1)
                list(LENGTH dep len)
                if(NOT (len EQUAL 2))
                    message(FATAL_ERROR "List '${dep}' should look like QtFoo;version")
                endif()
                list(GET dep 0 dep_name)
                list(GET dep 1 dep_ver)

                list(APPEND target_deps_seen "${dep_name}\;${dep_ver}")
            endif()
        endif()
    endforeach()
    set(target_deps "${target_deps_seen}")

    if (DEFINED qtdeps)
        list(REMOVE_DUPLICATES qtdeps)
    endif()

    get_target_property(hasModuleHeaders "${target}" INTERFACE_MODULE_HAS_HEADERS)
    if (${hasModuleHeaders})
        qt_internal_write_depends_file("${target}" ${qtdeps})
    endif()

    if(third_party_deps OR main_module_tool_deps OR target_deps)
        set(path_suffix "${INSTALL_CMAKE_NAMESPACE}${target}")
        qt_path_join(config_build_dir ${QT_CONFIG_BUILD_DIR} ${path_suffix})
        qt_path_join(config_install_dir ${QT_CONFIG_INSTALL_DIR} ${path_suffix})

        # Configure and install ModuleDependencies file.
        configure_file(
            "${QT_CMAKE_DIR}/QtModuleDependencies.cmake.in"
            "${config_build_dir}/${INSTALL_CMAKE_NAMESPACE}${target}Dependencies.cmake"
            @ONLY
        )

        qt_install(FILES
            "${config_build_dir}/${INSTALL_CMAKE_NAMESPACE}${target}Dependencies.cmake"
            DESTINATION "${config_install_dir}"
            COMPONENT Devel
        )

    endif()
    if(tool_deps)
        # The value of the property will be used by qt_export_tools.
        set_property(TARGET "${target}" PROPERTY _qt_tools_package_deps "${tool_deps}")
    endif()
endfunction()

function(qt_internal_create_plugin_depends_file target)
    get_target_property(qt_module "${target}" QT_MODULE)
    get_target_property(depends "${target}" LINK_LIBRARIES)
    get_target_property(public_depends "${target}" INTERFACE_LINK_LIBRARIES)
    get_target_property(target_deps "${target}" _qt_target_deps)
    set(target_deps_seen "")

    qt_collect_third_party_deps(${target})

    # Dirty hack because https://gitlab.kitware.com/cmake/cmake/issues/19200
    foreach(dep ${target_deps})
        if(dep)
            list(FIND target_deps_seen "${dep}" dep_seen)
            if(dep_seen EQUAL -1)
                list(LENGTH dep len)
                if(NOT (len EQUAL 2))
                    message(FATAL_ERROR "List '${dep}' should look like QtFoo;version")
                endif()
                list(GET dep 0 dep_name)
                list(GET dep 1 dep_ver)

                list(APPEND target_deps_seen "${dep_name}\;${dep_ver}")
            endif()
        endif()
    endforeach()
    set(target_deps "${target_deps_seen}")

    if(third_party_deps OR target_deps)
        # Setup build and install paths
        if(qt_module)
            set(path_suffix "${INSTALL_CMAKE_NAMESPACE}${qt_module}")
        else()
            set(path_suffix "${INSTALL_CMAKE_NAMESPACE}${target}")
        endif()

        qt_path_join(config_build_dir ${QT_CONFIG_BUILD_DIR} ${path_suffix})
        qt_path_join(config_install_dir ${QT_CONFIG_INSTALL_DIR} ${path_suffix})

        # Configure and install ModuleDependencies file.
        configure_file(
            "${QT_CMAKE_DIR}/QtPluginDependencies.cmake.in"
            "${config_build_dir}/${target}Dependencies.cmake"
            @ONLY
        )

        qt_install(FILES
            "${config_build_dir}/${target}Dependencies.cmake"
            DESTINATION "${config_install_dir}"
            COMPONENT Devel
        )
    endif()
endfunction()

# Create Depends.cmake & Depends.h files for all modules and plug-ins.
function(qt_internal_create_depends_files)
    qt_internal_get_qt_repo_known_modules(repo_known_modules)

    message("Generating ModuleDepends files and CMake ModuleDependencies files for ${repo_known_modules}...")
    foreach (target ${repo_known_modules})
        qt_internal_create_module_depends_file(${target})
    endforeach()

    message("Generating CMake PluginDependencies files for ${QT_KNOWN_PLUGINS}...")
    foreach (target ${QT_KNOWN_PLUGINS})
        qt_internal_create_plugin_depends_file(${target})
    endforeach()
endfunction()

# This function creates the Qt<Module>Plugins.cmake used to list all
# the plug-in target files.
function(qt_internal_create_plugins_files)
    # The plugins cmake configuration is only needed for static builds. Dynamic builds don't need
    # the application to link against plugins at build time.
    if(QT_BUILD_SHARED_LIBS)
        return()
    endif()
    qt_internal_get_qt_repo_known_modules(repo_known_modules)

    message("Generating Plugins files for ${repo_known_modules}...")
    foreach (QT_MODULE ${repo_known_modules})
        get_target_property(target_type "${QT_MODULE}" TYPE)
        if(target_type STREQUAL "INTERFACE_LIBRARY")
            # No plugins are provided by a header only module.
            continue()
        endif()
        qt_path_join(config_build_dir ${QT_CONFIG_BUILD_DIR} ${INSTALL_CMAKE_NAMESPACE}${QT_MODULE})
        qt_path_join(config_install_dir ${QT_CONFIG_INSTALL_DIR} ${INSTALL_CMAKE_NAMESPACE}${QT_MODULE})
        set(QT_MODULE_PLUGIN_INCLUDES "")

        get_target_property(qt_plugins "${QT_MODULE}" QT_PLUGINS)
        if(qt_plugins)
            foreach (pluginTarget ${qt_plugins})
                set(QT_MODULE_PLUGIN_INCLUDES "${QT_MODULE_PLUGIN_INCLUDES}include(\"\${CMAKE_CURRENT_LIST_DIR}/${pluginTarget}Config.cmake\")\n")
            endforeach()
            configure_file(
                "${QT_CMAKE_DIR}/QtPlugins.cmake.in"
                "${config_build_dir}/${INSTALL_CMAKE_NAMESPACE}${QT_MODULE}Plugins.cmake"
                @ONLY
            )
            qt_install(FILES
                "${config_build_dir}/${INSTALL_CMAKE_NAMESPACE}${QT_MODULE}Plugins.cmake"
                DESTINATION "${config_install_dir}"
                COMPONENT Devel
            )
        endif()
    endforeach()
endfunction()

function(qt_generate_install_prefixes out_var)
    set(content "\n")
    set(vars INSTALL_BINDIR INSTALL_INCLUDEDIR INSTALL_LIBDIR INSTALL_MKSPECSDIR INSTALL_ARCHDATADIR
        INSTALL_PLUGINSDIR INSTALL_LIBEXECDIR INSTALL_QMLDIR INSTALL_DATADIR INSTALL_DOCDIR
        INSTALL_TRANSLATIONSDIR INSTALL_SYSCONFDIR INSTALL_EXAMPLESDIR INSTALL_TESTSDIR
        INSTALL_DESCRIPTIONSDIR)

    foreach(var ${vars})
        get_property(docstring CACHE "${var}" PROPERTY HELPSTRING)
        string(APPEND content "set(${var} \"${${var}}\" CACHE STRING \"${docstring}\" FORCE)\n")
    endforeach()

    set(${out_var} "${content}" PARENT_SCOPE)
endfunction()

function(qt_generate_build_internals_extra_cmake_code)
    if(PROJECT_NAME STREQUAL "QtBase")
        foreach(var IN LISTS QT_BASE_CONFIGURE_TESTS_VARS_TO_EXPORT)
            string(APPEND QT_EXTRA_BUILD_INTERNALS_VARS "set(${var} \"${${var}}\" CACHE INTERNAL \"\")\n")
        endforeach()

        set(QT_SOURCE_TREE "${QtBase_SOURCE_DIR}")
        qt_path_join(extra_file_path
                     ${QT_CONFIG_BUILD_DIR}
                     ${INSTALL_CMAKE_NAMESPACE}BuildInternals/QtBuildInternalsExtra.cmake)

        if(CMAKE_BUILD_TYPE)
            # Need to force set, because CMake itself initializes a value for CMAKE_BUILD_TYPE
            # at the start of project configuration (with an empty value),
            # so we need to force override it.
            string(APPEND QT_EXTRA_BUILD_INTERNALS_VARS
                "set(CMAKE_BUILD_TYPE \"${CMAKE_BUILD_TYPE}\" CACHE STRING \"Choose the type of build.\" FORCE)\n")

        endif()
        if(CMAKE_CONFIGURATION_TYPES)
            string(APPEND QT_EXTRA_BUILD_INTERNALS_VARS
                "set(CMAKE_CONFIGURATION_TYPES \"${CMAKE_CONFIGURATION_TYPES}\" CACHE STRING \"\" FORCE)\n")
        endif()
        if(CMAKE_TRY_COMPILE_CONFIGURATION)
            string(APPEND QT_EXTRA_BUILD_INTERNALS_VARS
                "set(CMAKE_TRY_COMPILE_CONFIGURATION \"${CMAKE_TRY_COMPILE_CONFIGURATION}\")\n")
        endif()
        if(QT_MULTI_CONFIG_FIRST_CONFIG)
            string(APPEND QT_EXTRA_BUILD_INTERNALS_VARS
                "set(QT_MULTI_CONFIG_FIRST_CONFIG \"${QT_MULTI_CONFIG_FIRST_CONFIG}\")\n")
        endif()
        if(CMAKE_CROSS_CONFIGS)
            string(APPEND QT_EXTRA_BUILD_INTERNALS_VARS
                "set(CMAKE_CROSS_CONFIGS \"${CMAKE_CROSS_CONFIGS}\" CACHE STRING \"\")\n")
        endif()
        if(CMAKE_DEFAULT_BUILD_TYPE)
            string(APPEND QT_EXTRA_BUILD_INTERNALS_VARS
                "set(CMAKE_DEFAULT_BUILD_TYPE \"${CMAKE_DEFAULT_BUILD_TYPE}\" CACHE STRING \"\")\n")
        endif()
        if(DEFINED BUILD_WITH_PCH)
            string(APPEND QT_EXTRA_BUILD_INTERNALS_VARS
                "set(BUILD_WITH_PCH \"${BUILD_WITH_PCH}\" CACHE STRING \"\")\n")
        endif()

        qt_generate_install_prefixes(install_prefix_content)

        string(APPEND QT_EXTRA_BUILD_INTERNALS_VARS "${install_prefix_content}")

        configure_file(
            "${CMAKE_CURRENT_LIST_DIR}/QtBuildInternalsExtra.cmake.in"
            "${extra_file_path}"
            @ONLY
        )
    endif()
endfunction()

# For every Qt module check if there any android dependencies that require
# processing.
function(qt_modules_process_android_dependencies)
    qt_internal_get_qt_repo_known_modules(repo_known_modules)
    foreach (target ${repo_known_modules})
        qt_android_dependencies(${target})
    endforeach()
endfunction()

function(qt_create_tools_config_files)
    # Create packages like Qt6CoreTools/Qt6CoreToolsConfig.cmake.
    foreach(module_name ${QT_KNOWN_MODULES_WITH_TOOLS})
        qt_export_tools("${module_name}")
    endforeach()
endfunction()

function(qt_internal_create_config_file_for_standalone_tests)
    set(standalone_tests_config_dir "StandaloneTests")
    qt_path_join(config_build_dir
                 ${QT_CONFIG_BUILD_DIR}
                 "${INSTALL_CMAKE_NAMESPACE}BuildInternals" "${standalone_tests_config_dir}")
    qt_path_join(config_install_dir
                 ${QT_CONFIG_INSTALL_DIR}
                 "${INSTALL_CMAKE_NAMESPACE}BuildInternals" "${standalone_tests_config_dir}")

    # Filter out bundled system libraries. Otherwise when looking for their dependencies
    # (like PNG for Freetype) FindWrapPNG is searched for during configuration of
    # standalone tests, and it can happen that Core or Gui features are not
    # imported early enough, which means FindWrapPNG will try to find a system PNG library instead
    # of the bundled one.
    set(modules)
    foreach(m ${QT_REPO_KNOWN_MODULES})
        get_target_property(target_type "${m}" TYPE)

        # Interface libraries are never bundled system libraries (hopefully).
        if(target_type STREQUAL "INTERFACE_LIBRARY")
            list(APPEND modules "${m}")
            continue()
        endif()

        get_target_property(is_3rd_party "${m}" QT_MODULE_IS_3RDPARTY_LIBRARY)
        if(NOT is_3rd_party)
            list(APPEND modules "${m}")
        endif()
    endforeach()

    list(JOIN modules " " QT_REPO_KNOWN_MODULES_STRING)
    string(STRIP "${QT_REPO_KNOWN_MODULES_STRING}" QT_REPO_KNOWN_MODULES_STRING)

    # Skip generating and installing file if no modules were built. This make sure not to install
    # anything when build qtx11extras on macOS for example.
    if(NOT QT_REPO_KNOWN_MODULES_STRING)
        return()
    endif()

    # Ceate a Config file that calls find_package on the modules that were built as part
    # of the current repo. This is used for standalone tests.
    configure_file(
        "${QT_CMAKE_DIR}/QtStandaloneTestsConfig.cmake.in"
        "${config_build_dir}/${PROJECT_NAME}TestsConfig.cmake"
        @ONLY
    )
    qt_install(FILES
        "${config_build_dir}/${PROJECT_NAME}TestsConfig.cmake"
        DESTINATION "${config_install_dir}"
        COMPONENT Devel
    )
endfunction()

qt_internal_create_depends_files()
qt_generate_build_internals_extra_cmake_code()
qt_internal_create_plugins_files()
qt_internal_create_config_file_for_standalone_tests()

# Needs to run after qt_internal_create_depends_files.
qt_create_tools_config_files()

if (ANDROID)
    qt_modules_process_android_dependencies()
endif()
