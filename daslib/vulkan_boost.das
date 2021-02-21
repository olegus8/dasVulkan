options indenting = 4
options no_aot = true

module vulkan_boost

require vulkan                   public
require glfw                     public
require internal/generated       public

require internal/buffer          public
require internal/command         public
require internal/core            public
require internal/debug           public
require internal/descriptor_pool public
require internal/descriptor_set  public
require internal/device          public
require internal/framebuffer     public
require internal/image           public
require internal/instance        public
require internal/memory          public
require internal/pipeline        public
require internal/queries         public
require internal/swapchain       public
require internal/sync            public
require internal/window          public


// Have to keep this goo here because "require" is not being
// hanled correctly when this is moved into one of the publicly
// shared modules above.


let
    MAX_FRAMES_IN_FLIGHT = 2


struct SimpleSwapchainIndependentState
    window       : Window
    instance     : InstanceEx
    surface      : SurfaceKHR
    phys_dev     : PhysicalDevice
    device       : Device
    queue        : Queue
    desc_pool    : DescriptorPool
    gfx_qfam     : uint
    surf_fmt     : SurfaceFormatKHR
    present_mode : VkPresentModeKHR


def finalize(var x : SimpleSwapchainIndependentState explicit)
    x.device |> device_wait_idle
    delete x.desc_pool
    delete x.device
    delete x.surface
    delete x.instance
    delete x.window


struct SimpleSwapchainDependentState
    swapchain           : SimpleSwapchain
    img_avail_sems      : array<Semaphore>
    render_done_sems    : array<Semaphore>
    frame_fences        : array<Fence>
    frames_since_start  : int
    imgs_used_by_frames : array<int>
    _device             : Device


def finalize(var s : SimpleSwapchainDependentState explicit)
    s._device |> device_wait_idle()
    delete s.imgs_used_by_frames
    delete s.swapchain
    delete s.frame_fences
    delete s.render_done_sems
    delete s.img_avail_sems
    memzero(s)


def create_simple_sis(title : string; width,height : int
) : SimpleSwapchainIndependentState
    var sis : SimpleSwapchainIndependentState
    sis.window <- create_window(width, height, title)
    sis.instance <- create_instance_ex()
    sis.surface <- sis.instance.instance |> create_window_surface(sis.window)
    sis.phys_dev <- sis.instance.instance |> find_best_physical_device(
        sis.surface, @@simple_device_score)
    sis.gfx_qfam = sis.phys_dev |> get_graphics_queue_family(sis.surface, 1)
    sis.device <- sis.phys_dev |> create_simple_device(sis.gfx_qfam)
    sis.queue <- sis.device |> get_device_queue(sis.gfx_qfam)
    sis.desc_pool <- sis.device |> create_simple_descriptor_pool
    sis.present_mode = VkPresentModeKHR VK_PRESENT_MODE_FIFO_KHR
    sis.surf_fmt <- sis.phys_dev |> find_format_like_srgb_bgra8(sis.surface)
    return <- sis


def create_simple_sds(sis : SimpleSwapchainIndependentState
) : SimpleSwapchainDependentState
    var sds <- [[ SimpleSwapchainDependentState
        _device <- weak_copy(sis.device)
    ]]
    sds.img_avail_sems <- [{for x in range(MAX_FRAMES_IN_FLIGHT);
        sis.device |> create_semaphore() }]
    sds.render_done_sems <- [{for x in range(MAX_FRAMES_IN_FLIGHT);
        sis.device |> create_semaphore() }]
    sds.frame_fences <- [{for x in range(MAX_FRAMES_IN_FLIGHT);
        sis.device |> create_fence([[FenceCreateInfo
            flags=uint(VkFenceCreateFlagBits VK_FENCE_CREATE_SIGNALED_BIT)
    ]]) }]
    sds.swapchain <- sis.device |> create_simple_swapchain(sis.phys_dev,
        sis.surface, sis.window, sis.surf_fmt, sis.present_mode,
        sis.render_pass)
    sds.imgs_used_by_frames <- [{for x in sds.swapchain.framebuffers; -1}]

    return <- sds


struct SimpleSwapchain
    swapchain       : SwapchainKHR
    images          : array<Image>
    views           : array<ImageView>
    framebuffers    : array<Framebuffer>


def finalize(var sc : SimpleSwapchain)
    delete sc.framebuffers
    delete sc.views
    delete sc.images
    delete sc.swapchain
    memzero(sc)


def create_simple_swapchain(
    device          : Device;
    phys_dev        : PhysicalDevice;
    surface         : SurfaceKHR;
    window          : Window;
    surf_fmt        : SurfaceFormatKHR;
    present_mode    : VkPresentModeKHR;
    render_pass     : RenderPass
) : SimpleSwapchain

    var swapchain <- device |> create_multibuffered_swapchain(
        phys_dev, surface, window, surf_fmt, present_mode)

    var images <- device |> get_swapchain_images_khr(swapchain)

    var views <- [{ for image in images;
        device |> create_image_view([[ ImageViewCreateInfo
            image = image,
            format = surf_fmt.format,
            view_type = VkImageViewType VK_IMAGE_VIEW_TYPE_2D,
            subresource_range = IMAGE_SUBRESOURCE_RANGE_SINGLE_COLOR,
            components = COMPONENT_MAPPING_IDENTITY
        ]])}]

    let extent <- phys_dev |> get_swap_extent(surface, window)

    var framebuffers <- [{ for view in views;
        create_single_view_framebuffer([
            device = device,
            render_pass = render_pass,
            view = view,
            width = extent.width,
            height = extent.height
        ])}]

    return <- [[SimpleSwapchain
        swapchain <- swapchain,
        images <- images,
        views <- views,
        framebuffers <- framebuffers
    ]]
