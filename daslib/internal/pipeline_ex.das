options indenting = 4
options no_aot = true

require daslib/safe_addr
require daslib/defer

require vulkan
require device_ex
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
