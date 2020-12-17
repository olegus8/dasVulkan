options indenting = 4
options no_aot = true

require daslib/defer
require vulkan
require generated


def cmd_bind_descriptor_set(
    command_buffer : CommandBuffer;
    pipeline_bind_point : VkPipelineBindPoint;
    layout : PipelineLayout;
    descriptor_set : DescriptorSet;
    first_set : uint = [[ uint ]]
) : void
    var dsets <- [{ auto[] weak_copy(descriptor_set) }]
    defer() <| { delete dsets; }
    cmd_bind_descriptor_sets([
        command_buffer = command_buffer,
        pipeline_bind_point = pipeline_bind_point,
        layout = layout,
        first_set = first_set,
        descriptor_sets = dsets])
        
