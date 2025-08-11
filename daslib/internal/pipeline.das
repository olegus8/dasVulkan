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


def create_compute_pipeline(
    device : Device = [[ Device ]];
    pipeline_cache : PipelineCache = [[ PipelineCache ]];
    var create_info : ComputePipelineCreateInfo = [[
        ComputePipelineCreateInfo ]];
    var result : VkResult? = [[VkResult?]]
) : Pipeline

    var create_infos <- [{ auto[] clone_to_move(create_info) }]
    defer() <| ${ delete create_infos; }
    var pipelines <- create_compute_pipelines([
        device = device,
        pipeline_cache = pipeline_cache,
        create_infos = create_infos,
        result = result
    ])
    defer() <| ${ delete pipelines; }
    assert(pipelines |> length() == 1)

    var pipeline <- pipelines[0]
    return <- pipeline


def create_ray_tracing_pipeline(
    device : Device = [[ Device ]];
    deferred_operation : DeferredOperationKHR = [[ DeferredOperationKHR ]];
    pipeline_cache : PipelineCache = [[ PipelineCache ]];
    var create_info : RayTracingPipelineCreateInfoKHR = [[
        RayTracingPipelineCreateInfoKHR ]];
    var result : VkResult? = [[VkResult?]]
) : Pipeline

    var create_infos <- [{ auto[] clone_to_move(create_info) }]
    defer() <| ${ delete create_infos; }
    var pipelines <- create_ray_tracing_pipelines_khr([
        device = device,
        deferred_operation = deferred_operation,
        pipeline_cache = pipeline_cache,
        create_infos = create_infos,
        result = result
    ])
    defer() <| ${ delete pipelines; }
    assert(pipelines |> length() == 1)

    var pipeline <- pipelines[0]
    return <- pipeline


def create_ray_tracing_pipeline(
    device                    : Device;
    var create_info           : RayTracingPipelineCreateInfoKHR;
    var shader_group_handles  : array<auto(HANDLE_T)> &
) : Pipeline
    let groups_count = length(create_info.groups)
    var pipeline <- create_ray_tracing_pipeline([
      device=device, create_info=create_info])
    shader_group_handles |> resize(groups_count)
    var p_handles : void ?
    unsafe
        p_handles = addr(shader_group_handles[0])
    var result : VkResult
    result = vkGetRayTracingShaderGroupHandlesKHR(
        device, pipeline.pipeline, 0u, uint(groups_count),
        uint(length(shader_group_handles) * typeinfo(sizeof type<HANDLE_T>)),
        p_handles)
    assert(result == VkResult VK_SUCCESS)
    return <- pipeline
