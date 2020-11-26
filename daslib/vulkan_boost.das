options indenting = 4
options no_aot = true

module vulkan_boost

require daslib/safe_addr
require fio
require math
require vulkan

require internal/buffer      public
require internal/core        public
require internal/device      public
require internal/swap_chain  public


let
    ATT_BLENDING_DISABLED <- [[VkPipelineColorBlendAttachmentState
        colorWriteMask =
            uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_R_BIT) |
            uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_G_BIT) |
            uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_B_BIT) |
            uint(VkColorComponentFlagBits VK_COLOR_COMPONENT_A_BIT)
    ]]

    PIPELINE_BLENDING_DISABLED <- [[VkPipelineColorBlendStateCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO),
        attachmentCount = 1u,
        pAttachments = safe_addr(ATT_BLENDING_DISABLED)
    ]]

    PIPELINE_MULTISAMPLING_DISABLED <- [[VkPipelineMultisampleStateCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO),
        rasterizationSamples = VkSampleCountFlagBits VK_SAMPLE_COUNT_1_BIT,
        minSampleShading = 1.0f
    ]]

    PIPELINE_RASTERIZER_SIMPLE <- [[VkPipelineRasterizationStateCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO),
        polygonMode = VkPolygonMode VK_POLYGON_MODE_FILL,
        lineWidth = 1.0f,
        cullMode = uint(VkCullModeFlagBits VK_CULL_MODE_BACK_BIT),
        frontFace = VkFrontFace VK_FRONT_FACE_CLOCKWISE
    ]]

    PIPELINE_INPUT_ASSEMBLY_TRI_LIST <- [[
        VkPipelineInputAssemblyStateCreateInfo
        sType = (VkStructureType 
            VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO),
        topology = VkPrimitiveTopology VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST
    ]]


