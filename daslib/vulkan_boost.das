options indenting = 4
options no_aot = true

module vulkan_boost

require vulkan
require daslib/safe_addr


def with_physical_devices(inst; b : block<(d:array<VkPhysicalDevice>)>)
    var devices : array<VkPhysicalDevice>
    var count : uint
    verify(VkResult VK_SUCCESS == inst |> vkEnumeratePhysicalDevices(
        safe_addr(count), null))
    devices |> resize(int(count))
    devices |> lock() <| $(tdevices)
        verify(VkResult VK_SUCCESS == inst |> vkEnumeratePhysicalDevices(
            safe_addr(count), addr(tdevices[0])))
    b |> invoke(devices)
    delete devices
