IF(NOT DAS_VULKAN_INCLUDED)
    SET(DAS_VULKAN_INCLUDED TRUE)
    MESSAGE(STATUS "dasVulkan module included.")

    INCLUDE(${CMAKE_SOURCE_DIR}/modules/dasBinder/CMakeLists.txt)

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
        SET(DAS_VULKAN_DIR ${CMAKE_SOURCE_DIR}/modules/dasVulkan)

        SET(DAS_VULKAN_MODULE_SRC
            ${DAS_VULKAN_DIR}/src/headers_to_bind.h
            ${DAS_VULKAN_DIR}/src/module.cpp
            ${DAS_VULKAN_DIR}/src/module_generated.inc
        )

        LIST(APPEND DAS_MODULES_LIBS libDasModuleVulkan)

        ADD_LIBRARY(libDasModuleVulkan ${DAS_VULKAN_MODULE_SRC})
        TARGET_LINK_LIBRARIES(libDasModuleVulkan
            ${Vulkan_LIBRARY}
            glfw
        )
        ADD_DEPENDENCIES(libDasModuleVulkan libDaScript)
        TARGET_INCLUDE_DIRECTORIES(libDasModuleVulkan PUBLIC
            ${Vulkan_INCLUDE_DIR}
        )
        SETUP_CPP11(libDasModuleVulkan)
        
        GET_TARGET_PROPERTY(DAS_VULKAN_INCLUDE_DIRS libDasModuleVulkan INCLUDE_DIRECTORIES)

        SET(DAS_VULKAN_HEADERS_TO_BIND
            ${DAS_VULKAN_DIR}/src/headers_to_bind.h
        )

        IF(DAS_BINDER_INCLUDED)
            DAS_BINDER(
                ${DAS_VULKAN_DIR}/src/headers_to_bind.h
                ${DAS_VULKAN_DIR}/src/module_generated.inc
                ${DAS_VULKAN_DIR}/src/binding_config.py
                ${DAS_VULKAN_INCLUDE_DIRS}
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
    ENDIF()
ENDIF()
