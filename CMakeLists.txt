IF(NOT DAS_VULKAN_INCLUDED)
    SET(DAS_VULKAN_INCLUDED TRUE)
    MESSAGE(STATUS "dasVulkan module included.")

    INCLUDE(${CMAKE_SOURCE_DIR}/modules/dasBinder/CMakeLists.txt)

    FIND_PACKAGE(Vulkan)
    FIND_PACKAGE(glfw3)

    IF(NOT Vulkan_FOUND OR NOT glfw3_FOUND)
        MESSAGE(STATUS "Prerequisites not found. Not building dasVulkan.")
    ELSE()
        SET(DAS_VULKAN_DIR ${CMAKE_SOURCE_DIR}/modules/dasVulkan)

        SET(DAS_VULKAN_EXAMPLE_SRC
            ${DAS_VULKAN_DIR}/example/main.cpp
            ${DAS_VULKAN_DIR}/example/vulkan_headers_to_bind.h
            ${DAS_VULKAN_DIR}/example/vulkan_module.cpp
            ${DAS_VULKAN_DIR}/example/vulkan_module_generated.inc
        )

        ADD_EXECUTABLE(dasVulkanExample ${DAS_VULKAN_EXAMPLE_SRC})
        TARGET_LINK_LIBRARIES(dasVulkanExample
            libDaScript
            ${Vulkan_LIBRARY}
            glfw
        )
        TARGET_INCLUDE_DIRECTORIES(dasVulkanExample PUBLIC
            ${Vulkan_INCLUDE_DIR}
        )
        SETUP_CPP11(dasVulkanExample)
        
        GET_TARGET_PROPERTY(DAS_VULKAN_EXAMPLE_INCLUDE_DIRS dasVulkanExample INCLUDE_DIRECTORIES)

        SET(DAS_VULKAN_HEADERS_TO_BIND
            ${DAS_VULKAN_DIR}/example/vulkan_headers_to_bind.h
        )

        IF(DAS_BINDER_INCLUDED)
            DAS_BINDER(
                ${DAS_VULKAN_DIR}/example/vulkan_headers_to_bind.h
                ${DAS_VULKAN_DIR}/example/vulkan_module_generated.inc
                ${DAS_VULKAN_DIR}/example/vulkan_binding_config.py
                ${DAS_VULKAN_EXAMPLE_INCLUDE_DIRS}
            )
        ELSE()
            MESSAGE(STATUS "dasBinder not found. Using pre-generated Vulkan bindings.")
        ENDIF()
    ENDIF()
ENDIF()
