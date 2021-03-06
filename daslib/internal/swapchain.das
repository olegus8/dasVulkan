options indenting = 4
options no_aot = true

require math

require daslib/defer
require daslib/safe_addr
require vulkan
require device
require image
require generated
require framebuffer
require window


def create_swapchain_image_view(
    device      : Device;
    image       : Image;
    surf_fmt    : SurfaceFormatKHR
) : ImageView
    return <- device |> create_image_view([[ ImageViewCreateInfo
        image = image,
        format = surf_fmt.format,
        view_type = VkImageViewType VK_IMAGE_VIEW_TYPE_2D,
        subresource_range = IMAGE_SUBRESOURCE_RANGE_SINGLE_COLOR,
        components = COMPONENT_MAPPING_IDENTITY
    ]])


def create_multibuffered_swapchain(
    device          : Device;
    phys_dev        : PhysicalDevice;
    surface         : SurfaceKHR;
    window          : Window;
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


def queue_present_khr(
    queue : Queue;
    swapchain : SwapchainKHR;
    image_index : uint;
    wait_semaphore : Semaphore const ? implicit = [[ Semaphore const ? ]];
    var result : VkResult? = [[VkResult?]]
)
    var wait_semaphores : array<Semaphore>
    if wait_semaphore != null
        wait_semaphores |> push(weak_copy(*wait_semaphore))

    var info <- [[ PresentInfoKHR
        wait_semaphores <- wait_semaphores,
        swapchains <- [{ auto[] weak_copy(swapchain) }],
        image_indices <- [{ auto[] image_index }]
    ]]
    defer() <| ${ delete info; }

    queue |> queue_present_khr(info, result)


def present(
    queue : Queue;
    swapchain : SwapchainKHR;
    image_index : uint;
    sem_to_wait : Semaphore
) : bool
    var result : VkResult
    var p_result : VkResult ?
    unsafe
        p_result = addr(result)
    queue |> queue_present_khr(
        swapchain, image_index, safe_addr(sem_to_wait), p_result)
    if result == VkResult VK_SUCCESS
        return true
    assert(result == VkResult VK_ERROR_OUT_OF_DATE_KHR ||
        result == VkResult VK_SUBOPTIMAL_KHR)
    return false


def with_next_image(
    device : Device;
    swapchain : SwapchainKHR;
    sem_to_signal : Semaphore;
    b : block<(i:uint)>
)
    var result : VkResult
    var p_result : VkResult ?
    unsafe
        p_result = addr(result)
    let img_index = device |> acquire_next_image_khr(
        swapchain, ULONG_MAX, sem_to_signal, [[Fence]], p_result)
    if result == VkResult VK_SUCCESS
        b |> invoke(img_index)
    else
        assert(result == VkResult VK_ERROR_OUT_OF_DATE_KHR ||
            result == VkResult VK_SUBOPTIMAL_KHR)
