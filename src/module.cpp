#include "module.h"

MAKE_TYPE_FACTORY(PFN_vkDebugUtilsMessengerCallbackEXT, PFN_vkDebugUtilsMessengerCallbackEXT);

#include "module_generated.inc"
#include "module_boost_generated.inc"

void addVulkanCustomBeforeGenerated(Module &, ModuleLibrary &);
void addVulkanCustomAfterGenerated(Module &, ModuleLibrary &);


struct WindowContext {
    Context * ctx = nullptr;
    SimFunction * framebuffer_size_callback = nullptr;
    SimFunction * key_callback = nullptr;
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
    GLFWwindow * window, Func fn, Context * ctx
) {
    auto window_ctx = reinterpret_cast<WindowContext*>(
        glfwGetWindowUserPointer(window));
    if ( window_ctx->ctx != ctx ) {
        ctx->throw_error("must call from same context as was window created");
    }
    if ( ! window_ctx->framebuffer_size_callback ) {
        glfwSetFramebufferSizeCallback(
            window, glfw_framebuffer_size_callback);
    }
    window_ctx->framebuffer_size_callback = window_ctx->ctx->getFunction(
        fn.index-1);
    if ( ! window_ctx->framebuffer_size_callback ) {
        window_ctx->ctx->throw_error("callback function not found");
    }
}

void glfw_key_callback(
    GLFWwindow* window, int key, int scancode, int action, int mods
) {
    auto window_ctx = reinterpret_cast<WindowContext*>(
        glfwGetWindowUserPointer(window));
    vec4f args[5] = {
        cast<GLFWwindow *>::from(window),
        cast<int32_t>::from(key),
        cast<int32_t>::from(scancode),
        cast<int32_t>::from(action),
        cast<int32_t>::from(mods)
    };
    window_ctx->ctx->eval(window_ctx->key_callback, args);
}

void glfw_set_key_callback(GLFWwindow * window, Func fn, Context * ctx) {
    auto window_ctx = reinterpret_cast<WindowContext*>(
        glfwGetWindowUserPointer(window));
    if ( window_ctx->ctx != ctx ) {
        ctx->throw_error("must call from same context as was window created");
    }
    if ( ! window_ctx->key_callback ) {
        glfwSetKeyCallback(window, glfw_key_callback);
    }
    window_ctx->key_callback = window_ctx->ctx->getFunction(fn.index-1);
    if ( ! window_ctx->key_callback ) {
        window_ctx->ctx->throw_error("callback function not found");
    }
}


static VKAPI_ATTR VkBool32 VKAPI_CALL vk_debug_msg_callback(
    VkDebugUtilsMessageSeverityFlagBitsEXT      msg_severity,
    VkDebugUtilsMessageTypeFlagsEXT             msg_type,
    const VkDebugUtilsMessengerCallbackDataEXT* callback_data,
    void*                                       user_data
) {
    auto debug_ctx = reinterpret_cast<DebugMsgContext*>(user_data);

    //TODO: make it thread safe one day
    if ( this_thread::get_id() != debug_ctx->thread_id ) {
      DAS_FATAL_ERROR
    }

    vec4f args[5] = {
        cast<Lambda>::from(debug_ctx->cb_lambda),
        cast<VkDebugUtilsMessageSeverityFlagBitsEXT>::from(msg_severity),
        cast<VkDebugUtilsMessageTypeFlagsEXT>::from(msg_type),
        cast<const VkDebugUtilsMessengerCallbackDataEXT *>::from(callback_data)
    };
    auto result = debug_ctx->ctx->call(debug_ctx->cb_func, args, 0);
    return cast<VkBool32>::to(result);
}

/*
VkResult vkCreateDebugUtilsMessengerEXT(
    VkInstance                                  instance,
    const VkDebugUtilsMessengerCreateInfoEXT*   create_info,
    const VkAllocationCallbacks*                allocator,
    VkDebugUtilsMessengerEXT*                   messenger
) {
    //TODO: use real vulkan loader with ptr cache
    auto vk_func = (PFN_vkCreateDebugUtilsMessengerEXT)
        vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT");
    if (vk_func == nullptr) {
        return VK_ERROR_EXTENSION_NOT_PRESENT;
    }
    return vk_func(instance, create_info, allocator, messenger);
}

void vkDestroyDebugUtilsMessengerEXT(
    VkInstance                    instance,
    VkDebugUtilsMessengerEXT      messenger,
    const VkAllocationCallbacks*  allocator
) {
    //TODO: use real vulkan loader with ptr cache
    auto vk_func = (PFN_vkDestroyDebugUtilsMessengerEXT)
        vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT");
    if (vk_func == nullptr) {
        DAS_ASSERTF(0, "vkDestroyDebugUtilsMessengerEXT not found");
        return;
    }
    vk_func(instance, messenger, allocator);
}
*/

class Module_vulkan : public GeneratedModule_vulkan {
public:
    Module_vulkan() : GeneratedModule_vulkan() {
        ModuleLibrary lib;
        lib.addModule(this);
        lib.addBuiltInModule();

        addAnnotation(make_smart<VkHandleAnnotation<
            PFN_vkDebugUtilsMessengerCallbackEXT> >(
              "PFN_vkDebugUtilsMessengerCallbackEXT",
              "PFN_vkDebugUtilsMessengerCallbackEXT"
        ));

        addVulkanCustomBeforeGenerated(*this, lib);
        addGenerated(lib);
        addBoostGenerated(*this, lib);
        addVulkanCustomAfterGenerated(*this, lib);

        addConstant(*this, "vk_debug_msg_callback",
            reinterpret_cast<uint64_t>(&vk_debug_msg_callback));

        addExtern<DAS_BIND_FUN(glfw_create_window)>(
            *this, lib, "glfwCreateWindow",
            SideEffects::worstDefault, "glfwCreateWindow");
        addExtern<DAS_BIND_FUN(glfw_destroy_window)>(
            *this, lib, "glfwDestroyWindow",
            SideEffects::worstDefault, "glfwDestroyWindow");
        addExtern<DAS_BIND_FUN(glfw_set_framebuffer_size_callback)>(
            *this, lib, "glfwSetFramebufferSizeCallback",
            SideEffects::worstDefault, "glfwSetFramebufferSizeCallback");
        addExtern<DAS_BIND_FUN(glfw_set_key_callback)>(
            *this, lib, "glfwSetKeyCallback",
            SideEffects::worstDefault, "glfwSetKeyCallback");
    }
};

REGISTER_MODULE(Module_vulkan);
