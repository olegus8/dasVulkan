options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan

//
// Command pool
//

struct CommandPool
    device : VkDevice
    pool : VkCommandPool


def create_command_pool(
    device : VkDevice#;
    queue_family : uint;
    flags : uint = 0u
) : CommandPool
    let create_info <- [[VkCommandPoolCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        queueFamilyIndex = queue_family,
        flags = flags
    ]]
    var pool : CommandPool
    unsafe
        pool.device = reinterpret<VkDevice>(device)
    verify(VkResult VK_SUCCESS == device |> vkCreateCommandPool(
        safe_addr(create_info), null, safe_addr(pool.pool)))
    return <- pool


def finalize(var pool : CommandPool)
    pool.device |> vkDestroyCommandPool(pool.pool, null)
    memzero(pool)

//
// Command buffer
//

//TODO: this does not work saying:
//  too many custom  finalize functions exist for
//  finalize ( bufs : command::CommandBuffers -const ) : void
//  candidates are:
//      command::finalize ( bufs : command::CommandBuffers -const ) : void
//      command::finalize ( pool : command::CommandPool -const ) : void
//
//  It works if I change order so that "device" and "pool" are not in the
//  same order as they appear in CommandPool
/*
struct CommandBuffers
    device : VkDevice
    pool : VkCommandPool
    buffers : array<VkCommandBuffer>
*/

struct CommandBuffers
    buffers : array<VkCommandBuffer>
    device : VkDevice
    pool : VkCommandPool


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
