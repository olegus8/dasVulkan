IF(NOT DAS_VULKAN_INCLUDED)
    SET(DAS_VULKAN_INCLUDED TRUE)
    MESSAGE(STATUS "dasVulkan module included.")

    INCLUDE(${CMAKE_SOURCE_DIR}/modules/dasGlfw/CMakeLists.txt)
    INCLUDE(${CMAKE_SOURCE_DIR}/modules/dasBinder/CMakeLists.txt)

    SET(DAS_VULKAN_DIR ${CMAKE_SOURCE_DIR}/modules/dasVulkan)

    LIST(APPEND CMAKE_MODULE_PATH ${DAS_VULKAN_DIR})

    FIND_PACKAGE(Vulkan)
    FIND_PROGRAM(DAS_VULKAN_GLSL_EXE glslc)

    MACRO(DAS_VULKAN_COMPILE_SHADER input stage)
        IF(NOT DAS_VULKAN_GLSL_EXE)
            MESSAGE(STATUS "glslc not found. Will use precompiled shaders.")
        ELSE()
            get_filename_component(input_src ${input} ABSOLUTE)
            get_filename_component(input_dir ${input_src} DIRECTORY)
            get_filename_component(input_name ${input} NAME_WE)
            get_filename_component(input_name_ext ${input} NAME)
            ADD_CUSTOM_COMMAND(
                DEPENDS ${input_src}
                OUTPUT ${input_dir}/${input_name}.spv
                WORKING_DIRECTORY ${input_dir}
                VERBATIM
                COMMAND ${DAS_VULKAN_GLSL_EXE} -fshader-stage=${stage}
                    ${input_name_ext} -o ${input_name}.spv
                COMMENT "glsl ${input} to ${input_dir}/${input_name}.spv")
        ENDIF()
    ENDMACRO()

    IF(NOT Vulkan_FOUND OR NOT DAS_VULKAN_GLSL_EXE)
        MESSAGE(STATUS "Prerequisites not found. Not building dasVulkan.")
    ELSE()
        SET(DAS_VULKAN_NUM_PARTS 16)
        SET(DAS_VULKAN_GENERATED_CPP)
        DAS_BINDER_GET_GENERATED_CPP(
            ${DAS_VULKAN_NUM_PARTS}
            DAS_VULKAN_GENERATED_CPP
            ${DAS_VULKAN_DIR}/src/module_generated
        )

        SET(DAS_VULKAN_MODULE_SRC
            ${DAS_VULKAN_DIR}/daslib/internal/generated.das
            ${DAS_VULKAN_DIR}/include/dasVulkan/headers_to_bind.h
            ${DAS_VULKAN_DIR}/include/dasVulkan/module.h
            ${DAS_VULKAN_DIR}/include/dasVulkan/module_generated.h.inc
            ${DAS_VULKAN_DIR}/src/custom.cpp
            ${DAS_VULKAN_DIR}/src/module.cpp
            ${DAS_VULKAN_DIR}/src/module_boost_generated.inc
            ${DAS_VULKAN_DIR}/src/module_generated.cpp.inc
            ${DAS_VULKAN_GENERATED_CPP}
        )

        ADD_MODULE_LIB(libDasModuleVulkan)
        ADD_MODULE_CPP(vulkan)
        ADD_MODULE_NATIVE(vulkan_boost)

        ADD_LIBRARY(libDasModuleVulkan ${DAS_VULKAN_MODULE_SRC})
        TARGET_LINK_LIBRARIES(libDasModuleVulkan
            ${Vulkan_LIBRARY}
        )
        ADD_DEPENDENCIES(libDasModuleVulkan libDaScript)
        TARGET_INCLUDE_DIRECTORIES(libDasModuleVulkan PUBLIC
            ${Vulkan_INCLUDE_DIR}
            ${DAS_VULKAN_DIR}/include
        )
        SETUP_CPP11(libDasModuleVulkan)

        DAS_VULKAN_COMPILE_SHADER(${DAS_VULKAN_DIR}/example/vert.glsl vert)
        DAS_VULKAN_COMPILE_SHADER(${DAS_VULKAN_DIR}/example/frag.glsl frag)
        ADD_CUSTOM_TARGET(dasVulkanExample ALL DEPENDS
            ${DAS_VULKAN_DIR}/example/vert.spv
            ${DAS_VULKAN_DIR}/example/frag.spv
        )
        ADD_DEPENDENCIES(dasVulkanExample daScript)
        GET_TARGET_PROPERTY(DAS_VULKAN_INCLUDE_DIRS libDasModuleVulkan INCLUDE_DIRECTORIES)

        SET(DAS_VULKAN_HEADERS_TO_BIND
            ${DAS_VULKAN_DIR}/include/dasVulkan/headers_to_bind.h
        )

        SET(DAS_VULKAN_BINDER_DEPS
            ${DAS_VULKAN_DIR}/src/boost_generator.py
            ${DAS_VULKAN_DIR}/src/boost_preamble.das
        )
        SET(DAS_VULKAN_BINDER_EXTRA_OUTPUTS
            ${DAS_VULKAN_DIR}/daslib/internal/generated.das
            ${DAS_VULKAN_DIR}/src/module_boost_generated.inc
        )

        DAS_BINDER(
            ${DAS_VULKAN_NUM_PARTS}
            ${DAS_VULKAN_DIR}/include/dasVulkan/headers_to_bind.h
            ${DAS_VULKAN_DIR}/src/module_generated
            ${DAS_VULKAN_DIR}/include/dasVulkan/module_generated.h.inc
            ${DAS_VULKAN_DIR}/include/dasVulkan/module.h
            ${DAS_VULKAN_DIR}/src/binding_config.py
            "${DAS_VULKAN_INCLUDE_DIRS}"
            "${DAS_VULKAN_BINDER_DEPS}"
            "${DAS_VULKAN_BINDER_EXTRA_OUTPUTS}"
        )
    ENDIF()
ENDIF()
