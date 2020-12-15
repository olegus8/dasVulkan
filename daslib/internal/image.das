options indenting = 4
options no_aot = true

require vulkan
require generated


let
    COMPONENT_MAPPING_IDENTITY <- [[ComponentMapping
        r = VkComponentSwizzle VK_COMPONENT_SWIZZLE_IDENTITY,
        g = VkComponentSwizzle VK_COMPONENT_SWIZZLE_IDENTITY,
        b = VkComponentSwizzle VK_COMPONENT_SWIZZLE_IDENTITY,
        a = VkComponentSwizzle VK_COMPONENT_SWIZZLE_IDENTITY
    ]]

    IMAGE_SUBRESOURCE_RANGE_SINGLE_COLOR <- [[ImageSubresourceRange
        aspect_mask = uint(
            VkImageAspectFlagBits VK_IMAGE_ASPECT_COLOR_BIT),
        base_mip_level = 0u,
        level_count = 1u,
        base_array_layer = 0u,
        layer_count = 1u
    ]]
