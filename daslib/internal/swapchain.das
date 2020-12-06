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
    device          : VkDevice implicit;
    phys_dev        : PhysicalDevice;
    surface         : SurfaceKHR;
    window          : GLFWwindow_DasHandle implicit;
    surf_fmt        : VkSurfaceFormatKHR implicit;
    present_mode    : VkPresentModeKHR implicit;
    render_pass     : VkRenderPass implicit;
    b : block<(sc:SwapchainEx implicit)>
)
    device |> with_swapchain(
        phys_dev, surface, window, surf_fmt, present_mode
    ) <| $(swapchain)
        var images <- device |> get_swapchain_images(swapchain)
        var views <- device |> create_swapchain_image_views(images, surf_fmt)
        var framebuffers <- device |> create_swapchain_framebuffers(
            phys_dev, surface, window, views,
            render_pass)
        var sc <- [[SwapchainEx
            swapchain = swapchain,
            images <- images,
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


//////////////////
//
// private
//
//////////////////


[private]
def with_swapchain(
    device          : VkDevice implicit;
    phys_dev        : PhysicalDevice;
    surface         : SurfaceKHR;
    window          : GLFWwindow_DasHandle implicit;
    surf_fmt        : VkSurfaceFormatKHR implicit;
    present_mode    : VkPresentModeKHR implicit;
    b : block<(sc:VkSwapchainKHR#)>
)
    let caps <- phys_dev|>get_physical_device_surface_capabilities_khr(surface)
    let extent <- phys_dev |> get_swap_extent(surface, window)

    // we want at least one spare image for multi-buffering
    var img_count : uint = caps.minImageCount + 1u
    if caps.maxImageCount > 0u
        img_count = min(img_count, caps.maxImageCount)

    let create_info = [[VkSwapchainCreateInfoKHR
        sType = VkStructureType VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        surface = surface.surface,
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

    var swapchain : VkSwapchainKHR
    verify(VkResult VK_SUCCESS == device |> vkCreateSwapchainKHR(
        safe_addr(create_info), null, safe_addr(swapchain)))
    b |> invoke(swapchain)
    device |> vkDestroySwapchainKHR(swapchain, null)


[private]
def get_swapchain_images(
    device : VkDevice implicit;
    swapchain : VkSwapchainKHR implicit
) : array<VkImage>
    var images : array<VkImage>
    var count : uint
    verify(VkResult VK_SUCCESS == device |> vkGetSwapchainImagesKHR(
        swapchain, safe_addr(count), null))
    images |> resize(int(count))
    images |> lock() <| $(timages)
        verify(VkResult VK_SUCCESS == device |> vkGetSwapchainImagesKHR(
            swapchain, safe_addr(count), addr(timages[0])))
    return <- images


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
