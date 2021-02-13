options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan
require glfw


struct Window
    window : GLFWwindow ?
    _needs_delete : bool


def create_window(width : int; height : int; title : string;
    resizable : bool = true
) : Window
    glfwWindowHint(int(GLFW_RESIZABLE), resizable ? GLFW_TRUE : GLFW_FALSE)
    glfwWindowHint(int(GLFW_CLIENT_API), GLFW_NO_API)
    return <- [[Window window = glfwCreateWindow(width, height, title,
        [[GLFWmonitor ?]], [[GLFWwindow ?]]
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
    var window = glfwCreateWindow(mode.width, mode.height,
        title, monitor, [[GLFWwindow ?]])
    return <- [[Window window=window]]


def finalize(var window : Window explicit)
    if window._needs_delete
        window.window |> glfwDestroyWindow()
    memzero(window)


def get_framebuffer_size(window : Window)
    var width, height : int
    window.window |> glfwGetFramebufferSize(
        safe_addr(width), safe_addr(height))
    return uint2(uint(width), uint(height))
