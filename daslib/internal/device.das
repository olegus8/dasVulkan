options indenting = 4
options no_aot = true

require daslib/safe_addr
require daslib/defer
require core
require vulkan
require math
require strings


struct PhysicalDevices
    physical_devices : array<VkPhysicalDevice>


struct PhysicalDevice
    physical_device : VkPhysicalDevice


struct ExtensionProperties
    extension_name : string
    spec_version : uint


def split(devices : PhysicalDevices) : array<PhysicalDevice>
    return <- [{for d in devices.physical_devices ;
        [[PhysicalDevice physical_device=d]]}]


def enumerate_physical_devices(
    instance : VkInstance;
    var result : VkResult? = [[VkResult?]]
) : PhysicalDevices

    var count : uint
    var result_ = VkResult VK_SUCCESS

    result ?? result_ = instance |> vkEnumeratePhysicalDevices(
        safe_addr(count), null)
    assert(result_ == VkResult VK_SUCCESS)

    var vk_devs : array<VkPhysicalDevice>
    if result ?? result_ == VkResult VK_SUCCESS
        vk_devs |> resize(int(count))
        vk_devs |> lock() <| $(tdevs)
            result ?? result_ = instance |> vkEnumeratePhysicalDevices(
                safe_addr(count), addr(tdevs[0]))
            assert(result_ == VkResult VK_SUCCESS)

    return <- [[PhysicalDevices physical_devices <- vk_devs]]


def get_physical_device_properties(physical_device : PhysicalDevice
) : VkPhysicalDeviceProperties
    var props : VkPhysicalDeviceProperties
    physical_device.physical_device |> vkGetPhysicalDeviceProperties(
        safe_addr(props))
    return <- props


def enumerate_device_extension_properties(
    physical_device : PhysicalDevice;
    layer_name      : string = [[string]];
    var result      : VkResult? = [[VkResult?]]
) : array<ExtensionProperties>

    let vk_dev = physical_device.physical_device
    var result_ = VkResult VK_SUCCESS
    var vk_layer = layer_name |> length() > 0 ? layer_name : to_string(null)
    var count : uint

    result ?? result_ = vk_dev |> vkEnumerateDeviceExtensionProperties(
        vk_layer, safe_addr(count), null)
    assert(result_ == VkResult VK_SUCCESS)

    var vk_props : array<VkExtensionProperties>
    defer() <| ${ delete vk_props; }
    if result ?? result_ == VkResult VK_SUCCESS
        vk_props |> resize(int(count))
        vk_props |> lock() <| $(tprops)
            result ?? result_ = vk_dev |> vkEnumerateDeviceExtensionProperties(
                vk_layer, safe_addr(count), addr(tprops[0]))
            assert(result_ == VkResult VK_SUCCESS)
        
    return <- [{for p in vk_props; [[ExtensionProperties
        extension_name = to_string(p.extensionName),
        spec_version = p.specVersion
    ]]}]


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