def with_render_pass_simple(
    device : VkDevice#;
    surf_fmt : VkSurfaceFormatKHR#;
    b : block<(rp:VkRenderPass#)>
)
    let atts <- [[auto[] [[VkAttachmentDescription
        format = surf_fmt.format,
        samples = VkSampleCountFlagBits VK_SAMPLE_COUNT_1_BIT,
        loadOp = VkAttachmentLoadOp VK_ATTACHMENT_LOAD_OP_CLEAR,
        storeOp = VkAttachmentStoreOp VK_ATTACHMENT_STORE_OP_STORE,
        stencilLoadOp = VkAttachmentLoadOp VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        stencilStoreOp = VkAttachmentStoreOp VK_ATTACHMENT_STORE_OP_DONT_CARE,
        initialLayout = VkImageLayout VK_IMAGE_LAYOUT_UNDEFINED,
        finalLayout = VkImageLayout VK_IMAGE_LAYOUT_PRESENT_SRC_KHR
    ]]]]
    let att_refs <- [[auto[] [[VkAttachmentReference
        attachment = 0u,
        layout = VkImageLayout VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL
    ]]]]
    let subs <- [[auto[] [[VkSubpassDescription
        pipelineBindPoint = (
            VkPipelineBindPoint VK_PIPELINE_BIND_POINT_GRAPHICS),
        colorAttachmentCount = uint(att_refs |> length()),
        pColorAttachments = safe_addr(att_refs[0])
    ]]]]
    let deps <- [[auto[] [[VkSubpassDependency
        srcSubpass = VK_SUBPASS_EXTERNAL,
        dstSubpass = 0u,
        srcStageMask = uint(VkPipelineStageFlagBits
            VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
        srcAccessMask = 0u,
        dstStageMask = uint(VkPipelineStageFlagBits
            VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT),
        dstAccessMask = uint(VkAccessFlagBits
            VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT)
    ]]]]
    let create_info <- [[VkRenderPassCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO),
        attachmentCount = uint(atts |> length()),
        pAttachments = safe_addr(atts[0]),
        subpassCount = uint(subs |> length()),
        pSubpasses = safe_addr(subs[0]),
        dependencyCount = uint(deps |> length()),
        pDependencies = safe_addr(deps[0])
    ]]
    var rpass : VkRenderPass;
    verify(VkResult VK_SUCCESS == device |> vkCreateRenderPass(
        safe_addr(create_info), null, safe_addr(rpass)))
    b |> invoke(rpass)
    device |> vkDestroyRenderPass(rpass, null)


def with_pipeline_layout_simple(device : VkDevice#;
    b : block<(layout:VkPipelineLayout#)>
)
    let create_info <- [[ VkPipelineLayoutCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
    ]]
    var layout : VkPipelineLayout
    verify(VkResult VK_SUCCESS == device |> vkCreatePipelineLayout(
        create_info |> safe_addr(), null, layout |> safe_addr()))
    b |> invoke(layout)
    device |> vkDestroyPipelineLayout(layout, null)


def with_pipeline_shader_stages(
    vert : VkShaderModule#; vert_main : string;
    frag : VkShaderModule#; frag_main : string;
    b : block<(s:array<VkPipelineShaderStageCreateInfo>#)>
)
    var stages <- [{auto[]
        [[VkPipelineShaderStageCreateInfo module_ = vert, pName = vert_main,
            sType = (VkStructureType
                VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO),
            stage = VkShaderStageFlagBits VK_SHADER_STAGE_VERTEX_BIT
        ]];
        [[VkPipelineShaderStageCreateInfo module_ = frag, pName = frag_main,
            sType = (VkStructureType
                VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO),
            stage = VkShaderStageFlagBits VK_SHADER_STAGE_FRAGMENT_BIT
        ]]
    }]
    stages |> lock() <| $(tstages)
        b |> invoke(tstages)
    delete stages


def with_pipeline_viewport_full_window(
    phys_dev : VkPhysicalDevice#;
    surface : VkSurfaceKHR;
    window : GLFWwindow_DasHandle#;
    //TODO: make it pass temporary. compilation fails currently if i do
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


def with_graphics_pipeline_simple(
    device          : VkDevice#;
    layout          : VkPipelineLayout#;
    render_pass     : VkRenderPass#;
    stages          : array<VkPipelineShaderStageCreateInfo>#;
    vtx_input       : VkPipelineVertexInputStateCreateInfo;
    input_assembly  : VkPipelineInputAssemblyStateCreateInfo;
    viewport        : VkPipelineViewportStateCreateInfo;
    rasterizer      : VkPipelineRasterizationStateCreateInfo;
    multisampling   : VkPipelineMultisampleStateCreateInfo;
    blending        : VkPipelineColorBlendStateCreateInfo implicit;
    b : block<(p:VkPipeline#)>
)
    var pstages : VkPipelineShaderStageCreateInfo const ?
    unsafe
        pstages = reinterpret<VkPipelineShaderStageCreateInfo const ?>(
            addr(stages[0]))
    let pipe_info <- [[VkGraphicsPipelineCreateInfo
        sType = (VkStructureType
            VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO),
        layout              = layout,
        renderPass          = render_pass,
        stageCount          = uint(stages |> length()),
        pStages             = pstages,
        pVertexInputState   = vtx_input |> safe_addr(),
        pInputAssemblyState = input_assembly |> safe_addr(),
        pViewportState      = viewport |> safe_addr(),
        pRasterizationState = rasterizer |> safe_addr(),
        pMultisampleState   = multisampling |> safe_addr(),
        pColorBlendState    = blending |> safe_addr(),
        basePipelineIndex   = -1
    ]]
    var pipe : VkPipeline
    verify(VkResult VK_SUCCESS == device |> vkCreateGraphicsPipelines(
        [[VkPipelineCache]], 1u, safe_addr(pipe_info), null, safe_addr(pipe)))
    b |> invoke(pipe)
    device |> vkDestroyPipeline(pipe, null)


def with_shader_modules(device: VkDevice#; code_fpaths : auto;
    b : block<(m:array<VkShaderModule>#)>
)
    var shmods : array<VkShaderModule>
    shmods |> resize(code_fpaths |> length())
    shmods |> lock() <| $(tshmods)
        for code_fpath, tshmod in code_fpaths, tshmods
            var code : string
            var code_size : uint64
            code_fpath |> fopen("rb") <| $(f)
                code <- f |> fread()
                code_size = (f |> fstat()).size
            var code_ptr : uint?
            unsafe
                code_ptr = reinterpret<uint?>(code)
            let create_info <- [[VkShaderModuleCreateInfo
                sType = (VkStructureType
                    VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO),
                codeSize = code_size,
                pCode = code_ptr
            ]]
            verify(VkResult VK_SUCCESS == device |> vkCreateShaderModule(
                create_info |> safe_addr(), null, addr(tshmod)))
        b |> invoke(tshmods)

    for shmod in shmods
        device |> vkDestroyShaderModule(shmod, null)
    delete shmods


def with_swap_chain_framebuffers(
    device : VkDevice#;
    phys_dev : VkPhysicalDevice#;
    surface : VkSurfaceKHR#;
    window : GLFWwindow_DasHandle#;
    views : array<VkImageView>#;
    render_pass : VkRenderPass#;
    b : block<(fbs:array<VkFramebuffer>#)>
)
    let extent <- phys_dev |> get_swap_extent(surface, window)
    var fbufs : array<VkFramebuffer>
    fbufs |> resize(views |> length())
    fbufs |> lock() <| $(tfbufs)
        for tfbuf, view in tfbufs, views
            var pview : VkImageView const ?
            unsafe
                pview = reinterpret<VkImageView const ?>(addr(view))
            let create_info <- [[VkFramebufferCreateInfo
                sType = (VkStructureType
                    VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO),
                renderPass = render_pass,

                //TODO: make it work. says "can only dereference simple type"
                attachmentCount = 1u, 

                pAttachments = pview,
                width = extent.width,
                height = extent.height,
                layers = 1u
            ]]
            verify(VkResult VK_SUCCESS == device |> vkCreateFramebuffer(
                safe_addr(create_info), null, addr(tfbuf)))
        b |> invoke(tfbufs)
    for fbuf in fbufs
        device |> vkDestroyFramebuffer(fbuf, null)
    delete fbufs


def with_command_pool(
    device : VkDevice#;
    phys_dev : VkPhysicalDevice#;
    surface : VkSurfaceKHR#;
    b : block<(p:VkCommandPool#)>
)
    let qfam = phys_dev |> get_graphics_queue_family(surface)
    let create_info <- [[VkCommandPoolCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        queueFamilyIndex = qfam
    ]]
    var pool : VkCommandPool
    verify(VkResult VK_SUCCESS == device |> vkCreateCommandPool(
        safe_addr(create_info), null, safe_addr(pool)))
    b |> invoke(pool)
    device |> vkDestroyCommandPool(pool, null)


def with_memory(
    device : VkDevice#;
    size : uint64;
    mem_type_index : uint;
    b : block<(m:VkDeviceMemory#)>
)
    let alloc_info <- [[VkMemoryAllocateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        allocationSize = size,
        memoryTypeIndex = mem_type_index
    ]]
    var mem : VkDeviceMemory
    verify(VkResult VK_SUCCESS == device |> vkAllocateMemory(
        alloc_info |> safe_addr(), null, mem |> safe_addr()))
    b |> invoke(mem)
    device |> vkFreeMemory(mem, null)


def with_memory_type(
    phys_dev : VkPhysicalDevice#;
    type_filter : uint;
    needed_flags : uint;
    b : block<(t:uint)>
)
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


def with_buf_mem(
    device : VkDevice#;
    phys_dev : VkPhysicalDevice#;
    buffer : VkBuffer#;
    mem_props : uint;
    b : block<(m:VkDeviceMemory#)>
)
    var mem_reqs : VkMemoryRequirements
    device |> vkGetBufferMemoryRequirements(buffer, mem_reqs |> safe_addr())
    phys_dev |> with_memory_type(mem_reqs.memoryTypeBits, mem_props
    ) <| $(mem_type)
        device |> with_memory(mem_reqs.size, mem_type) <| $(mem)
            b |> invoke(mem)


def with_mem_backed_buf(
    device : VkDevice#;
    phys_dev : VkPhysicalDevice#;
    buf_size : uint64;
    offset : uint64;
    usage : uint;
    mem_props : uint;
    b : block<(b:VkBuffer#; m:VkDeviceMemory#)>
)
    device |> with_buffer(buf_size, usage) <| $(buf)
        device |> with_buf_mem(phys_dev, buf, mem_props) <| $(mem)
            verify(VkResult VK_SUCCESS ==
                device |> vkBindBufferMemory(buf, mem, offset))
            b |> invoke(buf, mem)
