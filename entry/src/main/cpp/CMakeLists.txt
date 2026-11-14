cmake_minimum_required(VERSION 3.5.0)
project(codecprobe)
add_library(codecprobe SHARED codec_probe.cpp)
target_link_libraries(codecprobe PUBLIC libace_napi.z.so libnative_media_codecbase.so libnative_media_core.so libhilog_ndk.z.so)
