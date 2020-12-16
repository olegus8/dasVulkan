#include "daScript/daScript.h"

#include "headers_to_bind.h"

using namespace das;

template <typename OT>
struct VkHandleAnnotation : public ManagedValueAnnotation<OT> {
    VkHandleAnnotation(const string & n, const string & cpn = string())
    : ManagedValueAnnotation<OT>(n,cpn) {
    }
    virtual bool canClone() const override {
        return true;
    }
    virtual SimNode * simulateClone ( Context & context, const LineInfo & at, SimNode * l, SimNode * r ) const override {
        return ManagedValueAnnotation<OT>::simulateCopy(context, at, l, r);
    }
};

#include "module_generated.inc"

void addVulkanCustom(Module &, ModuleLibrary &);

struct WindowContext {
    Context * ctx = nullptr;
    SimFunction * framebuffer_size_callback = nullptr;
};

GLFWwindow* glfw_create_window(int width, int height, const char* title,
    GLFWmonitor* monitor, GLFWwindow* share, Context * ctx
) {
    auto wnd = glfwCreateWindow(width, height, title, monitor, share);
    if ( wnd ) {
        auto window_ctx = new WindowContext();
        window_ctx->ctx = ctx;
        glfwSetWindowUserPointer(wnd, window_ctx);
    }
    return wnd;
}

void glfw_destroy_window(GLFWwindow* window) {
    auto window_ctx = reinterpret_cast<WindowContext*>(
        glfwGetWindowUserPointer(window));
    delete window_ctx;
    glfwDestroyWindow(window);
}

void glfw_framebuffer_size_callback(
    GLFWwindow* window, int width, int height
) {
    auto window_ctx = reinterpret_cast<WindowContext*>(
        glfwGetWindowUserPointer(window));
    vec4f args[3] = {
        cast<GLFWwindow *>::from(window),
        cast<int32_t>::from(width),
        cast<int32_t>::from(height)
    };
    window_ctx->ctx->eval(window_ctx->framebuffer_size_callback, args);
}

void glfw_set_framebuffer_size_callback(
    GLFWwindow * window, const char * func_name, Context * ctx
) {
    auto window_ctx = reinterpret_cast<WindowContext*>(
        glfwGetWindowUserPointer(window));
    if ( window_ctx->ctx != ctx )
        ctx->throw_error("must call from same context as was window created");
    if ( ! window_ctx->framebuffer_size_callback ) {
        glfwSetFramebufferSizeCallback(
            window, glfw_framebuffer_size_callback);
    }
    window_ctx->framebuffer_size_callback = window_ctx->ctx->findFunction(
        func_name);
    if ( ! window_ctx->framebuffer_size_callback ) {
        window_ctx->ctx->throw_error(("callback function \""
            + string(func_name) + "\" not found").c_str());
    }
}

class Module_vulkan : public GeneratedModule_vulkan {
public:
    Module_vulkan() : GeneratedModule_vulkan() {
        ModuleLibrary lib;
        lib.addModule(this);
        lib.addBuiltInModule();
        addGenerated(lib);
        addVulkanCustom(*this, lib);
        addExtern<DAS_BIND_FUN(glfw_create_window)>(
            *this, lib, "glfwCreateWindow",
            SideEffects::worstDefault, "glfwCreateWindow");
        addExtern<DAS_BIND_FUN(glfw_destroy_window)>(
            *this, lib, "glfwDestroyWindow",
            SideEffects::worstDefault, "glfwDestroyWindow");
        addExtern<DAS_BIND_FUN(glfw_set_framebuffer_size_callback)>(
            *this, lib, "glfwSetFramebufferSizeCallback",
            SideEffects::worstDefault, "glfwSetFramebufferSizeCallback");
    }
};

REGISTER_MODULE(Module_vulkan);
