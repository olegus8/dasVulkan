options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan

require device


def with_command_pool(
    device : VkDevice#;
    phys_dev : VkPhysicalDevice#;
    surface : VkSurfaceKHR#;
    b : block<(p:VkCommandPool#)>
)
    let qfam = phys_dev |> get_graphics_queue_family(surface)
    let create_info <- [[VkCommandPoolCreateInfo
        sType = VkStructureType VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        queueFamilyIndex = qfam
    ]]
    var pool : VkCommandPool
    verify(VkResult VK_SUCCESS == device |> vkCreateCommandPool(
        safe_addr(create_info), null, safe_addr(pool)))
    b |> invoke(pool)
    device |> vkDestroyCommandPool(pool, null)

