//options log, log_infer_passes

require daslib/safe_addr
require daslib/vulkan_boost
require fio
require math
require strings
require vulkan


let
    MAX_FRAMES_IN_FLIGHT = 2


struct Vertex
    position : float2
    color : float3


def with_shader_module(device, name; b : block<(m:VkShaderModule)>)
    let code_fpath = "{get_das_root()}/modules/dasVulkan/example/{name}.spv"
    var code : string
    var code_size : uint64
    code_fpath |> fopen("rb") <| $(f)
        code <- f |> fread()
        code_size = (f |> fstat()).size
    var code_ptr : uint?
    unsafe
        code_ptr = reinterpret<uint?>(code)
    let create_info <- [[VkShaderModuleCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        codeSize = code_size,
        pCode = code_ptr
    ]]
    var shmod : VkShaderModule
    verify(VkResult VK_SUCCESS == device |> vkCreateShaderModule(
        create_info |> safe_addr(), null, shmod |> safe_addr()))
    b |> invoke(shmod)
    device |> vkDestroyShaderModule(shmod, null)


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


def make_pipeline_input_assembly()
    return <- [[VkPipelineInputAssemblyStateCreateInfo
        sType = (VkStructureType 
            VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO),
        topology = VkPrimitiveTopology VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
    ]]


def with_pipeline_viewport(phys_dev, surface, window;
    b : block<(i:VkPipelineViewportStateCreateInfo)>
)
    let extent <- phys_dev |> get_swap_extent(surface, window)
    let viewports <- [[auto[] [[VkViewport minDepth = 0.0f, maxDepth = 1.0f,
        width = float(extent.width), height = float(extent.height)
    ]]]]
    let scissors <- [[auto[] [[VkRect2D extent = extent]]]]
    b |> invoke([[VkPipelineViewportStateCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO),
        viewportCount = uint(viewports |> length()),
        pViewports = viewports |> safe_addr(),
        scissorCount = uint(scissors |> length()),
        pScissors = scissors |> safe_addr()
    ]])


def make_pipeline_rasterizer()
    return <- [[VkPipelineRasterizationStateCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO),
        polygonMode = VkPolygonMode VK_POLYGON_MODE_FILL,
        lineWidth = 1.0f,
        cullMode = uint(VkCullModeFlagBits VK_CULL_MODE_BACK_BIT),
        frontFace = VkFrontFace VK_FRONT_FACE_CLOCKWISE
    ]]


def make_pipeline_multisampling()
    return <- [[VkPipelineMultisampleStateCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO),
        rasterizationSamples = VkSampleCountFlagBits VK_SAMPLE_COUNT_1_BIT,
        minSampleShading = 1.0f
    ]]


def with_pipeline_blending(b : block<(b:VkPipelineColorBlendStateCreateInfo)>)
    let blending_atts <- [[auto[] [[VkPipelineColorBlendAttachmentState
        colorWriteMask =
            uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_R_BIT) |
            uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_G_BIT) |
            uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_B_BIT) |
            uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_A_BIT)
    ]]]]
    b |> invoke([[VkPipelineColorBlendStateCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO),
        attachmentCount = uint(blending_atts |> length()),
        pAttachments = blending_atts |> safe_addr()
    ]])


def with_pipeline_creation_subobjects(
    phys_dev, surface, window, vert_shmod, frag_shmod;
    b : block<(
        stages : array<VkPipelineShaderStageCreateInfo>;
        vtx_input : VkPipelineVertexInputStateCreateInfo;
        input_assembly : VkPipelineInputAssemblyStateCreateInfo;
        viewport : VkPipelineViewportStateCreateInfo;
        rasterizer : VkPipelineRasterizationStateCreateInfo;
        multisampling : VkPipelineMultisampleStateCreateInfo;
        blending : VkPipelineColorBlendStateCreateInfo
    )>
)
    with_pipeline_shader_stages(
        vert_shmod, "main", frag_shmod, "main"
    ) <| $(stages) {
    with_pipeline_vertex_input() <| $(vtx_input) {
    with_pipeline_blending() <| $(blending) {
    phys_dev |> with_pipeline_viewport(surface, window) <| $(viewport) {
        b |> invoke(
            stages,
            vtx_input,
            make_pipeline_input_assembly(),
            viewport,
            make_pipeline_rasterizer(),
            make_pipeline_multisampling(),
            blending
        );
    }}}}


