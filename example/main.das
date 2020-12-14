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


def create_example_graphics_pipeline(
    device : Device;
    layout : PipelineLayout;
    render_pass : RenderPass;
    phys_dev : PhysicalDevice;
    surface : SurfaceKHR;
    window : GLFWwindow_DasHandle;
    vert_shmod : ShaderModule;
    frag_shmod : ShaderModule
) : Pipeline
    var extent <- phys_dev |> get_swap_extent(surface, window)
    var create_info <- [[GraphicsPipelineCreateInfo
        layout = weak_copy(layout),
        render_pass = weak_copy(render_pass),
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
                module_ = weak_copy(vert_shmod), name = "main",
                stage = VkShaderStageFlagBits VK_SHADER_STAGE_VERTEX_BIT]];
            [[PipelineShaderStageCreateInfo
                module_ = weak_copy(frag_shmod), name = "main",
                stage = VkShaderStageFlagBits VK_SHADER_STAGE_FRAGMENT_BIT]]
        }]
    ]]
    defer() <| ${ delete create_info; }

    return <- create_graphics_pipeline([
        device=device, create_info=create_info])


def with_example_draw_commands(device, phys_dev, window, surface, render_pass,
    fbufs, pipeline, cmd_pool, queue; vbuf, vertices_count;
    b : block<(cmds:array<VkCommandBuffer>)>
)
    var cmd_bufs <- device |> allocate_command_buffers_primary(
        cmd_pool, fbufs |> length())
    defer() <| ${ delete cmd_bufs; }
    var clear_values <- [{ auto[] [[VkClearValue]] }]
    defer() <| ${ delete clear_values; }
    for cmd_buf, fbuf in cmd_bufs.command_buffers, fbufs
        cmd_buf |> record_command_buffer() <|
            cmd_buf |> record_render_pass(
                phys_dev, window, surface, render_pass, fbuf, clear_values
            ) <|
                cmd_buf |> cmd_bind_pipeline(
                    VkPipelineBindPoint VK_PIPELINE_BIND_POINT_GRAPHICS,
                    pipeline)
                cmd_buf |> cmd_bind_vertex_buffer(vbuf)
                cmd_draw([command_buffer = cmd_buf,
                    vertex_count = uint(vertices_count),
                    instance_count = 1u])

    var vk_cmd_bufs <- [{ for b in cmd_bufs.command_buffers ;
        b.command_buffer }]
    defer() <| ${ delete vk_cmd_bufs; }
    b |> invoke(vk_cmd_bufs)


def with_mem_backed_buf(
    device : Device;
    phys_dev : PhysicalDevice;
    buf_size : uint64;
    usage : uint;
    mem_props : uint;
    b : block<(b:Buffer; m:DeviceMemory)>
)
    var buf <- device |> create_buffer_exclusive(buf_size, usage)
    defer() <| ${ delete buf; }
    device |> find_buffer_memory_type(phys_dev, buf, mem_props
    ) <| $(mem_type, mem_size)
        var mem <- device |> allocate_memory([[MemoryAllocateInfo
            allocation_size=mem_size, memory_type_index=mem_type]])
        defer() <| ${ delete mem; }
        device |> bind_buffer_memory(buf, mem)
        b |> invoke(buf, mem)


