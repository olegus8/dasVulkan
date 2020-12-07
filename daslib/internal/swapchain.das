options indenting = 4
options no_aot = true

require math

require daslib/safe_addr
require daslib/defer
require vulkan
require device_ex
require image
require generated


struct SwapchainEx
    swapchain       : VkSwapchainKHR
    images          : array<VkImage>
    views           : array<ImageView>
    framebuffers    : array<Framebuffer>


def with_swapchain_ex(
    device          : Device;
    phys_dev        : PhysicalDevice;
    surface         : SurfaceKHR;
    window          : GLFWwindow_DasHandle;
    surf_fmt        : SurfaceFormatKHR;
    present_mode    : VkPresentModeKHR;
    render_pass     : RenderPass;
    b : block<(sc:SwapchainEx)>
)
    var vk_device = device.device

    var swapchain <- device |> create_multibuffered_swapchain(
        phys_dev, surface, window, surf_fmt, present_mode)
    defer() <| ${ delete swapchain; }

    let vk_swapchain = swapchain.swapchain_khr

    var images <- device |> get_swapchain_images_khr(swapchain)
    defer() <| ${ delete images; }

    var vk_images <- [{ for image in images ; image.image }]
    defer() <| ${ delete vk_images; }

    var views <- [{ for image in images;
        device |> create_image_view([[ ImageViewCreateInfo
            image = image,
            format = surf_fmt.format,
            view_type = VkImageViewType VK_IMAGE_VIEW_TYPE_2D,
            subresource_range = IMAGE_SUBRESOURCE_RANGE_SINGLE_COLOR,
            components = COMPONENT_MAPPING_IDENTITY
        ]])}]
    defer() <| ${ delete views; }

    let extent <- phys_dev |> get_swap_extent(surface, window)

    var framebuffers : array<Framebuffer>
    defer() <| ${ delete framebuffers; }

    framebuffers |> resize(views |> length())
    for fbuf, view in framebuffers, views
        var create_info <- [[FramebufferCreateInfo
            render_pass = render_pass,
            attachments <- [{auto[] view}],
            width = extent.width,
            height = extent.height,
            layers = 1u
        ]]
        defer() <|
            create_info.attachments |> resize(0)
            memzero(create_info.render_pass)
            delete create_info

        fbuf <- device |> create_framebuffer(create_info)

    var sc <- [[SwapchainEx
        swapchain = vk_swapchain,
        images <- vk_images,
        views <- views,
        framebuffers <- framebuffers
    ]]
    defer() <| ${ delete sc; }
    b |> invoke(sc)


def finalize(var sc : SwapchainEx)
    delete sc.framebuffers
    delete sc.views
    delete sc.images
    memzero(sc)


def create_multibuffered_swapchain(
    device          : Device;
    phys_dev        : PhysicalDevice;
    surface         : SurfaceKHR;
    window          : GLFWwindow_DasHandle;
    surf_fmt        : SurfaceFormatKHR;
    present_mode    : VkPresentModeKHR
) : SwapchainKHR
    let caps <- phys_dev|>get_physical_device_surface_capabilities_khr(surface)

    // we want at least one spare image for multi-buffering
    var img_count : uint = caps.min_image_count + 1u
    if caps.max_image_count > 0u
        img_count = min(img_count, caps.max_image_count)

    return <- device |> create_swapchain_khr([[SwapchainCreateInfoKHR
            surface = surface,
            min_image_count = img_count,
            image_format = surf_fmt.format,
            image_color_space = surf_fmt.color_space,
            image_extent <- phys_dev |> get_swap_extent(surface, window),
            image_array_layers = 1u, // 2 for stereoscopic
            image_usage = uint(
                VkImageUsageFlagBits VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT),
            image_sharing_mode = VkSharingMode VK_SHARING_MODE_EXCLUSIVE,
            pre_transform = caps.current_transform,
            composite_alpha = (
                VkCompositeAlphaFlagBitsKHR VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR),
            present_mode = present_mode,
            clipped = uint(VK_TRUE)
        ]])


//////////////////
//
// private
//
//////////////////
