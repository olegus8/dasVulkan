options indenting = 4
options no_aot = true

require daslib/defer
require core
require generated


def create_command_pool(
    device : Device;
    queue_family : uint;
    flags : uint = 0u
) : CommandPool
    return <- device |> create_command_pool([[CommandPoolCreateInfo
        queue_family_index = queue_family,
        flags = flags
    ]])