def with_graphics_pipeline(device, layout, render_pass,
    phys_dev, surface, window, vert_shmod, frag_shmod;
    b : block<(p:VkPipeline)>
)
    with_pipeline_creation_subobjects(
        phys_dev, surface, window, vert_shmod, frag_shmod
    ) <| $(stages, vtx_input, input_assembly, viewport, rasterizer,
        multisampling, blending
    )
        let pipe_infos <- [[auto[] [[VkGraphicsPipelineCreateInfo
            sType = (VkStructureType
                VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO),
            layout              = layout,
            renderPass          = render_pass,
            stageCount          = uint(stages |> length()),
            pStages             = stages[0] |> safe_addr_plain(),
            pVertexInputState   = vtx_input |> safe_addr(),
            pInputAssemblyState = input_assembly |> safe_addr(),
            pViewportState      = viewport |> safe_addr(),
            pRasterizationState = rasterizer |> safe_addr(),
            pMultisampleState   = multisampling |> safe_addr(),
            pColorBlendState    = blending |> safe_addr(),
            basePipelineIndex   = -1
        ]]]]
        var pipes : array<VkPipeline>
        pipes |> resize(pipe_infos |> length())
        verify(VkResult VK_SUCCESS == device |> vkCreateGraphicsPipelines(
            [[VkPipelineCache]],
            uint(pipe_infos |> length()), pipe_infos[0] |> safe_addr(),
            null, pipes[0] |> safe_addr_val()))
        b |> invoke(pipes[0])
        for pipe in pipes
            device |> vkDestroyPipeline(pipe, null)
        delete pipes


def with_swap_chain_framebuffers(
    device, phys_dev, surface, window, views, render_pass;
    b : block<(fbs:array<VkFramebuffer>)>
)
    let extent <- phys_dev |> get_swap_extent(surface, window)
    var fbufs : array<VkFramebuffer>
    fbufs |> resize(views |> length())
    for fbuf, view in fbufs, views
        var pview : VkImageView const ?
        unsafe
            pview = reinterpret<VkImageView const ?>(addr(view))
        let create_info <- [[VkFramebufferCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            renderPass = render_pass,

            //TODO: make it work. says "can only dereference simple type"
            attachmentCount = 1u, 

            pAttachments = pview,
            width = extent.width,
            height = extent.height,
            layers = 1u
        ]]
        verify(VkResult VK_SUCCESS == device |> vkCreateFramebuffer(
            create_info |> safe_addr(), null, fbuf |> safe_addr()))
    b |> invoke(fbufs)
    for fbuf in fbufs
        device |> vkDestroyFramebuffer(fbuf, null)
    delete fbufs


def with_command_pool(device, phys_dev, surface; b : block<(p:VkCommandPool)>)
    phys_dev |> with_graphics_queue_family(surface) <| $(qfam)
        let create_info <- [[VkCommandPoolCreateInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            queueFamilyIndex = qfam
        ]]
        var pool : VkCommandPool
        verify(VkResult VK_SUCCESS == device |> vkCreateCommandPool(
            create_info |> safe_addr(), null, pool |> safe_addr()))
        b |> invoke(pool)
        device |> vkDestroyCommandPool(pool, null)


def with_buffer(device, buf_size, usage; b : block<(b:VkBuffer)>)
    let create_info <- [[VkBufferCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        size = uint64(buf_size),
        usage = usage,
        sharingMode = VkSharingMode VK_SHARING_MODE_EXCLUSIVE
    ]]
    var buf : VkBuffer
    verify(VkResult VK_SUCCESS == device |> vkCreateBuffer(
        create_info |> safe_addr(), null, buf |> safe_addr()))
    b |> invoke(buf)
    device |> vkDestroyBuffer(buf, null)


def with_memory(device, size, mem_type; b : block<(m:VkDeviceMemory)>)
    let alloc_info <- [[VkMemoryAllocateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        allocationSize = size,
        memoryTypeIndex = mem_type
    ]]
    var mem : VkDeviceMemory
    verify(VkResult VK_SUCCESS == device |> vkAllocateMemory(
        alloc_info |> safe_addr(), null, mem |> safe_addr()))
    b |> invoke(mem)
    device |> vkFreeMemory(mem, null)


def with_memory_type(phys_dev, type_filter, needed_flags; b : block<(t:uint)>)
    var actual_props : VkPhysicalDeviceMemoryProperties
    phys_dev |> vkGetPhysicalDeviceMemoryProperties(
        actual_props |> safe_addr())
    for type_i in range(actual_props.memoryTypeCount)
        if ((1u << uint(type_i)) & type_filter) == 0u
            continue
        let actual_flags = actual_props.memoryTypes[type_i].propertyFlags
        if (actual_flags & needed_flags) == needed_flags
            b |> invoke(uint(type_i))
            return


