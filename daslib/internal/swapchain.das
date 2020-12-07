options indenting = 4
options no_aot = true

require math

require daslib/safe_addr
require daslib/defer
require vulkan
require device_ex
require image
require framebuffer
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
    window          : GLFWwindow_DasHandle implicit;
    surf_fmt        : SurfaceFormatKHR;
    vk_surf_fmt     : VkSurfaceFormatKHR; //TODO: remove
    present_mode    : VkPresentModeKHR implicit;
    render_pass     : VkRenderPass implicit;
    b : block<(sc:SwapchainEx implicit)>
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

    var views <- vk_device |> create_swapchain_image_views(
        vk_images, vk_surf_fmt)
    var framebuffers <- vk_device |> create_swapchain_framebuffers(
        phys_dev, surface, window, views,
        render_pass)
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


[private]
def create_swapchain_image_views(
    device : VkDevice implicit;
    images : array<VkImage> implicit;
    surf_fmt : VkSurfaceFormatKHR implicit
)
    var views : array<ImageView>
    views |> resize(images |> length())
    for image, view in images, views
        view <- device |> create_image_view(image, surf_fmt.format,
            VkImageViewType VK_IMAGE_VIEW_TYPE_2D,
            IMAGE_SUBRESOURCE_RANGE_SINGLE_COLOR,
            COMPONENT_MAPPING_IDENTITY)
    return <- views


[private]
def create_swapchain_framebuffers(
    device      : VkDevice implicit;
    phys_dev    : PhysicalDevice;
    surface     : SurfaceKHR;
    window      : GLFWwindow_DasHandle implicit;
    views       : array<ImageView> implicit;
    render_pass : VkRenderPass implicit
) : array<Framebuffer>
    let extent <- phys_dev |> get_swap_extent(surface, window)
    var fbufs : array<Framebuffer>
    fbufs |> resize(views |> length())
    for fbuf, view in fbufs, views
        fbuf <- create_framebuffer([device=device, render_pass=render_pass,
            attachment=view.view, width=extent.width, height=extent.height,
            layers=1u])
    return <- fbufs
