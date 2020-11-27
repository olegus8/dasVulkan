options indenting = 4
options no_aot = true

require math

require daslib/safe_addr
require vulkan
require internal/device


def with_swap_chain(
    device : VkDevice#;
    phys_dev : VkPhysicalDevice#;
    surface : VkSurfaceKHR#;
    window : GLFWwindow_DasHandle#;
    surf_fmt : VkSurfaceFormatKHR implicit;
    present_mode : VkPresentModeKHR#;
    b : block<(sc:VkSwapchainKHR#)>
)
    let caps <- phys_dev |> get_capabilities(surface)
    let extent <- phys_dev |> get_swap_extent(surface, window)

    // we want at least one spare image for multi-buffering
    var img_count : uint = caps.minImageCount + 1u
    if caps.maxImageCount > 0u
        img_count = min(img_count, caps.maxImageCount)

    let create_info = [[VkSwapchainCreateInfoKHR
        sType = VkStructureType VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        surface = surface,
        minImageCount = img_count,
        imageFormat = surf_fmt.format,
        imageColorSpace = surf_fmt.colorSpace,
        imageExtent = extent,
        imageArrayLayers = 1u, // 2 for stereoscopic
        imageUsage = uint(
            VkImageUsageFlagBits VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT),
        imageSharingMode = VkSharingMode VK_SHARING_MODE_EXCLUSIVE,
        preTransform = caps.currentTransform,
        compositeAlpha = (
            VkCompositeAlphaFlagBitsKHR VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR),
        presentMode = present_mode,
        clipped = uint(VK_TRUE)
    ]]

    var swap_chain : VkSwapchainKHR
    verify(VkResult VK_SUCCESS == device |> vkCreateSwapchainKHR(
        safe_addr(create_info), null, safe_addr(swap_chain)))
    b |> invoke(swap_chain)
    device |> vkDestroySwapchainKHR(swap_chain, null)


def with_swap_chain_images(device : VkDevice#; swap_chain : VkSwapchainKHR#;
    b : block<(d:array<VkImage>#)>
)
    var images : array<VkImage>
    var count : uint
    verify(VkResult VK_SUCCESS == device |> vkGetSwapchainImagesKHR(
        swap_chain, safe_addr(count), null))
    images |> resize(int(count))
    images |> lock() <| $(timages)
        verify(VkResult VK_SUCCESS == device |> vkGetSwapchainImagesKHR(
            swap_chain, safe_addr(count), addr(timages[0])))
        b |> invoke(timages)
    delete images


def with_swap_chain_image_views(
    device : VkDevice#;
    images : array<VkImage>#;
    surf_fmt : VkSurfaceFormatKHR implicit;
    b : block<(d:array<VkImageView>#)>
)
    var views : array<VkImageView>
    views |> resize(images |> length())
    for image, view in images, views
        let no_swizzle = VkComponentSwizzle VK_COMPONENT_SWIZZLE_IDENTITY
        let create_info <- [[VkImageViewCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            image = image,
            viewType = VkImageViewType VK_IMAGE_VIEW_TYPE_2D,
            format = surf_fmt.format,
            components = [[VkComponentMapping
                r = no_swizzle,
                g = no_swizzle,
                b = no_swizzle,
                a = no_swizzle]],
            subresourceRange = [[VkImageSubresourceRange
                aspectMask = uint(
                    VkImageAspectFlagBits VK_IMAGE_ASPECT_COLOR_BIT),
                baseMipLevel = 0u,
                levelCount = 1u,
                baseArrayLayer = 0u,
                layerCount = 1u]]
        ]]
        verify(VkResult VK_SUCCESS == device |> vkCreateImageView(
            safe_addr(create_info), null, safe_addr(view)))

    views |> lock() <| $(tviews)
        b |> invoke(tviews)

    for view in views
        device |> vkDestroyImageView(view, null)
    delete views


def with_swap_chain_framebuffers(
    device      : VkDevice#;
    phys_dev    : VkPhysicalDevice#;
    surface     : VkSurfaceKHR#;
    window      : GLFWwindow_DasHandle#;
    views       : array<VkImageView>#;
    render_pass : VkRenderPass#;
    b : block<(fbs:array<VkFramebuffer>#)>
)
    let extent <- phys_dev |> get_swap_extent(surface, window)
    var fbufs : array<VkFramebuffer>
    fbufs |> resize(views |> length())
    fbufs |> lock() <| $(tfbufs)
        for tfbuf, view in tfbufs, views
            var pview : VkImageView const ?
            unsafe
                pview = reinterpret<VkImageView const ?>(addr(view))
            let create_info <- [[VkFramebufferCreateInfo
                sType = (VkStructureType
                    VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO),
                renderPass = render_pass,

                //TODO: make it work. says "can only dereference simple type"
                attachmentCount = 1u, 

                pAttachments = pview,
                width = extent.width,
                height = extent.height,
                layers = 1u
            ]]
            verify(VkResult VK_SUCCESS == device |> vkCreateFramebuffer(
                safe_addr(create_info), null, addr(tfbuf)))
        b |> invoke(tfbufs)
    for fbuf in fbufs
        device |> vkDestroyFramebuffer(fbuf, null)
    delete fbufs
