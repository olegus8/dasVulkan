options indenting = 4
options no_aot = true

require daslib/defer
require daslib/safe_addr

require vulkan

//
// Helpers
//

def with_p_view(
    p_boost_struct : auto(BOOST_T)?;
    b : block<(p_vk_struct : auto(VK_T)?)>
)
    if p_boost_struct == null
        b |> invoke([[VK_T?]])
    else
        *p_boost_struct |> with_view() <| $(vk_struct)
            unsafe
                b |> invoke(addr(vk_struct))

def to_string(bytes : int8[])
    unsafe
        return reinterpret<string>(addr(bytes[0]))

//
// Surface
//

struct SurfaceKHR
    surface_khr : VkSurfaceKHR
    _instance : VkInstance

def create_window_surface(
    instance : Instance = [[ Instance ]];
    window : GLFWwindow_DasHandle = [[ GLFWwindow_DasHandle ]];
    var result : VkResult? = [[VkResult?]]
) : SurfaceKHR

    var surface <- [[SurfaceKHR _instance=instance.instance]]
    var result_ = VkResult VK_SUCCESS
    result ?? result_ = glfwCreateWindowSurface(
        instance,
        window,
        null,
        safe_addr(surface.surface_khr)
    )
    assert(result_ == VkResult VK_SUCCESS)
    return <- surface

def finalize(var surface : SurfaceKHR)
    vkDestroyInstance(
        surface._instance,
        surface.surface_khr,
        null
    )
    memzero(surface)
