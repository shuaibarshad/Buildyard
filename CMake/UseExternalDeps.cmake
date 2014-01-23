
# Copyright (c) 2012 Stefan Eilemann <Stefan.Eilemann@epfl.ch>

function(USE_EXTERNAL_GATHER_INSTALL NAME)
  # sets ${NAME}_DEBS and ${NAME}_PORTS from all dependencies on return
  set(DEBS pkg-config git git-svn subversion cmake autoconf automake git-review
    ninja-build lcov doxygen)

  # recurse to get dependency roots
  foreach(proj ${${NAME}_DEPENDS})
    string(TOUPPER ${proj} PROJ)
    use_external_gather_install(${PROJ})
    list(APPEND DEBS ${${PROJ}_DEBS})
    list(APPEND PORTS ${${PROJ}_PORTS})
  endforeach()

  list(APPEND DEBS ${${NAME}_DEB_DEPENDS})
  list(APPEND PORTS ${${NAME}_PORT_DEPENDS})
  if(DEBS)
    list(REMOVE_DUPLICATES DEBS)
    list(SORT DEBS)
    set(${NAME}_DEBS ${DEBS} PARENT_SCOPE) # return value
  endif()
  if(PORTS)
    list(REMOVE_DUPLICATES PORTS)
    list(SORT PORTS)
    set(${NAME}_PORTS ${PORTS} PARENT_SCOPE) # return value
  endif()
endfunction()

