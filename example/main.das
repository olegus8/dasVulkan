//options log, log_infer_passes

options persistent_heap = true

require daslib/safe_addr
require daslib/vulkan_boost
require daslib/defer
require math
require strings
require vulkan


let
    MAX_FRAMES_IN_FLIGHT = 2


struct Vertex
    position : float2
    color : float3


def with_pipeline_vertex_input(
    b : block<(i:VkPipelineVertexInputStateCreateInfo)>
)
    let vtx_bindings <- [[auto[] [[VkVertexInputBindingDescription
        binding = 0u,
        stride = uint(typeinfo(sizeof type<Vertex>)),
        inputRate = VkVertexInputRate VK_VERTEX_INPUT_RATE_VERTEX
    ]]]]
    let vtx_attrs <- [[auto[]
        [[VkVertexInputAttributeDescription binding = 0u, location = 0u,
            format = VkFormat VK_FORMAT_R32G32_SFLOAT,
            offset = uint(typeinfo(offsetof<position> type<Vertex>))
        ]];
        [[VkVertexInputAttributeDescription binding = 0u, location = 1u,
            format = VkFormat VK_FORMAT_R32G32B32_SFLOAT,
            offset = uint(typeinfo(offsetof<color> type<Vertex>))
        ]]
    ]]
    b |> invoke ([[VkPipelineVertexInputStateCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO),
        vertexBindingDescriptionCount = uint(vtx_bindings |> length()),
        pVertexBindingDescriptions = vtx_bindings[0] |> safe_addr(),
        vertexAttributeDescriptionCount = uint(vtx_attrs |> length()),
        pVertexAttributeDescriptions = vtx_attrs[0] |> safe_addr()
    ]])


def with_graphics_pipeline(device, layout, render_pass,
    phys_dev, surface, window, vert_shmod, frag_shmod;
    b : block<(p:VkPipeline)>
)
    with_pipeline_vertex_input() <| $(vtx_input) {
    phys_dev |> with_pipeline_viewport_full_window(surface, window
    ) <| $(viewport) {
    with_pipeline_shader_stages(
        vert_shmod, "main",
        frag_shmod, "main"
    ) <| $(stages) {
    device |> with_graphics_pipeline_simple(
        layout, render_pass, stages, vtx_input,
        PIPELINE_INPUT_ASSEMBLY_TRI_LIST,
        viewport,
        PIPELINE_RASTERIZER_SIMPLE,
        PIPELINE_MULTISAMPLING_DISABLED,
        PIPELINE_BLENDING_DISABLED
    ) <| $(pipeline)
    {
        b |> invoke(pipeline);
    }}}}


