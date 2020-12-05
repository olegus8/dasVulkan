options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan
require fio


def to_string(bytes : void?)
    unsafe
        return reinterpret<string>(bytes)


//TODO: need this for heap
def safe_addr_plain(x : auto(T)) : T ? #
    unsafe
        return reinterpret<T?#>(addr(x))


//TODO: need this for heap
def safe_addr_val(var x : auto(T)&) : T-& ? #
    unsafe
        return reinterpret<T-&?#>(addr(x))


def read_file_to_array(file_path : string) : array<uint8>
    var data : array<uint8>
    fopen(file_path, "rb") <| $(f : FILE const ?)
        data |> resize(int((f |> fstat()).size))
        f |> fmap() <| $(fdata : string implicit)
            data |> lock() <| $(tdata)
                for dst, i in tdata, range(INT_MAX)
                    unsafe
                        dst = *(reinterpret<uint8 const?>(fdata) + i)
    return <- data


def with_window(width : int; height : int; title : string;
    b : block<(w:GLFWwindow_DasHandle#)>
)
    var window = glfwCreateWindow(width, height, title,
        [[GLFWmonitor_DasHandle]], [[GLFWwindow_DasHandle]])
    b |> invoke(window)
    window |> glfwDestroyWindow()


def with_surface(window : GLFWwindow_DasHandle#; instance : VkInstance#;
    b : block<(s:VkSurfaceKHR#)>
)
    var surface : VkSurfaceKHR
    verify(VkResult VK_SUCCESS == instance |> glfwCreateWindowSurface(
        window, null, safe_addr(surface)))
    b |> invoke(surface)
    instance |> vkDestroySurfaceKHR(surface, null)


def get_framebuffer_size(window : GLFWwindow_DasHandle#)
    var width, height : int
    window |> glfwGetFramebufferSize(safe_addr(width), safe_addr(height))
    return uint2(uint(width), uint(height))
