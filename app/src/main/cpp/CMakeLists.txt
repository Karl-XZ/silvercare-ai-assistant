cmake_minimum_required(VERSION 3.22.1)

project(silvercare_mnn_runtime)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(MNN_HEADERS_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../../third_party/mnn/headers")
set(JNI_LIBS_DIR "${CMAKE_CURRENT_LIST_DIR}/../jniLibs/${ANDROID_ABI}")

if(ANDROID_ABI STREQUAL "arm64-v8a")
    function(import_mnn_library target file_name)
        add_library(${target} SHARED IMPORTED)
        set_target_properties(${target} PROPERTIES
            IMPORTED_LOCATION "${JNI_LIBS_DIR}/${file_name}"
        )
    endfunction()

    import_mnn_library(mnn_runtime libMNN.so)
    import_mnn_library(mnn_expr libMNN_Express.so)
    import_mnn_library(mnn_core libmnncore.so)
    import_mnn_library(mnn_llm libllm.so)
    import_mnn_library(mnn_audio libMNNAudio.so)
    import_mnn_library(mnn_opencv libMNNOpenCV.so)
    import_mnn_library(mnn_opencl libMNN_CL.so)
    import_mnn_library(mnn_vulkan libMNN_Vulkan.so)

    add_library(silvercare_mnn_runtime SHARED
        silvercare_mnn_runtime.cpp
    )

    target_include_directories(silvercare_mnn_runtime PRIVATE
        "${MNN_HEADERS_DIR}/include"
        "${MNN_HEADERS_DIR}"
    )

    find_library(log_lib log)

    target_link_libraries(silvercare_mnn_runtime
        mnn_llm
        mnn_runtime
        mnn_expr
        mnn_core
        mnn_audio
        mnn_opencv
        mnn_opencl
        mnn_vulkan
        ${log_lib}
    )
else()
    add_library(silvercare_mnn_runtime SHARED
        silvercare_mnn_runtime_stub.cpp
    )
endif()