def with_mapped_vk_mem(device, mem, offset, size;
    b : block<(var a:array<auto(T)>#)>
)
    var mem_ptr : void?
    verify(VkResult VK_SUCCESS == device |> vkMapMemory(
        mem, uint64(offset), uint64(size), 0u, mem_ptr |> safe_addr()))
    unsafe
        mem_ptr |> map_to_array(size) <| $(var mapped : array<T>#)
            b |> invoke(mapped)
    device |> vkUnmapMemory(mem)


def record(cmd_buf : VkCommandBuffer; b : block)
    let begin_info <- [[VkCommandBufferBeginInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO]]
    verify(VkResult VK_SUCCESS ==
        cmd_buf |> vkBeginCommandBuffer(begin_info |> safe_addr()))
    b |> invoke()
    cmd_buf |> vkEndCommandBuffer()


def record_render_pass(cmd_buf, phys_dev, window, surface, render_pass, fbuf;
    b : block
)
    let vk_phys_dev = phys_dev.physical_device
    var extent <- phys_dev |> get_swap_extent(surface, window)
    extent |> with_view() <| $(vk_extent : VkExtent2D const)
        cmd_buf |> record() <| $()
            let clear_values <- [[auto[] [[VkClearValue]]]]
            let info <- [[VkRenderPassBeginInfo
                sType = (VkStructureType
                    VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO),
                renderPass      = render_pass,
                framebuffer     = fbuf.framebuffer,
                renderArea      = [[VkRect2D extent = vk_extent]],
                clearValueCount = uint(clear_values |> length()),
                pClearValues    = clear_values |> safe_addr()
            ]]
            cmd_buf |> vkCmdBeginRenderPass(info |> safe_addr(),
                VkSubpassContents VK_SUBPASS_CONTENTS_INLINE)
            b |> invoke()
            cmd_buf |> vkCmdEndRenderPass()


def submit(queue, cmd_bufs)
    let infos <- [[auto[] [[VkSubmitInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_SUBMIT_INFO,
        commandBufferCount = uint(cmd_bufs |> length()),
        pCommandBuffers = cmd_bufs[0] |> safe_addr_plain()
    ]]]]
    verify(VkResult VK_SUCCESS == queue |> vkQueueSubmit(
        uint(infos |> length()), infos[0] |> safe_addr(), [[VkFence]]))


def copy_buf_sync(device, cmd_pool, queue, src_buf, dst_buf, buf_size)
    var cmd_bufs <- device |> create_command_buffers_primary(cmd_pool, 1)
    defer() <|
        delete cmd_bufs;
    let cmd_buf = cmd_bufs.buffers[0]
    cmd_buf |> record() <| $()
        let params <- [[auto[] [[VkBufferCopy size = uint64(buf_size)]]]]
        cmd_buf |> vkCmdCopyBuffer(src_buf, dst_buf,
            uint(params |> length()), params[0] |> safe_addr())
    queue |> submit(cmd_bufs.buffers)
    queue |> vkQueueWaitIdle()


def with_draw_commands(device, phys_dev, window, surface, render_pass,
    fbufs, pipeline, cmd_pool, queue, vbuf, vertices_count;
    b : block<(cmds:array<VkCommandBuffer>)>
)
    let vbufs <- [[auto[] vbuf]]
    let offsets : uint64[1]
    var cmd_bufs <- device |> create_command_buffers_primary(
        cmd_pool, fbufs |> length())
    defer() <|
        delete cmd_bufs;
    for cmd_buf, fbuf in cmd_bufs.buffers, fbufs
        cmd_buf |> record_render_pass(
            phys_dev, window, surface, render_pass, fbuf
        ) <| $()
            cmd_buf |> vkCmdBindPipeline(
                VkPipelineBindPoint VK_PIPELINE_BIND_POINT_GRAPHICS,
                pipeline)
            cmd_buf |> vkCmdBindVertexBuffers(0u, // first binding idx
                //TODO: make it work. says "can only dereference
                //      simple type"
                1u,
                //uint(vbufs |> length()),

                vbufs[0] |> safe_addr(),
                offsets[0] |> safe_addr())
            cmd_buf |> vkCmdDraw(uint(vertices_count),
                1u, // instance count
                0u, // first vertex
                0u  // first instance
            )

    b |> invoke(cmd_bufs.buffers)


def with_mem_backed_buf(
    device : VkDevice#;
    phys_dev : VkPhysicalDevice#;
    buf_size : uint64;
    usage : uint;
    mem_props : uint;
    b : block<(b:VkBuffer#; m:VkDeviceMemory#)>
)
    var buf <- device |> create_buffer_exclusive(buf_size, usage)
    defer() <|
        delete buf
    device |> find_buffer_memory_type(phys_dev, buf, mem_props
    ) <| $(mem_type, mem_size)
        var mem <- allocate_memory([device=device,
            allocation_size=mem_size, mem_type_index=mem_type])
        defer() <|
            delete mem
        verify(VkResult VK_SUCCESS ==
            device |> vkBindBufferMemory(buf.buffer, mem.memory, uint64(0)))
        b |> invoke(buf.buffer, mem.memory)


def with_baked_vertex_buffer(device, phys_dev, cmd_pool, queue;
    vertices:array<auto(VT)>; b : block<(b:VkBuffer)>
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
            device |> with_mapped_vk_mem(staging_mem, 0, buf_size
            ) <| $(var mapped_vertices : array<VT>#)
                for dst, src in mapped_vertices, vertices
                    dst = src
            device |> copy_buf_sync(
                cmd_pool, queue, staging_buf, vbuf, buf_size)

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
    queue           : VkQueue;
    var surf_fmt    : SurfaceFormatKHR;
    present_mode    : VkPresentModeKHR;
    vert_shmod      : VkShaderModule;
    frag_shmod      : VkShaderModule;
    render_pass     : RenderPass;
    pipeline_layout : VkPipelineLayout;
    cmd_pool        : VkCommandPool
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
            queue.queue,
            surf_fmt,
            present_mode,
            shvert.shader_module,
            shfrag.shader_module,
            render_pass,
            pipeline_layout.pipeline_layout,
            cmd_pool.command_pool
        )

        device.device |> vkDeviceWaitIdle()


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
        pipeline            : VkPipeline;
        img_avail_sems      : array<VkSemaphore>;
        render_done_sems    : array<VkSemaphore>;
        frame_fences        : array<VkFence>
)>)
    let vk_device = device.device
    let vk_render_pass = render_pass.render_pass

    var img_avail_sems <- [{for x in range(MAX_FRAMES_IN_FLIGHT);
        device |> create_semaphore() }]
    defer() <| ${ delete img_avail_sems; }

    var vk_img_avail_sems <- [{for sem in img_avail_sems; sem.semaphore}]
    defer() <| ${ delete vk_img_avail_sems; }

    var render_done_sems <- [{for x in range(MAX_FRAMES_IN_FLIGHT);
        device |> create_semaphore() }]
    defer() <| ${ delete render_done_sems; }

    var vk_render_done_sems <- [{for sem in render_done_sems; sem.semaphore}]
    defer() <| ${ delete vk_render_done_sems; }

    var frame_fences <- [{for x in range(MAX_FRAMES_IN_FLIGHT);
        device |> create_fence([[FenceCreateInfo
            flags=uint(VkFenceCreateFlagBits VK_FENCE_CREATE_SIGNALED_BIT)
    ]]) }]
    defer() <| ${ delete frame_fences; }

    var vk_frame_fences <- [{for fence in frame_fences; fence.fence}]
    defer() <| ${ delete vk_frame_fences; }

    var swapchain <- device |> create_swapchain_ex(phys_dev, surface, window,
        surf_fmt, present_mode, render_pass)
    defer() <| ${ delete swapchain; }

    vk_device |> with_graphics_pipeline(
        pipeline_layout, vk_render_pass, phys_dev,
        surface, window, vert_shmod, frag_shmod
    ) <| $(pipeline)
        b |> invoke(
            swapchain,
            pipeline,
            vk_img_avail_sems,
            vk_render_done_sems,
            vk_frame_fences
        )


def wait_fence(device; fence : VkFence)
    verify(VkResult VK_SUCCESS == device |> vkWaitForFences(
        1u, fence |> safe_addr(), uint(VK_TRUE), ULONG_MAX))


def reset_fence(device; fence : VkFence)
    verify(VkResult VK_SUCCESS ==
        device |> vkResetFences(1u, fence |> safe_addr()))


def with_next_image(device, swapchain, sem_to_signal, fence_to_signal;
    b : block<(i:uint)>
)
    var img_index : uint

    //TODO: handle result properly. currently crashes on
    //      "internal integration error"
    verify(VkResult VK_SUCCESS == device |> vkAcquireNextImageKHR(
        swapchain, ULONG_MAX, sem_to_signal, fence_to_signal,
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
        pWaitSemaphores         = sem_to_wait |> safe_addr(),
        pWaitDstStageMask       = stage_to_wait |> safe_addr(),
        signalSemaphoreCount    = 1u,
        pSignalSemaphores       = sem_to_signal |> safe_addr(),
        commandBufferCount      = 1u,
        pCommandBuffers         = cmd_buf |> safe_addr_plain()
    ]]]]
    verify(VkResult VK_SUCCESS == queue |> vkQueueSubmit(
        uint(infos |> length()), infos[0] |> safe_addr(),
        fence_to_signal))


