options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan


struct Window
    window : GLFWwindow_DasHandle
    _needs_delete : bool


def create_window(width : int; height : int; title : string;
    resizable : bool = true
) : Window
    glfwWindowHint(GLFW_RESIZABLE, resizable ? GLFW_TRUE : GLFW_FALSE)
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
    return <- [[Window window = glfwCreateWindow(width, height, title,
            [[GLFWmonitor_DasHandle]], [[GLFWwindow_DasHandle]]
    )]]


def create_fullscreen_window(title : string) : Window
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE)
    var monitor = glfwGetPrimaryMonitor()
    var vidmode = monitor |> glfwGetVideoMode


def finalize(var window : Window explicit)
    if window._needs_delete
        window.window |> glfwDestroyWindow()
    memzero(window)


def get_framebuffer_size(window : Window)
    var width, height : int
    window.window |> glfwGetFramebufferSize(
        safe_addr(width), safe_addr(height))
    return uint2(uint(width), uint(height))
