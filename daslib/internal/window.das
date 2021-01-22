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
    var monitor = glfwGetPrimaryMonitor()
    var mode = monitor |> glfwGetVideoMode
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API)
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE)
    glfwWindowHint(GLFW_RED_BITS, mode.redBits)
    glfwWindowHint(GLFW_GREEN_BITS, mode.greenBits)
    glfwWindowHint(GLFW_BLUE_BITS, mode.blueBits)
    glfwWindowHint(GLFW_REFRESH_RATE, mode.refreshRate)
    return <- [[Window window = glfwCreateWindow(mode.width, mode.height,
        title, monitor, [[GLFWwindow_DasHandle]]
    )]]


def finalize(var window : Window explicit)
    if window._needs_delete
        window.window |> glfwDestroyWindow()
    memzero(window)


def get_framebuffer_size(window : Window)
    var width, height : int
    window.window |> glfwGetFramebufferSize(
        safe_addr(width), safe_addr(height))
    return uint2(uint(width), uint(height))
