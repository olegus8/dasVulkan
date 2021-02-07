IF(NOT DAS_VULKAN_INCLUDED)
    SET(DAS_VULKAN_INCLUDED TRUE)
    MESSAGE(STATUS "dasVulkan module included.")

    IF(EXISTS ${CMAKE_SOURCE_DIR}/modules/dasBinder/CMakeLists.txt)
        INCLUDE(${CMAKE_SOURCE_DIR}/modules/dasBinder/CMakeLists.txt)
    ENDIF()

    SET(DAS_VULKAN_DIR ${CMAKE_SOURCE_DIR}/modules/dasVulkan)

    LIST(APPEND CMAKE_MODULE_PATH ${DAS_VULKAN_DIR})

    FIND_PACKAGE(Vulkan)
    FIND_PACKAGE(glfw3)
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

    IF(NOT Vulkan_FOUND OR NOT glfw3_FOUND OR NOT DAS_VULKAN_GLSL_EXE)
        MESSAGE(STATUS "Prerequisites not found. Not building dasVulkan.")
    ELSE()
        SET(DAS_VULKAN_MODULE_SRC
            ${DAS_VULKAN_DIR}/daslib/internal/generated.das
            ${DAS_VULKAN_DIR}/include/dasVulkan/headers_to_bind.h
            ${DAS_VULKAN_DIR}/include/dasVulkan/module_custom.h
            ${DAS_VULKAN_DIR}/include/dasVulkan/module.h
            ${DAS_VULKAN_DIR}/include/dasVulkan/module_generated.h
            ${DAS_VULKAN_DIR}/src/custom.cpp
            ${DAS_VULKAN_DIR}/src/module.cpp
            ${DAS_VULKAN_DIR}/src/module_boost_generated.inc
            ${DAS_VULKAN_DIR}/src/module_generated_add.inc
            ${DAS_VULKAN_DIR}/src/module_generated_add_1.cpp
            ${DAS_VULKAN_DIR}/src/module_generated_add_2.cpp
            ${DAS_VULKAN_DIR}/src/module_generated_add_3.cpp
            ${DAS_VULKAN_DIR}/src/module_generated_add_4.cpp
            ${DAS_VULKAN_DIR}/src/module_generated_add_5.cpp
            ${DAS_VULKAN_DIR}/src/module_generated_add_6.cpp
            ${DAS_VULKAN_DIR}/src/module_generated_add_7.cpp
            ${DAS_VULKAN_DIR}/src/module_generated_add_8.cpp
            ${DAS_VULKAN_DIR}/src/module_generated_add_9.cpp
            ${DAS_VULKAN_DIR}/src/module_generated_add_10.cpp
            ${DAS_VULKAN_DIR}/src/module_generated_add_11.cpp
            ${DAS_VULKAN_DIR}/src/module_generated_add_12.cpp
            ${DAS_VULKAN_DIR}/src/module_generated_add_13.cpp
            ${DAS_VULKAN_DIR}/src/module_generated_add_14.cpp
            ${DAS_VULKAN_DIR}/src/module_generated_add_15.cpp
            ${DAS_VULKAN_DIR}/src/module_generated_add_16.cpp
        )

        ADD_MODULE_LIB(libDasModuleVulkan)
        ADD_MODULE_CPP(vulkan)
        ADD_MODULE_NATIVE(vulkan_boost)

        ADD_LIBRARY(libDasModuleVulkan ${DAS_VULKAN_MODULE_SRC})
        TARGET_LINK_LIBRARIES(libDasModuleVulkan
            ${Vulkan_LIBRARY}
            glfw::glfw
        )
        ADD_DEPENDENCIES(libDasModuleVulkan libDaScript)
        TARGET_INCLUDE_DIRECTORIES(libDasModuleVulkan PUBLIC
            ${Vulkan_INCLUDE_DIR}
            ${glfw_INCLUDE_DIR}
            ${DAS_VULKAN_DIR}/include
        )
        SETUP_CPP11(libDasModuleVulkan)
        
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

        IF(DAS_BINDER_INCLUDED)
            DAS_BINDER(
                ${DAS_VULKAN_DIR}/include/dasVulkan/headers_to_bind.h
                ${DAS_VULKAN_DIR}/src/module_generated
                ${DAS_VULKAN_DIR}/include/dasVulkan/module_generated
                ${DAS_VULKAN_DIR}/src/binding_config.py
                "${DAS_VULKAN_INCLUDE_DIRS}"
                "${DAS_VULKAN_BINDER_DEPS}"
                "${DAS_VULKAN_BINDER_EXTRA_OUTPUTS}"
            )
        ELSE()
            MESSAGE(STATUS "dasBinder not found. Using pre-generated Vulkan bindings.")
        ENDIF()

        DAS_VULKAN_COMPILE_SHADER(${DAS_VULKAN_DIR}/example/vert.glsl vert)
        DAS_VULKAN_COMPILE_SHADER(${DAS_VULKAN_DIR}/example/frag.glsl frag)
        ADD_CUSTOM_TARGET(dasVulkanExample ALL DEPENDS
            ${DAS_VULKAN_DIR}/example/vert.spv
            ${DAS_VULKAN_DIR}/example/frag.spv
        )
        ADD_DEPENDENCIES(dasVulkanExample daScript)
    ENDIF()
ENDIF()
