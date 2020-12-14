options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan


struct CommandBuffers
    buffers : array<VkCommandBuffer>
    _device : VkDevice
    _pool : VkCommandPool


def create_command_buffers(
    device : VkDevice#;
    pool : VkCommandPool#;
    count : int;
    level : VkCommandBufferLevel
) : CommandBuffers
    let alloc_info <- [[VkCommandBufferAllocateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        level = level,
        commandPool = pool,
        commandBufferCount = uint(count)
    ]]
    var bufs : CommandBuffers
    unsafe
        bufs.device = reinterpret<VkDevice>(device)
        bufs.pool = reinterpret<VkCommandPool>(pool)
    bufs.buffers |> resize(count)
    bufs.buffers |> lock() <| $(tbufs)
        verify(VkResult VK_SUCCESS == device |> vkAllocateCommandBuffers(
            safe_addr(alloc_info), addr(tbufs[0])))
    return <- bufs


def create_command_buffers_primary(
    device : VkDevice#;
    pool : VkCommandPool#;
    count : int
) : CommandBuffers
    return <- device |> create_command_buffers(pool, count,
        VkCommandBufferLevel VK_COMMAND_BUFFER_LEVEL_PRIMARY)


def finalize(var bufs : CommandBuffers)
    bufs.buffers |> lock() <| $(tbufs)
        bufs.device |> vkFreeCommandBuffers(
            bufs.pool, uint(bufs.buffers |> length()), addr(tbufs[0]))
    delete bufs.buffers
    memzero(bufs)
