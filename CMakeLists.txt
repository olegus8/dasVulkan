IF(NOT DAS_VULKAN_INCLUDED)
    SET(DAS_VULKAN_INCLUDED TRUE)
    MESSAGE(STATUS "dasVulkan module included.")

    include(${CMAKE_SOURCE_DIR}/modules/dasBinder/CMakeLists.txt)

    find_package(Vulkan)
    find_package(glfw3)

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

        add_executable(dasVulkanExample ${DAS_VULKAN_EXAMPLE_SRC})
        TARGET_LINK_LIBRARIES(dasVulkanExample
            libDaScript
            ${Vulkan_LIBRARY}
            glfw
        )
        TARGET_INCLUDE_DIRECTORIES(dasVulkanExample PUBLIC
            ${Vulkan_INCLUDE_DIR}
        )
        SETUP_CPP11(dasVulkanExample)
        
        get_target_property(DAS_VULKAN_INCLUDE_DIRS dasVulkanExample INCLUDE_DIRECTORIES)

        IF(DAS_BINDER_INCLUDED)
            DAS_BINDER(
                ${DAS_VULKAN_DIR}/example/vulkan_headers_to_bind.h
                ${DAS_VULKAN_DIR}/example/vulkan_module_generated.inc
                ${DAS_VULKAN_DIR}/example/vulkan_binding_config.py
                ${DAS_VULKAN_INCLUDE_DIRS}
            )
        ELSE()
            MESSAGE(STATUS "dasBinder not found. Using pre-generated Vulkan bindings.")
        ENDIF()
    ENDIF()
ENDIF()
