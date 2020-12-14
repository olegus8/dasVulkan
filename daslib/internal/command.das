options indenting = 4
options no_aot = true

require vulkan
require generated


def create_command_buffers_primary(
    device : Device;
    pool : CommandPool;
    count : int
) : CommandBuffers
    return <- device |> create_command_buffers([[
        CommandBufferAllocateInfo
            command_pool = pool,
            command_buffer_count = count,
            level = VkCommandBufferLevel VK_COMMAND_BUFFER_LEVEL_PRIMARY
        ]])
