//options log, log_infer_passes

options persistent_heap = true

require daslib/safe_addr
require daslib/vulkan_boost
require daslib/defer
require math
require strings


let
    MAX_FRAMES_IN_FLIGHT = 2


struct Vertex
    position : float2
    color : float3


struct UniformBufferObject
    offset : float2


def create_example_descriptor_set_layout(
    device : Device
) : DescriptorSetLayout
    var info <- [[ DescriptorSetLayoutCreateInfo
        bindings <- [{ auto[] [[ DescriptorSetLayoutBinding
            binding = 0u,
            descriptor_type = (VkDescriptorType
                VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER),
            descriptor_count = 1u,
            stage_flags = VkShaderStageFlagBits VK_SHADER_STAGE_VERTEX_BIT
    ]] }] ]]
    defer() <| { delete info; }
    return <- device |> create_descriptor_set_layout(info)


def create_example_pipeline_layout(
    device : Device;
    desc_set_layout : DescriptorSetLayout
) : PipelineLayout
    var info <- [[ PipelineLayoutCreateInfo
        set_layouts <- [{ auto[] weak_copy(desc_set_layout) }]
    ]]
    defer() <| { delete info; }
    return <- device |> create_pipeline_layout(info)


def create_example_graphics_pipeline(
    sis : SwapchainIndependentState
) : Pipeline
    var extent <- sis.phys_dev |> get_swap_extent(sis.surface, sis.window)
    var create_info <- [[GraphicsPipelineCreateInfo
        layout = weak_copy(sis.pipeline_layout),
        render_pass = weak_copy(sis.render_pass),
        base_pipeline_index = -1,
        input_assembly_state <- [[ PipelineInputAssemblyStateCreateInfo
            topology=VkPrimitiveTopology VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST]],
        rasterization_state <- [[ PipelineRasterizationStateCreateInfo
            polygon_mode = VkPolygonMode VK_POLYGON_MODE_FILL,
            line_width = 1.0f,
            cull_mode = uint(VkCullModeFlagBits VK_CULL_MODE_BACK_BIT),
            front_face = VkFrontFace VK_FRONT_FACE_CLOCKWISE]],
        multisample_state <- [[ PipelineMultisampleStateCreateInfo
            rasterization_samples=VkSampleCountFlagBits VK_SAMPLE_COUNT_1_BIT,
            min_sample_shading = 1.0f ]],
        color_blend_state <- [[ PipelineColorBlendStateCreateInfo
            attachments <- [{ auto[] [[PipelineColorBlendAttachmentState
                color_write_mask =
                    uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_R_BIT) |
                    uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_G_BIT) |
                    uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_B_BIT) |
                    uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_A_BIT)
        ]]}]]],
        vertex_input_state <- [[PipelineVertexInputStateCreateInfo
            vertex_binding_descriptions <- [{ auto[]
                [[VertexInputBindingDescription binding = 0u,
                    stride = uint(typeinfo(sizeof type<Vertex>)),
                    input_rate=VkVertexInputRate VK_VERTEX_INPUT_RATE_VERTEX]]
            }],
            vertex_attribute_descriptions <- [{ auto[]
                [[VertexInputAttributeDescription binding=0u, location=0u,
                    format = VkFormat VK_FORMAT_R32G32_SFLOAT,
                    offset = uint(typeinfo(offsetof<position> type<Vertex>))]];
                [[VertexInputAttributeDescription binding=0u, location=1u,
                    format = VkFormat VK_FORMAT_R32G32B32_SFLOAT,
                    offset = uint(typeinfo(offsetof<color> type<Vertex>))]]
            }]
        ]],
        viewport_state <- [[PipelineViewportStateCreateInfo
            viewports <- [{ auto[] [[Viewport min_depth=0.f, max_depth=1.f,
                width=float(extent.width), height=float(extent.height) ]]}],
            scissors <- [{ auto[] [[Rect2D extent = extent]] }]
        ]],
        stages <- [{ auto[]
            [[PipelineShaderStageCreateInfo
                module_ = weak_copy(sis.vert_shmod), name = "main",
                stage = VkShaderStageFlagBits VK_SHADER_STAGE_VERTEX_BIT]];
            [[PipelineShaderStageCreateInfo
                module_ = weak_copy(sis.frag_shmod), name = "main",
                stage = VkShaderStageFlagBits VK_SHADER_STAGE_FRAGMENT_BIT]]
        }]
    ]]
    defer() <| { delete create_info; }

    return <- create_graphics_pipeline([
        device=sis.device, create_info=create_info])


