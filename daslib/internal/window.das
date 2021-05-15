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
    glfwWindowHint(int(GLFW_CLIENT_API), GLFW_NO_API)
    glfwWindowHint(int(GLFW_RESIZABLE), GLFW_FALSE)
    glfwWindowHint(int(GLFW_RED_BITS), mode.redBits)
    glfwWindowHint(int(GLFW_GREEN_BITS), mode.greenBits)
    glfwWindowHint(int(GLFW_BLUE_BITS), mode.blueBits)
    glfwWindowHint(int(GLFW_REFRESH_RATE), mode.refreshRate)
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


def get_required_instance_extensions() : array<string>
    var exts : array<string>
    var count : uint
    let glfw_exts : string const ? = glfwGetRequiredInstanceExtensions(
        safe_addr(count))
    exts |> resize(int(count))
    for ext, i in exts, range(INT_MAX)
        unsafe
            ext := *(glfw_exts + i)
    return <- exts


def get_cursor_pos(window : Window) : float2
    var xpos, ypos : double
    window.window |> glfwGetCursorPos(safe_addr(xpos), safe_addr(ypos))
    return float2(float(xpos), float(ypos))
