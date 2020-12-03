options indenting = 4
options no_aot = true

require daslib/safe_addr
require daslib/defer
require core
require vulkan
require math
require strings

require generated public


def get_physical_device_surface_present_modes_khr(
    physical_device : PhysicalDevice;
    surface         : VkSurfaceKHR;
    var result      : VkResult? = [[VkResult?]]
) : array<VkPresentModeKHR>

    let vk_dev = physical_device.physical_device
    var result_ = VkResult VK_SUCCESS
    var count : uint

    result ?? result_ = vk_dev |> vkGetPhysicalDeviceSurfacePresentModesKHR(
        surface, safe_addr(count), null)
    assert(result_ == VkResult VK_SUCCESS)

    var modes : array<VkPresentModeKHR>
    if result ?? result_ == VkResult VK_SUCCESS
        modes |> resize(int(count))
        modes |> lock() <| $(tmodes)
            result ?? result_ = (
                vk_dev |> vkGetPhysicalDeviceSurfacePresentModesKHR(
                    surface, safe_addr(count), addr(tmodes[0])))
            assert(result_ == VkResult VK_SUCCESS)

    return <- modes
