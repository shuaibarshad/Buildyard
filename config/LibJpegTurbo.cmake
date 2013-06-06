
set(LIBJPEGTURBO_PACKAGE_VERSION 1.2.1)
set(LIBJPEGTURBO_OPTIONAL ON)
set(LIBJPEGTURBO_DEPENDS nasm)
set(LIBJPEGTURBO_REPO_URL svn://svn.code.sf.net/p/libjpeg-turbo/code/tags/1.2.1)
set(LIBJPEGTURBO_REPO_TYPE svn)
set(LIBJPEGTURBO_SOURCE "${CMAKE_SOURCE_DIR}/src/LibJpegTurbo")
set(LIBJPEGTURBO_EXTRA
 CONFIGURE_COMMAND ${CMAKE_COMMAND} -P LibJpegTurbo_configure_cmd.cmake)
