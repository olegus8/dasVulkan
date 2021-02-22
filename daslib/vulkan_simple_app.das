options indenting = 4
options no_aot = true

module vulkan_simple_app

require daslib/defer
require vulkan_boost


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
    render_pass  : RenderPass
    cmd_pool     : CommandPool


def finalize(var s : SimpleSwapchainIndependentState explicit)
    s.device |> device_wait_idle
    delete s.cmd_pool
    delete s.render_pass
    delete s.desc_pool
    delete s.device
    delete s.surface
    delete s.instance
    delete s.window


struct SimpleSwapchainDependentState
    swapchain           : SimpleSwapchain
    img_avail_sems      : array<Semaphore>
    render_done_sems    : array<Semaphore>
    frame_fences        : array<Fence>
    draw_cmds           : CommandBuffers
    frames_since_start  : int
    imgs_used_by_frames : array<int>
    _device             : Device


def finalize(var s : SimpleSwapchainDependentState explicit)
    s._device |> device_wait_idle()
    delete s.imgs_used_by_frames
    delete s.draw_cmds
    delete s.swapchain
    delete s.frame_fences
    delete s.render_done_sems
    delete s.img_avail_sems
    memzero(s)


struct SimpleVulkanApp
    sis : SimpleSwapchainIndependentState
    sds : SimpleSwapchainDependentState

def finalize(var a : SimpleVulkanApp explicit)
    delete a.sds
    delete a.sis
    memzero(a)
    glfwTerminate()


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


def vk_instance(a : SimpleVulkanApp) : VkInstance
    return a.sis.instance.instance.instance

def vk_phys_dev(a : SimpleVulkanApp) : VkPhysicalDevice
    return a.sis.phys_dev.physical_device

def vk_device(a : SimpleVulkanApp) : VkDevice
    return a.sis.device.device

def vk_queue(a : SimpleVulkanApp) : VkQueue
    return a.sis.queue.queue

def vk_desc_pool(a : SimpleVulkanApp) : VkDescriptorPool
    return a.sis.desc_pool.descriptor_pool

def vk_render_pass(a : SimpleVulkanApp) : VkRenderPass
    return a.sis.render_pass.render_pass

def vk_gfx_qfam(a : SimpleVulkanApp) : uint
    return a.sis.gfx_qfam

def glfw_window(a : SimpleVulkanApp) : GLFWwindow ?
    return a.sis.window.window

def images_in_swapchain(a : SimpleVulkanApp) : int
    return a.sds.swapchain.images |> length


def SimpleVulkanApp(title : string; width,height : int) : SimpleVulkanApp
    if glfwInit()==0
		panic("can't init glfw")
    var app : SimpleVulkanApp
    app.sis <- create_simple_sis(title, width, height)
    app.sds <- create_simple_sds(app.sis)
    return <- app


def frame_loop(
    var app : SimpleVulkanApp;
    draw_fn : block<(c:CommandBuffer; f:Framebuffer)>
)
    var keep_running = true
    while keep_running // swapchain re-creation loop
        // waiting while window is minimized
        while uint2(0,0) == app.sis.window |> get_framebuffer_size
            glfwWaitEvents()
        device_wait_idle(app |> vk_device)

        delete app.sds
        app.sds <- create_simple_sds(app.sis)

        while keep_running
            keep_running = glfwWindowShouldClose(app |> glfw_window) == 0
            glfwPollEvents()
            if ! draw_simple_frame(app.sis, app.sds, draw_fn)
                break

        device_wait_idle(app |> vk_device)


[private]
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
    sis.render_pass <- sis.device |> create_simple_render_pass(sis.surf_fmt)
    sis.cmd_pool <- create_command_pool([
        device=sis.device,
        queue_family=sis.gfx_qfam,
        flags=uint(VkCommandPoolCreateFlagBits
            VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT)
    ])
    return <- sis


