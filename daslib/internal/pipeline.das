options indenting = 4
options no_aot = true

require daslib/safe_addr
require daslib/defer

require vulkan
require device
require core
require generated


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


def create_graphics_pipeline(
    device : Device = [[ Device ]];
    pipeline_cache : PipelineCache = [[ PipelineCache ]];
    var create_info : GraphicsPipelineCreateInfo = [[
        GraphicsPipelineCreateInfo ]];
    var result : VkResult? = [[VkResult?]]
) : Pipeline

    var create_infos <- [{ auto[] clone_to_move(create_info) }]
    defer() <| ${ delete create_infos; }
    var pipelines <- create_graphics_pipelines([
        device = device,
        pipeline_cache = pipeline_cache,
        create_infos = create_infos,
        result = result
    ])
    defer() <| ${ delete pipelines; }
    assert(pipelines |> length() == 1)

    // This works as expected. pipelines[0] is memzeroed
    var pipeline <- pipelines[0]
    return <- pipeline

    // TODO: Here pipelines[0] is not memzeroed, and hence gets deleted twice,
    // first time in defer() above, second time -- when caller calls delete
    //return <- pipelines[0]
