options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan

require device

//
// Command pool
//

struct CommandPool
    device : VkDevice
    pool : VkCommandPool


def create_command_pool(
    device : VkDevice#;
    queue_family : uint;
    flags : uint
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
    count : int
) : CommandBuffers
    let alloc_info <- [[VkCommandBufferAllocateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        level = VkCommandBufferLevel VK_COMMAND_BUFFER_LEVEL_PRIMARY,
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


def finalize(var bufs : CommandBuffers)
    bufs.buffers |> lock() <| $(tbufs)
        bufs.device |> vkFreeCommandBuffers(
            bufs.pool, uint(bufs.buffers |> length()), addr(tbufs[0]))
    delete bufs.buffers
    memzero(bufs)