[private]
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
    sds.draw_cmds <- sis.device |> allocate_command_buffers_primary(
        sis.cmd_pool, sds.swapchain.framebuffers |> length)

    return <- sds


[private]
def draw_simple_frame(
    sis : SimpleSwapchainIndependentState;
    var sds : SimpleSwapchainDependentState;
    draw_fn : block<(c:CommandBuffer; f:Framebuffer)>
)
    let frame = sds.frames_since_start % MAX_FRAMES_IN_FLIGHT
    sis.device |> wait_for_fence(sds.frame_fences[frame], ULONG_MAX)
    var img_acquired = false
    var presented = false
    sis.device |> with_next_image(
        sds.swapchain.swapchain, sds.img_avail_sems[frame]
    ) <| $(img_i)
        img_acquired = true

        var img_frame = sds.imgs_used_by_frames[img_i]
        if img_frame != -1
            sis.device |> wait_for_fence(
                sds.frame_fences[img_frame], ULONG_MAX)
        sds.imgs_used_by_frames[img_i] = frame

        var cmd_buf <- weak_copy(sds.draw_cmds.command_buffers[img_i])
        cmd_buf |> reset_command_buffer
        cmd_buf |> record_command_buffer_ex([[ CommandBufferBeginInfo
            flags = uint(VkCommandBufferUsageFlagBits
                VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT)
        ]] ) <|
            draw_fn |> invoke(cmd_buf, sds.swapchain.framebuffers[img_i])

        sis.device |> reset_fence <| sds.frame_fences[frame]
        queue_submit([queue = sis.queue, command_buffer = cmd_buf,
            wait_semaphore = safe_addr(sds.img_avail_sems[frame]),
            wait_dst_stage_mask = uint(VkPipelineStageFlagBits
                VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
            signal_semaphore = safe_addr(sds.render_done_sems[frame]),
            fence = sds.frame_fences[frame]
        ])

        presented = sis.device |> present(sis.queue, sds.swapchain.swapchain,
            img_i, sds.render_done_sems[frame])

    sds.frames_since_start += 1
    return img_acquired && presented


[private]
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


[private]
def create_simple_render_pass(
    device : Device;
    surf_fmt : SurfaceFormatKHR
) : RenderPass
    
    var create_info <- [[RenderPassCreateInfo
        attachments <- [{auto[] [[AttachmentDescription
            format = surf_fmt.format,
            samples = VkSampleCountFlagBits VK_SAMPLE_COUNT_1_BIT,
            load_op = VkAttachmentLoadOp VK_ATTACHMENT_LOAD_OP_CLEAR,
            store_op = VkAttachmentStoreOp VK_ATTACHMENT_STORE_OP_STORE,
            stencil_load_op = (VkAttachmentLoadOp
                VK_ATTACHMENT_LOAD_OP_DONT_CARE),
            stencil_store_op = (VkAttachmentStoreOp
                VK_ATTACHMENT_STORE_OP_DONT_CARE),
            initial_layout = VkImageLayout VK_IMAGE_LAYOUT_UNDEFINED,
            final_layout = VkImageLayout VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
        ]]}],
        subpasses <- [{auto[] [[SubpassDescription
            pipeline_bind_point = (VkPipelineBindPoint
                VK_PIPELINE_BIND_POINT_GRAPHICS),
            color_attachments <- [{auto[] [[AttachmentReference
                attachment = 0u,
                layout = VkImageLayout VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
            ]]}]
        ]]}],
        dependencies <- [{auto[] [[SubpassDependency
            src_subpass = VK_SUBPASS_EXTERNAL,
            dst_subpass = 0u,
            src_stage_mask = uint(VkPipelineStageFlagBits
                VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
            src_access_mask = 0u,
            dst_stage_mask = uint(VkPipelineStageFlagBits
                VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
            dst_access_mask = uint(VkAccessFlagBits
                VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT)
        ]]}]
    ]]
    defer() <| { delete create_info; }
    return <- device |> create_render_pass(create_info)
