cmake_minimum_required(VERSION 3.18)
project(realtime_audio_apm)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_C_STANDARD 11)

# Build the WebRTC audio processing library as a subdirectory.
add_subdirectory(webrtc-audio-processing)

# Build the JNI bridge as a shared library.
add_library(webrtc_apm_jni SHARED webrtc_apm_jni.cpp)

target_include_directories(webrtc_apm_jni PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/webrtc-audio-processing/webrtc
    ${CMAKE_CURRENT_SOURCE_DIR}/webrtc-audio-processing/abseil-cpp
)

target_link_libraries(webrtc_apm_jni PRIVATE
    webrtc_apm_wrapper
    log
)

# 16KB page alignment for Android 15+ compatibility.
target_link_options(webrtc_apm_jni PRIVATE "-Wl,-z,max-page-size=16384")
