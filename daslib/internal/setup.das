options indenting = 4
options no_aot = true

require daslib/safe_addr
require daslib/defer
require core
require vulkan
require device
require generated
require window
require instance
require descriptor_pool


struct SimpleVulkanSetup
    window    : Window
    instance  : InstanceEx
    surface   : SurfaceKHR
    phys_dev  : PhysicalDevice
    device    : Device
    queue     : Queue
    desc_pool : DescriptorPool
    gfx_qfam  : uint


def finalize(var x : SimpleVulkanSetup explicit)
    x.device |> device_wait_idle
    delete x.desc_pool
    delete x.device
    delete x.surface
    delete x.instance
    delete x.window


def simple_vulkan_setup(title : string; width,height : int) : SimpleVulkanSetup
    var s : SimpleVulkanSetup
    s.window <- create_window(width, height, title)
    s.instance <- create_instance_ex()
    s.surface <- s.instance.instance |> create_window_surface(s.window)
    s.phys_dev <- s.instance.instance |> find_best_physical_device(
        s.surface, @@simple_device_score)
    s.gfx_qfam = s.phys_dev |> get_graphics_queue_family(s.surface, 1)
    s.device <- s.phys_dev |> create_simple_device(s.gfx_qfam)
    s.queue <- s.device |> get_device_queue(s.gfx_qfam)
    s.desc_pool <- s.device |> create_simple_descriptor_pool
    return <- s