def with_buf_mem(device, phys_dev, buffer, mem_props;
    b : block<(m:VkDeviceMemory)>
)
    var mem_reqs : VkMemoryRequirements
    device |> vkGetBufferMemoryRequirements(buffer, mem_reqs |> safe_addr())
    phys_dev |> with_memory_type(mem_reqs.memoryTypeBits, mem_props
    ) <| $(mem_type)
        device |> with_memory(mem_reqs.size, mem_type) <| $(mem)
            b |> invoke(mem)


def with_mem_backed_buf(device, phys_dev, buf_size, usage, mem_props;
    b : block<(b:VkBuffer; m:VkDeviceMemory)>
)
    device |> with_buffer(buf_size, usage) <| $(buf)
        device |> with_buf_mem(phys_dev, buf, mem_props) <| $(mem)
            verify(VkResult VK_SUCCESS ==
                device |> vkBindBufferMemory(buf, mem, uint64(0)))
            b |> invoke(buf, mem)


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


def with_cmd_bufs(device, cmd_pool, count;
    b : block<(c:array<VkCommandBuffer>)>
)
    let alloc_info <- [[VkCommandBufferAllocateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        level = VkCommandBufferLevel VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        commandPool = cmd_pool,
        commandBufferCount = uint(count)
    ]]
    var bufs : array<VkCommandBuffer>
    bufs |> resize(count)
    verify(VkResult VK_SUCCESS == device |> vkAllocateCommandBuffers(
        alloc_info |> safe_addr(), bufs[0] |> safe_addr_val()))
    b |> invoke(bufs)
    device |> vkFreeCommandBuffers(
        cmd_pool, uint(count), bufs[0] |> safe_addr_val())
    delete bufs


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
    let extent <- phys_dev |> get_swap_extent(surface, window)
    cmd_buf |> record() <| $()
        let clear_values <- [[auto[] [[VkClearValue]]]]
        let info <- [[VkRenderPassBeginInfo
            sType = VkStructureType VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
            renderPass      = render_pass,
            framebuffer     = fbuf,
            renderArea      = [[VkRect2D extent = extent]],
            clearValueCount = uint(clear_values |> length()),
            pClearValues    = clear_values |> safe_addr()
        ]]
        cmd_buf |> vkCmdBeginRenderPass(
            info |> safe_addr(), VkSubpassContents VK_SUBPASS_CONTENTS_INLINE)
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
    device |> with_cmd_bufs(cmd_pool, 1) <| $(cmd_bufs)
        let cmd_buf = cmd_bufs[0]
        cmd_buf |> record() <| $()
            let params <- [[auto[] [[VkBufferCopy size = uint64(buf_size)]]]]
            cmd_buf |> vkCmdCopyBuffer(src_buf, dst_buf,
                uint(params |> length()), params[0] |> safe_addr())
        queue |> submit(cmd_bufs)
        queue |> vkQueueWaitIdle()


def with_draw_commands(device, phys_dev, window, surface, render_pass,
    fbufs, pipeline, cmd_pool, queue, vbuf, vertices_count;
    b : block<(cmds:array<VkCommandBuffer>)>
)
    let vbufs <- [[auto[] vbuf]]
    let offsets : uint64[1]
    device |> with_cmd_bufs(cmd_pool, fbufs |> length()) <| $(cmd_bufs)
        for cmd_buf, fbuf in cmd_bufs, fbufs
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

        b |> invoke(cmd_bufs)