def create_example_draw_commands(
    sis             : SwapchainIndependentState;
    sds             : SwapchainDependentState;
    vbuf            : Buffer;
    vertices_count  : int
) : CommandBuffers
    var cmd_bufs <- sis.device |> allocate_command_buffers_primary(
        sis.cmd_pool, sds.swapchain.framebuffers |> length())
    var clear_values <- [{ auto[] [[VkClearValue]] }]
    defer() <| { delete clear_values; }
    for cmd_buf, fbuf in cmd_bufs.command_buffers, sds.swapchain.framebuffers
        cmd_buf |> record_command_buffer() <|
            cmd_buf |> record_render_pass(
                sis.phys_dev, sis.window, sis.surface, sis.render_pass,
                fbuf, clear_values
            ) <|
                cmd_buf |> cmd_bind_pipeline(
                    VkPipelineBindPoint VK_PIPELINE_BIND_POINT_GRAPHICS,
                    sds.pipeline)
                cmd_buf |> cmd_bind_vertex_buffer(vbuf)
                cmd_draw([command_buffer = cmd_buf,
                    vertex_count = uint(vertices_count),
                    instance_count = 1u])
    return <- cmd_bufs


struct MemoryBackedBuffer
    buffer : Buffer
    memory : DeviceMemory


def finalize(var b: MemoryBackedBuffer explicit)
    delete b.memory
    delete b.buffer
    memzero(b)


def create_memory_backed_buffer(
    device      : Device;
    phys_dev    : PhysicalDevice;
    buf_size    : uint64;
    usage       : uint;
    mem_props   : uint
) : MemoryBackedBuffer
    var created = false
    var mbb : MemoryBackedBuffer
    mbb.buffer <- device |> create_buffer_exclusive(buf_size, usage)
    device |> find_buffer_memory_type(phys_dev, mbb.buffer, mem_props
    ) <| $(mem_type, mem_size)
        mbb.memory <- device |> allocate_memory([[MemoryAllocateInfo
            allocation_size=mem_size, memory_type_index=mem_type]])
        device |> bind_buffer_memory(mbb.buffer, mbb.memory)
        created = true
    assert(created)
    return <- mbb


