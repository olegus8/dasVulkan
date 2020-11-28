options indenting = 4
options no_aot = true

require daslib/safe_addr
require core
require vulkan
require math


struct PhysicalDevices
    devices : array<VkPhysicalDevice>


struct PhysicalDevice
    device : VkPhysicalDevice


def enumerate_physical_devices(
    instance : VkInstance;
    var result : VkResult? = [[VkResult?]]
) : PhysicalDevices

    var devices : PhysicalDevices
    var count : uint
    var result_ = VkResult VK_SUCCESS

    result ?? result_ = instance |> vkEnumeratePhysicalDevices(
        safe_addr(count), null)
    assert(result_ == VkResult VK_SUCCESS)

    if result ?? result_ == VkResult VK_SUCCESS
        devices.devices |> resize(int(count))
        devices.devices |> lock() <| $(tdevices)
            result ?? result_ = instance |> vkEnumeratePhysicalDevices(
                safe_addr(count), addr(tdevices[0]))
            assert(result_ == VkResult VK_SUCCESS)

    return <- devices


def split(devices : PhysicalDevices) : array<PhysicalDevice>
    return <- [{for d in devices ; [[PhysicalDevice device=d]]}]
