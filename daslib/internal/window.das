options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan


struct Window
    window : GLFWwindow_DasHandle
    _needs_delete : bool


def create_window(width : int; height : int; title : string) : Window
    return <- [[Window window = glfwCreateWindow(width, height, title,
            [[GLFWmonitor_DasHandle]], [[GLFWwindow_DasHandle]]
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
