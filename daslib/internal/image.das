options indenting = 4
options no_aot = true

require math

require daslib/safe_addr
require daslib/defer
require vulkan
require internal/device


let
    COMPONENT_MAPPING_IDENTITY <- [[VkComponentMapping
        r <- [[VkComponentSwizzle VK_COMPONENT_SWIZZLE_IDENTITY]],
        g <- [[VkComponentSwizzle VK_COMPONENT_SWIZZLE_IDENTITY]],
        b <- [[VkComponentSwizzle VK_COMPONENT_SWIZZLE_IDENTITY]],
        a <- [[VkComponentSwizzle VK_COMPONENT_SWIZZLE_IDENTITY]]
    ]]

    IMAGE_SUBRESOURCE_RANGE_SINGLE_COLOR <- [[VkImageSubresourceRange
        aspectMask = uint(
            VkImageAspectFlagBits VK_IMAGE_ASPECT_COLOR_BIT),
        baseMipLevel = 0u,
        levelCount = 1u,
        baseArrayLayer = 0u,
        layerCount = 1u
    ]]


struct ImageView
    device : VkDevice
    view : VkImageView


def create_image_view(
    device : VkDevice implicit;
    image : VkImage implicit;
    format : VkFormat;
    view_type : VkImageViewType;
    subresource_range : VkImageSubresourceRange implicit;
    components : VkComponentMapping implicit;
    flags : uint = 0u
) : ImageView
    let info <- [[VkImageViewCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
        image = image,
        viewType = view_type,
        format = format,
        components = components,
        subresourceRange = subresource_range
    ]]
    var view : ImageView
    unsafe
        view.device = reinterpret<VkDevice>(device)
    verify(VkResult VK_SUCCESS == device |> vkCreateImageView(
        safe_addr(info), null, safe_addr(view.view)))


def finalize(var view : ImageView)
    view.device |> vkDestroyImageView(view.view, null)
    memzero(view)
