options indenting = 4
options no_aot = true

require daslib/safe_addr
require fio

require vulkan
require internal/device

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
    //b : block<(i:VkPipelineViewportStateCreateInfo#)>
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