def with_baked_vertex_buffer(device, phys_dev, cmd_pool, queue;
    vertices:array<auto(VT)>; b : block<(b:VkBuffer)>
)
    let buf_size = typeinfo(sizeof type<VT>) * vertices |> length()

    device |> with_mem_backed_buf(phys_dev, buf_size,
        uint(VkBufferUsageFlagBits VK_BUFFER_USAGE_TRANSFER_DST_BIT) |
        uint(VkBufferUsageFlagBits VK_BUFFER_USAGE_VERTEX_BUFFER_BIT),
        uint(VkMemoryPropertyFlagBits VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
    ) <| $(vbuf, vbuf_mem)

        device |> with_mem_backed_buf(phys_dev, buf_size,
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


def with_semaphores(device, count; b : block<(sems:array<VkSemaphore>)>)
    var sems : array<VkSemaphore>
    sems |> resize(count)
    let info <- [[VkSemaphoreCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO]]
    for sem in sems
        verify(VkResult VK_SUCCESS == device |> vkCreateSemaphore(
            info |> safe_addr(), null, sem |> safe_addr_val()))
    b |> invoke(sems)
    for sem in sems
        device |> vkDestroySemaphore(sem, null)
    delete sems


def with_fences(device, count, flags; b : block<(fences:array<VkFence>)>)
    var fences : array<VkFence>
    fences |> resize(count)
    let info <- [[VkFenceCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
        flags = flags
    ]]
    for fence in fences
        verify(VkResult VK_SUCCESS == device |> vkCreateFence(
            info |> safe_addr(), null, fence |> safe_addr_val()))
    b |> invoke(fences)
    for fence in fences
        device |> vkDestroyFence(fence, null)
    delete fences


def with_swap_chain_independent_state(width, height, title; b : block<(
    instance        : VkInstance#;
    window          : GLFWwindow_DasHandle#;
    surface         : VkSurfaceKHR#;
    phys_dev        : VkPhysicalDevice#;
    device          : VkDevice#;
    queue           : VkQueue;
    surf_fmt        : VkSurfaceFormatKHR#;
    present_mode    : VkPresentModeKHR;
    vert_shmod      : VkShaderModule;
    frag_shmod      : VkShaderModule;
    render_pass     : VkRenderPass;
    pipeline_layout : VkPipelineLayout;
    cmd_pool        : VkCommandPool
)>)
    with_instance()                                 <| $(instance)          {
    with_window(width, height, title)               <| $(window)            {
    window |> with_surface(instance)                <| $(surface)           {
    instance |> with_best_physical_device(surface)  <| $(phys_dev)          {
    instance |> with_device(phys_dev, surface)      <| $(device, queue)     {
    phys_dev |> with_best_format(surface)           <| $(surf_fmt)          {
    phys_dev |> with_best_present_mode(surface)     <| $(present_mode)      {
    device |> with_shader_module("vert")            <| $(vert_shmod)        {
    device |> with_shader_module("frag")            <| $(frag_shmod)        {
    device |> with_basic_render_pass(surf_fmt)      <| $(render_pass)       {
    device |> with_basic_pipeline_layout()          <| $(pipeline_layout)   {
    device |> with_command_pool(phys_dev, surface)  <| $(cmd_pool)
    {
        b |> invoke(
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
        );
    }}}}}}}}}}}}


def with_swap_chain_dependent_state(
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
    cmd_pool;
    b : block<(
        swap_chain          : VkSwapchainKHR;
        sc_imgs             : array<VkImage>#;
        sc_views            : array<VkImageView>#;
        sc_fbufs            : array<VkFramebuffer>;
        pipeline            : VkPipeline;
        img_avail_sems      : array<VkSemaphore>;
        render_done_sems    : array<VkSemaphore>;
        frame_fences        : array<VkFence>
)>)
    device |> with_swap_chain(phys_dev, surface,
        window, surf_fmt, present_mode)             <| $(swap_chain)        {
    device |> with_swap_chain_images(swap_chain)    <| $(sc_imgs)           {
    device |> with_swap_chain_image_views(
        sc_imgs, surf_fmt)                          <| $(sc_views)          {
    device |> with_swap_chain_framebuffers(
        phys_dev, surface, window, sc_views,
        render_pass)                                <| $(sc_fbufs)          {
    device |> with_graphics_pipeline(
        pipeline_layout, render_pass, phys_dev,
        surface, window, vert_shmod, frag_shmod)    <| $(pipeline)          {
    device |> with_semaphores(MAX_FRAMES_IN_FLIGHT) <| $(img_avail_sems)    {
    device |> with_semaphores(MAX_FRAMES_IN_FLIGHT) <| $(render_done_sems)  {
    device |> with_fences(MAX_FRAMES_IN_FLIGHT,
        uint(VkFenceCreateFlagBits
            VK_FENCE_CREATE_SIGNALED_BIT))          <| $(frame_fences)
    {
        b |> invoke(
            swap_chain,
            sc_imgs,
            sc_views,
            sc_fbufs,
            pipeline,
            img_avail_sems,
            render_done_sems,
            frame_fences
        );
    }}}}}}}}


def wait_fence(device; fence : VkFence)
    verify(VkResult VK_SUCCESS == device |> vkWaitForFences(
        1u, fence |> safe_addr(), uint(VK_TRUE), ULONG_MAX))


def reset_fence(device; fence : VkFence)
    verify(VkResult VK_SUCCESS ==
        device |> vkResetFences(1u, fence |> safe_addr()))


def with_next_image(device, swap_chain, sem_to_signal, fence_to_signal;
    b : block<(i:uint)>
)
    var img_index : uint

    //TODO: handle result properly. currently crashes on
    //      "internal integration error"
    verify(VkResult VK_SUCCESS == device |> vkAcquireNextImageKHR(
        swap_chain, ULONG_MAX, sem_to_signal, fence_to_signal,
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


def present(device, queue, swap_chain, img_i, sem_to_wait; b : block<()>)
    let info <- [[VkPresentInfoKHR
        sType = VkStructureType VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        waitSemaphoreCount  = 1u,
        pWaitSemaphores     = sem_to_wait |> safe_addr(),
        swapchainCount      = 1u,
        pSwapchains         = swap_chain |> safe_addr(),
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


def draw_frame(device, queue, cmd_bufs, swap_chain, frame,
    frame_fences, img_avail_sems, render_done_sems;
    var imgs_used_by_frames
)
    device |> wait_fence(frame_fences[frame])
    var img_acquired = false
    var presented = false
    device |> with_next_image(swap_chain, img_avail_sems[frame], [[VkFence]]
    ) <| $(img_i)
        img_acquired = true

        var img_frame = imgs_used_by_frames[img_i]
        if img_frame != -1
            device |> wait_fence(frame_fences[img_frame])
        imgs_used_by_frames[img_i] = frame

        device |> reset_fence(frame_fences[frame])
        device |> submit_draw(queue, cmd_bufs[img_i], img_avail_sems[frame],
            render_done_sems[frame], frame_fences[frame])

        device |> present(queue, swap_chain, img_i, render_done_sems[frame]
        ) <| $()
            presented = true

    return img_acquired && presented


[export]
def main
    print("\nStarted\n")
    glfwInit()
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE)

    let vertices <- [{auto[]
        [[Vertex position=float2( 0.0f, -0.5f), color=float3(1f, 0f, 0f)]];
        [[Vertex position=float2( 0.5f,  0.5f), color=float3(0f, 1f, 0f)]];
        [[Vertex position=float2(-0.5f,  0.5f), color=float3(0f, 0f, 1f)]]
    }]

    with_swap_chain_independent_state(800, 600, "dasVulkanExample") <| $(
        instance        : VkInstance;
        window          : GLFWwindow_DasHandle;
        surface         : VkSurfaceKHR;
        phys_dev        : VkPhysicalDevice;
        device          : VkDevice;
        queue           : VkQueue;
        surf_fmt        : VkSurfaceFormatKHR#;
        present_mode    : VkPresentModeKHR;
        vert_shmod      : VkShaderModule;
        frag_shmod      : VkShaderModule;
        render_pass     : VkRenderPass;
        pipeline_layout : VkPipelineLayout;
        cmd_pool        : VkCommandPool
    )
        let props <- phys_dev |> get_properties()
        print("Using {props.deviceName |> to_string()}\n")
        device |> with_baked_vertex_buffer(
            phys_dev, cmd_pool, queue, vertices
        ) <| $(vbuf)
            var keep_running = true
            while keep_running // swapchain re-creation loop
                // waiting while window is minimized
                while uint2(0,0) == window |> get_framebuffer_size()
                    glfwWaitEvents()
                device |> vkDeviceWaitIdle()

                with_swap_chain_dependent_state(
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
                    swap_chain          : VkSwapchainKHR;
                    sc_imgs             : array<VkImage>#;
                    sc_views            : array<VkImageView>#;
                    sc_fbufs            : array<VkFramebuffer>;
                    pipeline            : VkPipeline;
                    img_avail_sems      : array<VkSemaphore>;
                    render_done_sems    : array<VkSemaphore>;
                    frame_fences        : array<VkFence>
                )
                    print("{sc_fbufs |> length()} images in swap chain\n")
                    device |> with_draw_commands(phys_dev, window, surface,
                        render_pass, sc_fbufs, pipeline, cmd_pool, queue,
                        vbuf, vertices |> length()
                    ) <| $(sc_draw_cmds)
                        var frame = 0
                        var imgs_used_by_frames <- [{for x in sc_fbufs ; -1 }]
                        while keep_running
                            keep_running = (
                                window |> glfwWindowShouldClose() == 0)
                            glfwPollEvents()
                            let is_swap_chain_good = device |> draw_frame(
                                queue, sc_draw_cmds, swap_chain, frame,
                                frame_fences, img_avail_sems, render_done_sems,
                                imgs_used_by_frames
                            )
                            if ! is_swap_chain_good
                                break
                            frame = (frame + 1) % MAX_FRAMES_IN_FLIGHT
                        delete imgs_used_by_frames
                        device |> vkDeviceWaitIdle()

    glfwTerminate()
    print("Finished\n")
    return true