def create_example_vertex_buffer(
    sis : SwapchainIndependentState;
    vertices : array<auto(VT)>
) : MemoryBackedBuffer
    let buf_size = typeinfo(sizeof type<VT>) * vertices |> length()

    var vbuf <- sis.device |> create_memory_backed_buffer(
        sis.phys_dev, uint64(buf_size),
        uint(VkBufferUsageFlagBits VK_BUFFER_USAGE_TRANSFER_DST_BIT) |
        uint(VkBufferUsageFlagBits VK_BUFFER_USAGE_VERTEX_BUFFER_BIT),
        uint(VkMemoryPropertyFlagBits VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT))

    var staging <- sis.device |> create_memory_backed_buffer(
        sis.phys_dev, uint64(buf_size),
        uint(VkBufferUsageFlagBits VK_BUFFER_USAGE_TRANSFER_SRC_BIT),
        uint(VkMemoryPropertyFlagBits VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)|
        uint(VkMemoryPropertyFlagBits VK_MEMORY_PROPERTY_HOST_COHERENT_BIT))
    defer() <| { delete staging; }

    sis.device |> map_device_memory_to_array(
        staging.memory, uint64(buf_size), uint64(0), 0u
    ) <| $(var mapped_vertices : array<VT>#)
        for dst, src in mapped_vertices, vertices
            dst = src
    sis.device |> copy_buffer_sync(
        sis.cmd_pool, sis.queue, staging.buffer, vbuf.buffer, uint64(buf_size))

    return <- vbuf


def create_example_render_pass(
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


struct SwapchainIndependentState
    window          : Window
    instance        : Instance
    surface         : SurfaceKHR
    phys_dev        : PhysicalDevice
    device          : Device
    queue           : Queue
    surf_fmt        : SurfaceFormatKHR
    present_mode    : VkPresentModeKHR
    vert_shmod      : ShaderModule
    frag_shmod      : ShaderModule
    render_pass     : RenderPass
    desc_set_layout : DescriptorSetLayout
    pipeline_layout : PipelineLayout
    cmd_pool        : CommandPool


def finalize(var s : SwapchainIndependentState explicit)
    s.device |> device_wait_idle()
    delete s.pipeline_layout
    delete s.desc_set_layout
    delete s.render_pass
    delete s.frag_shmod
    delete s.vert_shmod
    delete s.cmd_pool
    delete s.device
    delete s.surface
    delete s.instance
    delete s.window
    memzero(s)


def create_swapchain_independent_state(
    width, height : int;
    title : string
) : SwapchainIndependentState
    var s : SwapchainIndependentState
    s.window <- create_window(width, height, title)
    s.instance <- create_default_instance()
    s.surface <- s.instance |> create_window_surface(s.window)
    s.phys_dev <- s.instance |> find_physical_device_for_graphics(s.surface)
    s.present_mode <- s.phys_dev |> find_present_mode_like_mailbox(s.surface)
    s.surf_fmt <- s.phys_dev |> find_format_like_srgb_bgra8(s.surface)
    let qfam <- s.phys_dev |> get_graphics_queue_family(s.surface)
    s.device <- s.phys_dev |> create_single_queue_device(qfam)
    s.queue <- s.device |> get_device_queue(qfam)
    s.cmd_pool <- create_command_pool([device=s.device, queue_family=qfam])
    s.vert_shmod <- s.device |> create_shader_module_from_file(
        "{get_das_root()}/modules/dasVulkan/example/vert.spv")
    s.frag_shmod <- s.device |> create_shader_module_from_file(
        "{get_das_root()}/modules/dasVulkan/example/frag.spv")
    s.render_pass <- s.device |> create_example_render_pass(s.surf_fmt)
    s.desc_set_layout <- s.device |> create_example_descriptor_set_layout()
    s.pipeline_layout <- s.device |> create_example_pipeline_layout(
        s.desc_set_layout)
    return <- s


struct SwapchainDependentState
    swapchain        : SwapchainEx
    pipeline         : Pipeline
    img_avail_sems   : array<Semaphore>
    render_done_sems : array<Semaphore>
    frame_fences     : array<Fence>
    uniform_bufs     : array<MemoryBackedBuffer>
    _device          : Device


def finalize(var s : SwapchainDependentState explicit)
    s._device |> device_wait_idle()
    delete s.pipeline
    delete s.uniform_bufs
    delete s.swapchain
    delete s.frame_fences
    delete s.render_done_sems
    delete s.img_avail_sems
    memzero(s)


def create_swapchain_dependent_state(
    var sis : SwapchainIndependentState
) : SwapchainDependentState
    var sds <- [[ SwapchainDependentState _device <- weak_copy(sis.device) ]]
    sds.img_avail_sems <- [{for x in range(MAX_FRAMES_IN_FLIGHT);
        sis.device |> create_semaphore() }]
    sds.render_done_sems <- [{for x in range(MAX_FRAMES_IN_FLIGHT);
        sis.device |> create_semaphore() }]
    sds.frame_fences <- [{for x in range(MAX_FRAMES_IN_FLIGHT);
        sis.device |> create_fence([[FenceCreateInfo
            flags=uint(VkFenceCreateFlagBits VK_FENCE_CREATE_SIGNALED_BIT)
    ]]) }]
    sds.swapchain <- sis.device |> create_swapchain_ex(sis.phys_dev,
        sis.surface, sis.window, sis.surf_fmt, sis.present_mode,
        sis.render_pass)
    sds.pipeline <- sis |> create_example_graphics_pipeline()
    return <- sds


def with_next_image(device, swapchain, sem_to_signal; b : block<(i:uint)>)
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


def submit_draw(
    device          : Device;
    queue           : Queue;
    cmd_buf         : CommandBuffer;
    sem_to_wait     : Semaphore;
    sem_to_signal   : Semaphore;
    fence_to_signal : Fence
)
    queue_submit([queue = queue, command_buffer = cmd_buf,
        wait_semaphore = safe_addr(sem_to_wait),
        wait_dst_stage_mask = uint(VkPipelineStageFlagBits
            VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
        signal_semaphore = safe_addr(sem_to_signal),
        fence = fence_to_signal])


def present(device, queue, swapchain, img_i, sem_to_wait) : bool
    var result : VkResult
    var p_result : VkResult ?
    unsafe
        p_result = addr(result)
    queue |> queue_present_khr(
        swapchain, img_i, safe_addr(sem_to_wait), p_result)
    if result == VkResult VK_SUCCESS
        return true
    assert(result == VkResult VK_ERROR_OUT_OF_DATE_KHR ||
        result == VkResult VK_SUBOPTIMAL_KHR)
    return false


def draw_frame(
    sis                     : SwapchainIndependentState;
    sds                     : SwapchainDependentState;
    cmd_bufs                : array<CommandBuffer>;
    frame                   : int;
    var imgs_used_by_frames : array<int>
)
    sis.device |> wait_for_fence(sds.frame_fences[frame], ULONG_MAX)
    var img_acquired = false
    var presented = false
    sis.device |> with_next_image(sds.swapchain.swapchain,
        sds.img_avail_sems[frame]
    ) <| $(img_i)
        img_acquired = true

        var img_frame = imgs_used_by_frames[img_i]
        if img_frame != -1
            sis.device |> wait_for_fence(
                sds.frame_fences[img_frame], ULONG_MAX)
        imgs_used_by_frames[img_i] = frame

        sis.device |> reset_fence(sds.frame_fences[frame])
        sis.device |> submit_draw(sis.queue, cmd_bufs[img_i],
            sds.img_avail_sems[frame], sds.render_done_sems[frame],
            sds.frame_fences[frame])

        presented = sis.device |> present(sis.queue, sds.swapchain.swapchain,
            img_i, sds.render_done_sems[frame])

    return img_acquired && presented


[export]
def key_callback(
    window : GLFWwindow_DasHandle;
    key, scancode, action, mods : int
)
    print("key={key} scancode={scancode} action={action} mods={mods}\n")


def run_example
    var vertices <- [{auto[]
        [[Vertex position=float2( 0.0f, -0.5f), color=float3(1f, 0f, 0f)]];
        [[Vertex position=float2( 0.5f,  0.5f), color=float3(0f, 1f, 0f)]];
        [[Vertex position=float2(-0.5f,  0.5f), color=float3(0f, 0f, 1f)]]
    }]
    defer() <| { delete vertices; }

    var sis <- create_swapchain_independent_state(800, 600, "dasVulkanExample")
    defer() <| { delete sis; }

    sis.window.window |> glfwSetKeyCallback(@@key_callback)
    var props <- sis.phys_dev |> get_physical_device_properties()
    defer() <| { delete props ; }
    print("Using {props.device_name}\n")

    var vbuf <- sis |> create_example_vertex_buffer(vertices)
    defer() <| { delete vbuf; }

    var keep_running = true
    while keep_running // swapchain re-creation loop
        // waiting while window is minimized
        while uint2(0,0) == sis.window |> get_framebuffer_size()
            glfwWaitEvents()
        sis.device |> device_wait_idle()

        var sds <- create_swapchain_dependent_state(sis)

        print("{sds.swapchain.framebuffers |> length()} " +
            "images in swap chain\n")

        var draw_cmds <- create_example_draw_commands(
            sis, sds, vbuf.buffer, vertices |> length())

        var frame = 0
        var imgs_used_by_frames <- [{for x in sds.swapchain.framebuffers; -1}]

        while keep_running
            keep_running = sis.window.window |> glfwWindowShouldClose() == 0
            glfwPollEvents()
            let is_swapchain_good = draw_frame(sis, sds,
                draw_cmds.command_buffers, frame, imgs_used_by_frames)
            if ! is_swapchain_good
                break
            frame = (frame + 1) % MAX_FRAMES_IN_FLIGHT

        sis.device |> device_wait_idle()
        delete imgs_used_by_frames
        delete draw_cmds
        delete sds


[export]
def main
    let heap_on_start = heap_bytes_allocated()
    let string_heap_on_start = string_heap_bytes_allocated()
    print("\nStarted\n")
    glfwInit()
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
    glfwWindowHint(GLFW_RESIZABLE, GLFW_TRUE)
    run_example()
    glfwTerminate()

    unsafe
        string_heap_collect()

    let heap_leaks = int(heap_bytes_allocated() - heap_on_start)
    let string_heap_leaks = int(string_heap_bytes_allocated()
        - string_heap_on_start)

    print("{heap_leaks} heap bytes have leaked\n")
    print("{string_heap_leaks} string heap bytes have leaked\n")
    assert(heap_leaks == 0)
    assert(string_heap_leaks == 0)

    print("Finished\n")
    return true
