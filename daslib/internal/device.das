options indenting = 4
options no_aot = true

require daslib/safe_addr
require daslib/defer
require core
require vulkan
require math
require strings

require generated public


def get_physical_device_surface_formats_khr(
    physical_device : PhysicalDevice;
    surface         : VkSurfaceKHR;
    var result      : VkResult? = [[VkResult?]]
) : array<VkSurfaceFormatKHR>

    let vk_dev = physical_device.physical_device
    var result_ = VkResult VK_SUCCESS
    var count : uint

    result ?? result_ = vk_dev |> vkGetPhysicalDeviceSurfaceFormatsKHR(
        surface, safe_addr(count), null)
    assert(result_ == VkResult VK_SUCCESS)

    var formats : array<VkSurfaceFormatKHR>
    if result ?? result_ == VkResult VK_SUCCESS
        formats |> resize(int(count))
        formats |> lock() <| $(tformats)
            result ?? result_ = vk_dev |> vkGetPhysicalDeviceSurfaceFormatsKHR(
                surface, safe_addr(count), addr(tformats[0]))
            assert(result_ == VkResult VK_SUCCESS)

    return <- formats


def get_physical_device_queue_family_properties(
    physical_device : PhysicalDevice
) : array<VkQueueFamilyProperties>

    let vk_dev = physical_device.physical_device
    var count : uint
    vk_dev |> vkGetPhysicalDeviceQueueFamilyProperties(safe_addr(count), null)

    var props : array<VkQueueFamilyProperties>
    props |> resize(int(count))
    props |> lock() <| $(tprops)
        vk_dev |> vkGetPhysicalDeviceQueueFamilyProperties(
            safe_addr(count), addr(tprops[0]))

    return <- props


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