def present(device, queue, swapchain, img_i, sem_to_wait; b : block<()>)
    let info <- [[VkPresentInfoKHR
        sType = VkStructureType VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        waitSemaphoreCount  = 1u,
        pWaitSemaphores     = sem_to_wait |> safe_addr(),
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
    device |> wait_fence(frame_fences[frame])
    var img_acquired = false
    var presented = false
    device |> with_next_image(vk_swapchain, img_avail_sems[frame], [[VkFence]]
    ) <| $(img_i)
        img_acquired = true

        var img_frame = imgs_used_by_frames[img_i]
        if img_frame != -1
            device |> wait_fence(frame_fences[img_frame])
        imgs_used_by_frames[img_i] = frame

        device |> reset_fence(frame_fences[frame])
        device |> submit_draw(queue, cmd_bufs[img_i], img_avail_sems[frame],
            render_done_sems[frame], frame_fences[frame])

        device |> present(queue, vk_swapchain, img_i, render_done_sems[frame]
        ) <| $()
            presented = true

    return img_acquired && presented


[export]
def main
    print("\nStarted\n")
    print("{heap_bytes_allocated()} bytes on heap\n")
    print("{string_heap_bytes_allocated()} bytes on string heap\n")
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
        queue           : VkQueue;
        var surf_fmt    : SurfaceFormatKHR;
        present_mode    : VkPresentModeKHR;
        vert_shmod      : VkShaderModule;
        frag_shmod      : VkShaderModule;
        render_pass     : RenderPass;
        pipeline_layout : VkPipelineLayout;
        cmd_pool        : VkCommandPool
    )
        let vk_device = device.device
        let vk_render_pass = render_pass.render_pass
        var props <- phys_dev |> get_physical_device_properties()
        defer() <| ${ delete props ; }
        print("Using {props.device_name}\n")
        vk_device |> with_baked_vertex_buffer(
            phys_dev.physical_device, cmd_pool, queue, vertices
        ) <| $(vbuf)
            var keep_running = true
            while keep_running // swapchain re-creation loop
                // waiting while window is minimized
                while uint2(0,0) == window |> get_framebuffer_size()
                    glfwWaitEvents()
                vk_device |> vkDeviceWaitIdle()

                with_swapchain_dependent_state(
                    instance,
                    window,
                    surface,
                    phys_dev,
                    device,
                    queue,
                    surf_fmt,
                    present_mode,
                    vert_shmod,
                    frag_shmod,
                    render_pass,
                    pipeline_layout,
                    cmd_pool
                ) <| $(
                    sc                  : SwapchainEx;
                    pipeline            : VkPipeline;
                    img_avail_sems      : array<VkSemaphore>;
                    render_done_sems    : array<VkSemaphore>;
                    frame_fences        : array<VkFence>
                )
                    print("{sc.framebuffers |> length()} " +
                        "images in swap chain\n")
                    vk_device |> with_draw_commands(phys_dev, window, surface,
                        vk_render_pass, sc.framebuffers, pipeline, cmd_pool,
                        queue, vbuf, vertices |> length()
                    ) <| $(sc_draw_cmds)
                        var frame = 0
                        var imgs_used_by_frames <- [{
                            for x in sc.framebuffers ; -1 }]
                        while keep_running
                            keep_running = (
                                window |> glfwWindowShouldClose() == 0)
                            glfwPollEvents()
                            let is_swapchain_good = vk_device |> draw_frame(
                                queue, sc_draw_cmds, sc.swapchain, frame,
                                frame_fences, img_avail_sems, render_done_sems,
                                imgs_used_by_frames
                            )
                            if ! is_swapchain_good
                                break
                            frame = (frame + 1) % MAX_FRAMES_IN_FLIGHT
                        delete imgs_used_by_frames
                        vk_device |> vkDeviceWaitIdle()

    delete vertices
    unsafe
        string_heap_collect()

    glfwTerminate()
    print("Finished\n")
    print("{heap_bytes_allocated()} bytes on heap\n")
    print("{string_heap_bytes_allocated()} bytes on string heap\n")
    return true
