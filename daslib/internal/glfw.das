options indenting = 4
options no_aot = true

require daslib/safe_addr
require vulkan


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
