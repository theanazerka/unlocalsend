#----------------------------------------------------------------
# Generated CMake target import file for configuration "Release".
#----------------------------------------------------------------

# Commands may need to know the format version.
set(CMAKE_IMPORT_FILE_VERSION 1)

# Import target "de265" for configuration "Release"
set_property(TARGET de265 APPEND PROPERTY IMPORTED_CONFIGURATIONS RELEASE)
set_target_properties(de265 PROPERTIES
  IMPORTED_LINK_INTERFACE_LANGUAGES_RELEASE "CXX"
  IMPORTED_LOCATION_RELEASE "${_IMPORT_PREFIX}/lib/libde265.a"
  )

list(APPEND _cmake_import_check_targets de265 )
list(APPEND _cmake_import_check_files_for_de265 "${_IMPORT_PREFIX}/lib/libde265.a" )

# Commands beyond this point should not need to know the version.
set(CMAKE_IMPORT_FILE_VERSION)
