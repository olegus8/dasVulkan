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

struct CommandBuffer
    pool : VkCommandPool
    buffer : VkCommandBuffer
