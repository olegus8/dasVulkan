options indenting = 4
options no_aot = true

require daslib/safe_addr
require daslib/defer

require vulkan
require device_ex
require core
require generated

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


def create_shader_module_from_file(
    device : Device;
    file_path : string;
    flags : uint = [[ uint ]]
) : ShaderModule
    var create_info <- [[ShaderModuleCreateInfo
        flags = flags,
        code <- read_file_to_array(file_path)
    ]]
    defer() <| ${ delete create_info; }
    return <- device |> create_shader_module(create_info)