def with_baked_vertex_buffer(device, phys_dev, cmd_pool, queue;
    vertices:array<auto(VT)>; b : block<(b:Buffer)>
)
    let buf_size = typeinfo(sizeof type<VT>) * vertices |> length()

    device |> with_mem_backed_buf(phys_dev, uint64(buf_size),
        uint(VkBufferUsageFlagBits VK_BUFFER_USAGE_TRANSFER_DST_BIT) |
        uint(VkBufferUsageFlagBits VK_BUFFER_USAGE_VERTEX_BUFFER_BIT),
        uint(VkMemoryPropertyFlagBits VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
    ) <| $(vbuf, vbuf_mem)

        device |> with_mem_backed_buf(phys_dev, uint64(buf_size),
            uint(VkBufferUsageFlagBits VK_BUFFER_USAGE_TRANSFER_SRC_BIT),
            uint(VkMemoryPropertyFlagBits VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)|
            uint(VkMemoryPropertyFlagBits VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)
        ) <| $(staging_buf, staging_mem)
            device |> map_device_memory_to_array(
                staging_mem, uint64(buf_size), uint64(0), 0u
            ) <| $(var mapped_vertices : array<VT>#)
                for dst, src in mapped_vertices, vertices
                    dst = src
            device |> copy_buffer_sync(
                cmd_pool, queue, staging_buf, vbuf, uint64(buf_size))

        b |> invoke(vbuf)


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
    defer() <| ${ delete create_info; }
    return <- device |> create_render_pass(create_info)


def with_swapchain_independent_state(width, height, title; b : block<(
    instance        : VkInstance#;
    window          : GLFWwindow_DasHandle#;
    surface         : SurfaceKHR;
    phys_dev        : PhysicalDevice;
    device          : Device;
    queue           : Queue;
    var surf_fmt    : SurfaceFormatKHR;
    present_mode    : VkPresentModeKHR;
    vert_shmod      : ShaderModule;
    frag_shmod      : ShaderModule;
    render_pass     : RenderPass;
    pipeline_layout : PipelineLayout;
    cmd_pool        : CommandPool
)>)
    with_window(width, height, title) <| $(window)
        var instance <- create_default_instance()
        defer() <| ${ delete instance; }

        var surface <- instance |> create_window_surface(window)
        defer() <| ${ delete surface; }

        let phys_dev <- instance |> find_physical_device_for_graphics(surface)
        let present_mode <- phys_dev |> find_present_mode_like_mailbox(surface)
        var surf_fmt <- phys_dev |> find_format_like_srgb_bgra8(surface)
        let qfam <- phys_dev |> get_graphics_queue_family(surface)

        var device <- phys_dev |> create_single_queue_device(qfam)
        defer() <| ${ delete device; }

        let queue <- device |> get_device_queue(qfam)

        var cmd_pool <- create_command_pool([device=device, queue_family=qfam])
        defer() <| ${ delete cmd_pool; };

        var shvert <- device |> create_shader_module_from_file(
            "{get_das_root()}/modules/dasVulkan/example/vert.spv")
        defer() <| ${ delete shvert; }

        var shfrag <- device |> create_shader_module_from_file(
            "{get_das_root()}/modules/dasVulkan/example/frag.spv")
        defer() <| ${ delete shfrag; }

        var render_pass <- device |> create_example_render_pass(surf_fmt)
        defer() <| ${ delete render_pass; }

        var pipeline_layout <- device |> create_pipeline_layout()
        defer() <| ${ delete pipeline_layout; }

        b |> invoke(
            instance.instance,
            window,
            surface,
            phys_dev,
            device,
            queue,
            surf_fmt,
            present_mode,
            shvert,
            shfrag,
            render_pass,
            pipeline_layout,
            cmd_pool
        )

        device |> device_wait_idle()


def with_swapchain_dependent_state(
    instance,
    window,
    surface,
    phys_dev,
    device,
    queue;
    var surf_fmt;
    present_mode,
    vert_shmod,
    frag_shmod,
    render_pass,
    pipeline_layout,
    cmd_pool;
    b : block<(
        swapchain           : SwapchainEx;
        pipeline            : Pipeline;
        img_avail_sems      : array<Semaphore>;
        render_done_sems    : array<Semaphore>;
        frame_fences        : array<Fence>
)>)
    var img_avail_sems <- [{for x in range(MAX_FRAMES_IN_FLIGHT);
        device |> create_semaphore() }]
    defer() <| ${ delete img_avail_sems; }

    var render_done_sems <- [{for x in range(MAX_FRAMES_IN_FLIGHT);
        device |> create_semaphore() }]
    defer() <| ${ delete render_done_sems; }

    var frame_fences <- [{for x in range(MAX_FRAMES_IN_FLIGHT);
        device |> create_fence([[FenceCreateInfo
            flags=uint(VkFenceCreateFlagBits VK_FENCE_CREATE_SIGNALED_BIT)
    ]]) }]
    defer() <| ${ delete frame_fences; }

    var swapchain <- device |> create_swapchain_ex(phys_dev, surface, window,
        surf_fmt, present_mode, render_pass)
    defer() <| ${ delete swapchain; }

    var pipeline <- device |> create_example_graphics_pipeline(
        pipeline_layout, render_pass, phys_dev,
        surface, window, vert_shmod, frag_shmod
    )
    defer() <| ${ delete pipeline; }

    b |> invoke(
        swapchain,
        pipeline,
        img_avail_sems,
        render_done_sems,
        frame_fences
    )


def with_next_image(device, swapchain, sem_to_signal, fence_to_signal;
    b : block<(i:uint)>
)
    var img_index : uint

    //TODO: handle result properly. currently crashes on
    //      "internal integration error"
    verify(VkResult VK_SUCCESS == device |> vkAcquireNextImageKHR(
        swapchain, ULONG_MAX, sem_to_signal.semaphore,
        fence_to_signal,
        img_index |> safe_addr()))
    b |> invoke(img_index)
    /*
    if result == VkResult VK_SUCCESS
        b |> invoke(img_index)
    else
        assert(result == VkResult VK_ERROR_OUT_OF_DATE_KHR ||
            result == VkResult VK_SUBOPTIMAL_KHR)
    */


def submit_draw(device, queue; cmd_buf : VkCommandBuffer;
    sem_to_wait, sem_to_signal, fence_to_signal
)
    let stage_to_wait = uint(VkPipelineStageFlagBits
        VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT)
    let infos <- [[auto[] [[VkSubmitInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_SUBMIT_INFO,
        waitSemaphoreCount      = 1u,
        pWaitSemaphores         = sem_to_wait.semaphore |> safe_addr(),
        pWaitDstStageMask       = stage_to_wait |> safe_addr(),
        signalSemaphoreCount    = 1u,
        pSignalSemaphores       = sem_to_signal.semaphore |> safe_addr(),
        commandBufferCount      = 1u,
        pCommandBuffers         = cmd_buf |> safe_addr_plain()
    ]]]]
    verify(VkResult VK_SUCCESS == queue |> vkQueueSubmit(
        uint(infos |> length()), infos[0] |> safe_addr(),
        fence_to_signal.fence))


def present(device, queue, swapchain, img_i, sem_to_wait; b : block<()>)
    let info <- [[VkPresentInfoKHR
        sType = VkStructureType VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        waitSemaphoreCount  = 1u,
        pWaitSemaphores     = sem_to_wait.semaphore |> safe_addr(),
        swapchainCount      = 1u,
        pSwapchains         = swapchain |> safe_addr(),
        pImageIndices       = img_i |> safe_addr()
    ]]
    //TODO: handle result properly. currently crashes on
    //      "internal integration error"
    verify(VkResult VK_SUCCESS ==
        queue |> vkQueuePresentKHR(info |> safe_addr()))
    b |> invoke()
    /*
    if result == VkResult VK_SUCCESS
        b |> invoke()
    else
        assert(result == VkResult VK_ERROR_OUT_OF_DATE_KHR ||
            result == VkResult VK_SUBOPTIMAL_KHR)
    */


def draw_frame(device, queue, cmd_bufs, swapchain, frame,
    frame_fences, img_avail_sems, render_done_sems;
    var imgs_used_by_frames
)
    let vk_swapchain = swapchain.swapchain_khr
    let vk_device = device.device
    device |> wait_for_fence(frame_fences[frame], ULONG_MAX)
    var img_acquired = false
    var presented = false
    vk_device |> with_next_image(
        vk_swapchain, img_avail_sems[frame], [[VkFence]]
    ) <| $(img_i)
        img_acquired = true

        var img_frame = imgs_used_by_frames[img_i]
        if img_frame != -1
            device |> wait_for_fence(frame_fences[img_frame], ULONG_MAX)
        imgs_used_by_frames[img_i] = frame

        device |> reset_fence(frame_fences[frame])
        vk_device |> submit_draw(queue, cmd_bufs[img_i], img_avail_sems[frame],
            render_done_sems[frame], frame_fences[frame])

        vk_device |> present(
            queue, vk_swapchain, img_i, render_done_sems[frame]
        ) <| $()
            presented = true

    return img_acquired && presented


/*
def log_type ( t : auto(TT)? )
    print("
        {typeinfo(typename type<TT>)}:
            isLocal = {typeinfo(is_local type<TT>)}
            canBePlacedInContainer = {typeinfo(can_be_placed_in_container type<TT>)}
            canCopy = {typeinfo(can_copy type<TT>)}
            canMove = {typeinfo(can_move type<TT>)}
            canClone = {typeinfo(can_clone type<TT>)}
            canDelete = {typeinfo(can_delete type<TT>)}
            canNew = {typeinfo(can_new type<TT>)}
            canDeletePtr = {typeinfo(can_delete_ptr type<TT>)}
            hasNonTrivialCtor = {typeinfo(has_nontrivial_ctor type<TT>)}
            hasNonTrivialDtor = {typeinfo(has_nontrivial_dtor type<TT>)}
            hasNonTrivialCopy = {typeinfo(has_nontrivial_copy type<TT>)}
    ")
*/


[export]
def main
/*
    var v : VkCommandBuffer ?
    log_type(v)
    return true
*/
    let heap_on_start = heap_bytes_allocated()
    let string_heap_on_start = string_heap_bytes_allocated()
    print("\nStarted\n")
    glfwInit()
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE)

    var vertices <- [{auto[]
        [[Vertex position=float2( 0.0f, -0.5f), color=float3(1f, 0f, 0f)]];
        [[Vertex position=float2( 0.5f,  0.5f), color=float3(0f, 1f, 0f)]];
        [[Vertex position=float2(-0.5f,  0.5f), color=float3(0f, 0f, 1f)]]
    }]

    with_swapchain_independent_state(800, 600, "dasVulkanExample") <| $(
        instance        : VkInstance;
        window          : GLFWwindow_DasHandle;
        surface         : SurfaceKHR;
        phys_dev        : PhysicalDevice;
        device          : Device;
        queue           : Queue;
        var surf_fmt    : SurfaceFormatKHR;
        present_mode    : VkPresentModeKHR;
        vert_shmod      : ShaderModule;
        frag_shmod      : ShaderModule;
        render_pass     : RenderPass;
        pipeline_layout : PipelineLayout;
        cmd_pool        : CommandPool
    )
        let vk_device = device.device
        let vk_render_pass = render_pass.render_pass
        let vk_queue = queue.queue
        var props <- phys_dev |> get_physical_device_properties()
        defer() <| ${ delete props ; }
        print("Using {props.device_name}\n")
        device |> with_baked_vertex_buffer(phys_dev, cmd_pool, queue, vertices
        ) <| $(vbuf)
            var keep_running = true
            while keep_running // swapchain re-creation loop
                // waiting while window is minimized
                while uint2(0,0) == window |> get_framebuffer_size()
                    glfwWaitEvents()
                device |> device_wait_idle()

                with_swapchain_dependent_state(
                    instance,
                    window,
                    surface,
                    phys_dev,
                    device,
                    vk_queue,
                    surf_fmt,
                    present_mode,
                    vert_shmod,
                    frag_shmod,
                    render_pass,
                    pipeline_layout,
                    cmd_pool
                ) <| $(
                    sc                  : SwapchainEx;
                    pipeline            : Pipeline;
                    img_avail_sems      : array<Semaphore>;
                    render_done_sems    : array<Semaphore>;
                    frame_fences        : array<Fence>
                )
                    print("{sc.framebuffers |> length()} " +
                        "images in swap chain\n")
                    device |> with_example_draw_commands(phys_dev, window,
                        surface, render_pass, sc.framebuffers, pipeline,
                        cmd_pool, vk_queue, vbuf, vertices |> length()
                    ) <| $(sc_draw_cmds)
                        var frame = 0
                        var imgs_used_by_frames <- [{
                            for x in sc.framebuffers ; -1 }]
                        while keep_running
                            keep_running = (
                                window |> glfwWindowShouldClose() == 0)
                            glfwPollEvents()
                            let is_swapchain_good = device |> draw_frame(
                                vk_queue, sc_draw_cmds, sc.swapchain, frame,
                                frame_fences, img_avail_sems, render_done_sems,
                                imgs_used_by_frames
                            )
                            if ! is_swapchain_good
                                break
                            frame = (frame + 1) % MAX_FRAMES_IN_FLIGHT
                        delete imgs_used_by_frames
                        device |> device_wait_idle()

    delete vertices
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