# write in-source FindPackages.cmake, .travis.yml
function(USE_EXTERNAL_DEPS name)
  string(TOUPPER ${name} NAME)
  if(BUILDYARD_STOP OR ${NAME}_SKIPFIND OR NOT ${NAME}_DEPENDS)
    return()
  endif()

  set(_fpIn "${CMAKE_CURRENT_BINARY_DIR}/${name}FindPackages.cmake")
  set(_fpOut "${${NAME}_SOURCE}/CMake/FindPackages.cmake")
  set(_ciIn "${CMAKE_CURRENT_BINARY_DIR}/${name}Travis.yml")
  set(_ciOut "${${NAME}_SOURCE}/.travis.yml")
  set(_configIn "${CMAKE_CURRENT_BINARY_DIR}/${name}Config.cmake")
  set(_configOut "${${NAME}_SOURCE}/CMake/${name}.cmake")
  set(_dependsIn "${CMAKE_CURRENT_BINARY_DIR}/${name}Depends.txt")
  set(_dependsOut "${${NAME}_SOURCE}/CMake/depends.txt")
  set(_reqIn "${CMAKE_CURRENT_BINARY_DIR}/${name}FindRequired.cmake")
  set(_reqOut "${${NAME}_SOURCE}/CMake/FindRequired.cmake")

  set(_scriptdir ${CMAKE_CURRENT_BINARY_DIR}/${name})
  set(_generated ${_fpOut} ${_ciOut} ${_configOut} ${_dependsOut} ${_reqOut})
  set(DEPMODE)

  set(_deps)

  #----------------------------------------------------------------------------
  #---- Generate FindPackages.cmake header
  #----------------------------------------------------------------------------
  file(WRITE ${_fpIn}
    "# generated by Buildyard, do not edit.\n\n"
    "include(System)\n"
    "list(APPEND FIND_PACKAGES_DEFINES \${SYSTEM})\n"
    "find_package(PkgConfig)\n\n"
    "set(ENV{PKG_CONFIG_PATH} \"\${CMAKE_INSTALL_PREFIX}/lib/pkgconfig:\$ENV{PKG_CONFIG_PATH}\")\n"
    )
  file(WRITE ${_ciIn}
    "# generated by Buildyard, do not edit.\n"
    "notifications:\n"
    "  email:\n"
    "    on_success: never\n"
    "language: cpp\n"
    "script:\n"
    " - mkdir Debug\n"
    " - cd Debug\n"
    " - cmake .. -DCI_BUILD_COMMIT=$TRAVIS_COMMIT -DCMAKE_BUILD_TYPE=Debug -DTRAVIS=1\n"
    " - env TRAVIS=1 make -j2 tests ARGS=-V\n" # 1.5 cores on travis-ci.com
    " - mkdir ../Release\n"
    " - git status\n"
    " - git --no-pager diff\n"
    " - cd ../Release\n"
    " - cmake .. -DCI_BUILD_COMMIT=$TRAVIS_COMMIT -DCMAKE_BUILD_TYPE=Release -DTRAVIS=1\n"
    " - env TRAVIS=1 make -j2 tests ARGS=-V\n"
    " - git status\n"
    " - git --no-pager diff\n"
    "before_install:\n"
    " - sudo apt-get update -qq\n")
  file(WRITE ${_reqIn} "
# generated by Buildyard, do not edit. Sets FOUND_REQUIRED if all required
# dependencies are found. Used by Buildyard.cmake
set(FIND_REQUIRED_FAILED)")

  set(_use_external_post)

  #----------------------------------------------------------------------------
  # Iterate through the dependencies found:
  #
  # Dependencies come as a list of space separated words, these words can
  # either be REQUIRED, OPTIONAL or an actual dependency name. When REQUIRED or
  # OPTIONAL are found the flag DEPMODE is set accordingly. When an actual
  # dependency is found, different checks are perfomed depending on the
  # dependency being REQUIRED or not, and having components or not.
  # ---------------------------------------------------------------------------
  foreach(_dep ${${NAME}_DEPENDS})
    # Set mode flag to OPTIONAL or REQUIRED
    if(${_dep} STREQUAL "OPTIONAL")
      set(DEPMODE)
    elseif(${_dep} STREQUAL "REQUIRED")
      set(DEPMODE " REQUIRED")
    else()
      # Process an actual dependency
      string(TOUPPER ${_dep} _DEP)
      set(COMPONENTS)
      set(COMPONENTS_NOT_REQUIRED)

      # If the dependency has declared components take them into account
      if(${NAME}_${_DEP}_COMPONENTS)
        set(COMPONENTS_NOT_REQUIRED " COMPONENTS ${${NAME}_${_DEP}_COMPONENTS}")
        if(DEPMODE)
          set(COMPONENTS " ${${NAME}_${_DEP}_COMPONENTS}")
        else()
          set(COMPONENTS " COMPONENTS ${${NAME}_${_DEP}_COMPONENTS}")
        endif()
      endif()

      if(${_DEP}_CMAKE_INCLUDE)
        set(${_DEP}_CMAKE_INCLUDE "${${_DEP}_CMAKE_INCLUDE} ")
      endif()

      #------------------------------------------------------------------------
      # Inject the actual FindPackage logic
      # 1- Use find_package without REQUIRED
      # 2- If package not found then use pkg_check_modules
      # 3- If package not found and it was REQUIRED then throw a FATAL ERROR
      #------------------------------------------------------------------------
      if(NOT ${_DEP}_SKIPFIND)
        list(APPEND _deps ${_dep})
        set(DEFDEP "${NAME}_USE_${_DEP}")
        string(REGEX REPLACE "-" "_" DEFDEP ${DEFDEP})

        # Take into accout whether there is a version required or not
        if (${_DEP}_PACKAGE_VERSION)
            set(pkg_command "pkg_check_modules(${_dep} ${_dep}>=${${_DEP}_PACKAGE_VERSION})")
        else()
            set(pkg_command "pkg_check_modules(${_dep} ${_dep})")
        endif()

        # Try to find the dependency
        file(APPEND ${_fpIn}
          "if(PKG_CONFIG_EXECUTABLE)\n"
          "  find_package(${_dep} ${${_DEP}_PACKAGE_VERSION}${${_DEP}_FIND_ARGS}${COMPONENTS_NOT_REQUIRED})\n"
          "  if((NOT ${_dep}_FOUND) AND (NOT ${_DEP}_FOUND))\n"
          "    ${pkg_command}\n"
          "  endif()\n")
        if(DEPMODE STREQUAL " REQUIRED")
          file(APPEND ${_fpIn}
            "  if((NOT ${_dep}_FOUND) AND (NOT ${_DEP}_FOUND))\n"
            "    message(FATAL_ERROR \"Could not find ${_dep}\")\n"
            "  endif()\n")
        endif()
        file(APPEND ${_fpIn}
          "else()\n"
          "  find_package(${_dep} ${${_DEP}_PACKAGE_VERSION} ${${_DEP}_FIND_ARGS}${DEPMODE}${COMPONENTS})\n"
          "endif()\n\n")

        if(DEPMODE STREQUAL " REQUIRED")
          if(COMPONENTS)
            set(COMPONENTS " COMPONENTS${COMPONENTS}")
          endif()
          file(APPEND ${_reqIn} "
find_package(${_dep} ${${_DEP}_PACKAGE_VERSION}${COMPONENTS} QUIET)
if(NOT ${_dep}_FOUND AND NOT ${_DEP}_FOUND)
  set(FIND_REQUIRED_FAILED \"\${FIND_REQUIRED_FAILED} ${_dep}\")
endif()")
        endif()
        set(_use_external_post "${_use_external_post}
if(${_DEP}_FOUND)
  set(${_dep}_name ${_DEP})
  set(${_dep}_FOUND TRUE)
elseif(${_dep}_FOUND)
  set(${_dep}_name ${_dep})
  set(${_DEP}_FOUND TRUE)
endif()
if(${_dep}_name)
  list(APPEND FIND_PACKAGES_DEFINES ${DEFDEP})
  set(FIND_PACKAGES_FOUND \"\${FIND_PACKAGES_FOUND} ${_dep}\")
  link_directories(\${\${${_dep}_name}_LIBRARY_DIRS})
  if(NOT \"\${\${${_dep}_name}_INCLUDE_DIRS}\" MATCHES \"-NOTFOUND\")
    include_directories(${${_DEP}_CMAKE_INCLUDE}\${\${${_dep}_name}_INCLUDE_DIRS})
  endif()
endif()
")
      endif()
    endif()
  endforeach()

  use_external_gather_install(${NAME})
  foreach(_dep ${${NAME}_DEBS})
    file(APPEND ${_ciIn} " - sudo apt-get install -qq ${_dep} || /bin/true\n")
  endforeach()

  file(APPEND ${_fpIn} "\n"
    "if(EXISTS \${CMAKE_SOURCE_DIR}/CMake/FindPackagesPost.cmake)\n"
    "  include(\${CMAKE_SOURCE_DIR}/CMake/FindPackagesPost.cmake)\n"
    "endif()\n"
    "${_use_external_post}\n")

  if(${NAME}_DEBS)  # setup for CPACK_DEBIAN_BUILD_DEPENDS
    file(APPEND ${_fpIn} "set(${NAME}_BUILD_DEBS ${${NAME}_DEBS})\n")
  endif()

  file(APPEND ${_fpIn} "\n"
    "set(${NAME}_DEPENDS ${_deps})\n\n"
    "# Write defines.h and options.cmake\n"
    "if(NOT PROJECT_INCLUDE_NAME)\n"
    "  set(PROJECT_INCLUDE_NAME \${CMAKE_PROJECT_NAME})\n"
    "endif()\n"
    "if(NOT OPTIONS_CMAKE)\n"
    "  set(OPTIONS_CMAKE \${CMAKE_BINARY_DIR}/options.cmake)\n"
    "endif()\n"
    "set(DEFINES_FILE \"\${CMAKE_BINARY_DIR}/include/\${PROJECT_INCLUDE_NAME}/defines\${SYSTEM}.h\")\n"
    "set(DEFINES_FILE_IN \${DEFINES_FILE}.in)\n"
    "file(WRITE \${DEFINES_FILE_IN}\n"
    "  \"// generated by CMake/FindPackages.cmake, do not edit.\\n\\n\"\n"
    "  \"#ifndef \${CMAKE_PROJECT_NAME}_DEFINES_\${SYSTEM}_H\\n\"\n"
    "  \"#define \${CMAKE_PROJECT_NAME}_DEFINES_\${SYSTEM}_H\\n\\n\")\n"
    "file(WRITE \${OPTIONS_CMAKE} \"# Optional modules enabled during build\\n\")\n"
    "foreach(DEF \${FIND_PACKAGES_DEFINES})\n"
    "  add_definitions(-D\${DEF}=1)\n"
    "  file(APPEND \${DEFINES_FILE_IN}\n"
    "  \"#ifndef \${DEF}\\n\"\n"
    "  \"#  define \${DEF} 1\\n\"\n"
    "  \"#endif\\n\")\n"
    "if(NOT DEF STREQUAL SYSTEM)\n"
    "  file(APPEND \${OPTIONS_CMAKE} \"set(\${DEF} ON)\\n\")\n"
    "endif()\n"
    "endforeach()\n"
    "file(APPEND \${DEFINES_FILE_IN}\n"
    "  \"\\n#endif\\n\")\n\n"
    "include(UpdateFile)\n"
    "update_file(\${DEFINES_FILE_IN} \${DEFINES_FILE})\n"
    "if(Boost_FOUND) # another WAR for broken boost stuff...\n"
    "  set(Boost_VERSION \${Boost_MAJOR_VERSION}.\${Boost_MINOR_VERSION}.\${Boost_SUBMINOR_VERSION})\n"
    "endif()\n"
    "if(CUDA_FOUND)\n"
    "  string(REPLACE \"-std=c++11\" \"\" CUDA_HOST_FLAGS \"\${CUDA_HOST_FLAGS}\")\n"
    "  string(REPLACE \"-std=c++0x\" \"\" CUDA_HOST_FLAGS \"\${CUDA_HOST_FLAGS}\")\n"
    "endif()\n"
    "if(FIND_PACKAGES_FOUND)\n"
    "  if(MSVC)\n"
    "    message(STATUS \"Configured with \${FIND_PACKAGES_FOUND}\")\n"
    "  else()\n"
    "    message(STATUS \"Configured with \${CMAKE_BUILD_TYPE}\${FIND_PACKAGES_FOUND}\")\n"
    "  endif()\n"
    "endif()\n"
    )

  file(APPEND ${_reqIn} "
if(FIND_REQUIRED_FAILED)
  set(FOUND_REQUIRED FALSE)
else()
  set(FOUND_REQUIRED TRUE)
endif()")

  file(READ ${${NAME}_CONFIGFILE} _configfile)
  file(WRITE ${_configIn} "
${_configfile}
if(CI_BUILD_COMMIT)
  set(${NAME}_REPO_TAG \${CI_BUILD_COMMIT})
else()
  set(${NAME}_REPO_TAG master)
endif()
set(${NAME}_FORCE_BUILD ON)
set(${NAME}_SOURCE \${CMAKE_SOURCE_DIR})")

  file(WRITE ${_dependsIn}
    "config.${${NAME}_GROUP} ${${${NAME}_GROUP}_CONFIGURL} master")

  file(WRITE ${_scriptdir}/writeDeps.cmake "
list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/CMake
  ${CMAKE_SOURCE_DIR}/CMake/common)
include(UpdateFile)
update_file(${_fpIn} ${_fpOut})
update_file(${_ciIn} ${_ciOut})
update_file(${_configIn} ${_configOut})
update_file(${_dependsIn} ${_dependsOut})
update_file(${_reqIn} ${_reqOut})
")

  setup_scm(${name})
  set(_rmGeneratedLast)
  foreach(_rmGenerated ${_generated})
    get_filename_component(_baseGenerated ${_rmGenerated} NAME)
    ExternalProject_Add_Step(${name} rm${_baseGenerated}
      COMMENT "Resetting ${_baseGenerated}"
      COMMAND ${SCM_RESET} ${_rmGenerated} || ${CMAKE_COMMAND} -E remove ${_rmGenerated}
      WORKING_DIRECTORY "${${NAME}_SOURCE}"
      DEPENDEES mkdir ${_rmGeneratedLast} DEPENDERS download ALWAYS 1)
    set(_rmGeneratedLast rm${_baseGenerated})
  endforeach()

  ExternalProject_Add_Step(${name} Generate
    COMMENT "Updating ${_generated}"
    COMMAND ${CMAKE_COMMAND} -DBUILDYARD:PATH=${CMAKE_SOURCE_DIR}
            -P ${_scriptdir}/writeDeps.cmake
    DEPENDEES update DEPENDERS configure DEPENDS ${${NAME}_CONFIGFILE}
    )
endfunction()
