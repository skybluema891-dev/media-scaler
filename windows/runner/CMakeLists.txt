cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Bundle the local GPL FFmpeg tools next to the application. The Dart service
# resolves this relative path first, so end users do not need a system install.
set(FFMPEG_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../tools/ffmpeg/windows")
set(FFMPEG_OUTPUT_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>/tools/ffmpeg/windows")
add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory "${FFMPEG_OUTPUT_DIR}"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${FFMPEG_SOURCE_DIR}/ffmpeg.exe"
    "${FFMPEG_OUTPUT_DIR}/ffmpeg.exe"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${FFMPEG_SOURCE_DIR}/ffprobe.exe"
    "${FFMPEG_OUTPUT_DIR}/ffprobe.exe"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${FFMPEG_SOURCE_DIR}/FFMPEG-LICENSE.txt"
    "${FFMPEG_OUTPUT_DIR}/FFMPEG-LICENSE.txt"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/../../THIRD_PARTY_NOTICES.txt"
    "$<TARGET_FILE_DIR:${BINARY_NAME}>/THIRD_PARTY_NOTICES.txt"
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${CMAKE_CURRENT_SOURCE_DIR}/../../パラメーター設定ガイド.txt"
    "$<TARGET_FILE_DIR:${BINARY_NAME}>/パラメーター設定ガイド.txt"
  VERBATIM
)

set(AI_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../tools/ai/windows")
if(EXISTS "${AI_SOURCE_DIR}/python/python.exe")
  add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
      "${AI_SOURCE_DIR}" "$<TARGET_FILE_DIR:${BINARY_NAME}>/tools/ai/windows"
    COMMAND ${CMAKE_COMMAND} -E copy_directory
      "${CMAKE_CURRENT_SOURCE_DIR}/../../tools/licenses"
      "$<TARGET_FILE_DIR:${BINARY_NAME}>/licenses"
    VERBATIM
  )
endif()
