options indenting = 4
options no_aot = true

require vulkan
require generated


def allocate_command_buffers_primary(
    device : Device;
    pool : CommandPool;
    count : int
) : CommandBuffers
    return <- device |> allocate_command_buffers([[
        CommandBufferAllocateInfo
            command_pool = pool,
            command_buffer_count = uint(count),
            level = VkCommandBufferLevel VK_COMMAND_BUFFER_LEVEL_PRIMARY
        ]])


def create_command_pool(
    device : Device;
    queue_family : uint;
    flags : uint = 0u
) : CommandPool
    return <- device |> create_command_pool([[CommandPoolCreateInfo
        queue_family_index = queue_family,
        flags = flags
    ]])
