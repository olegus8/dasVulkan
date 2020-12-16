#include "daScript/daScript.h"

#define GLFW_INCLUDE_VULKAN
#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

using namespace das;

GLFWwindow* glfw_create_window(int width, int height, const char* title,
    GLFWmonitor* monitor, GLFWwindow* share
) {
    return glfwCreateWindow(width, height, title, monitor, share);
}

void glfw_destroy_window(GLFWwindow* window) {
    glfwDestroyWindow(window);
}

void my_cpp_func(Context * ctx) {
    auto fx = ctx->findFunction("my_das_func");
    if (!fx) {
        ctx->throw_error("function not found");
        return;
    }
    ctx->eval(fx, nullptr);
}

void addVulkanCustom(Module & module, ModuleLibrary & lib) {
    addExtern<DAS_BIND_FUN(my_cpp_func)>(module, lib, "my_cpp_func",
        SideEffects::worstDefault, "my_cpp_func");
    addExtern<DAS_BIND_FUN(glfw_create_window)>(
        module, lib, "glfwCreateWindow",
        SideEffects::worstDefault, "glfwCreateWindow");
    addExtern<DAS_BIND_FUN(glfw_destroy_window)>(
        module, lib, "glfwDestroyWindow",
        SideEffects::worstDefault, "glfwDestroyWindow");
}
