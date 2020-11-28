options indenting = 4
options no_aot = true

require daslib/safe_addr
require core
require vulkan
require math


struct PhysicalDevices
    physical_devices : array<VkPhysicalDevice>


struct PhysicalDevice
    physical_device : VkPhysicalDevice


def split(devices : PhysicalDevices) : array<PhysicalDevice>
    return <- [{for d in devices.physical_devices ;
        [[PhysicalDevice physical_device=d]]}]


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
        devices.physical_devices |> resize(int(count))
        devices.physical_devices |> lock() <| $(tdevices)
            result ?? result_ = instance |> vkEnumeratePhysicalDevices(
                safe_addr(count), addr(tdevices[0]))
            assert(result_ == VkResult VK_SUCCESS)

    return <- devices


def get_physical_device_properties(physical_device : PhysicalDevice
) : VkPhysicalDeviceProperties
    var props : VkPhysicalDeviceProperties
    physical_device.physical_device |> vkGetPhysicalDeviceProperties(
        safe_addr(props))
    return <- props
