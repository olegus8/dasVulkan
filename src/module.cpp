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

struct DebugMsgContext {
    Context * ctx = nullptr;
    SimFunction * cb_func = nullptr;
    Lambda cb_lambda;
};

typedef DebugMsgContext * DebugMsgContext_DasHandle;
MAKE_TYPE_FACTORY(DebugMsgContext_DasHandle, DebugMsgContext_DasHandle)

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
    vec4f args[5] = {
        cast<Lambda>::from(debug_ctx->cb_lambda),
        cast<VkDebugUtilsMessageSeverityFlagBitsEXT>::from(msg_severity),
        cast<VkDebugUtilsMessageTypeFlagsEXT>::from(msg_type),
        cast<const VkDebugUtilsMessengerCallbackDataEXT *>::from(callback_data)
    };
    auto result = debug_ctx->ctx->call(debug_ctx->cb_func, args, 0);
    return cast<VkBool32>::to(result);
}

DebugMsgContext * create_debug_msg_context(Lambda callback, Context * ctx) {
    auto debug_ctx = new DebugMsgContext();
    debug_ctx->ctx = ctx;
    int32_t * fn_index = (int32_t *) callback.capture;
    if ( ! fn_index ) {
        delete debug_ctx;
        ctx->throw_error("null callback lambda");
        return nullptr;
    }
    debug_ctx->cb_func = ctx->getFunction(*fn_index-1);
    if ( ! debug_ctx->cb_func ) {
        delete debug_ctx;
        ctx->throw_error("callback function not found");
        return nullptr;
    }
    debug_ctx->cb_lambda = callback;
    return debug_ctx;
}

void destroy_debug_msg_context(DebugMsgContext * debug_ctx, Context * ctx) {
    if ( debug_ctx == nullptr ) {
        ctx->throw_error("debug_ctx must not be null");
    }
    if ( debug_ctx->ctx != ctx ) {
        ctx->throw_error("must call from same context as was created");
    }
    delete debug_ctx;
}

VkResult vk_create_debug_utils_messenger_ex(
    VkInstance                                  instance,
    const VkDebugUtilsMessengerCreateInfoEXT*   create_info,
    const VkAllocationCallbacks*                allocator,
    VkDebugUtilsMessengerEXT*                   messenger,
    Context *                                   ctx
) {
    auto vk_func = (PFN_vkCreateDebugUtilsMessengerEXT)
        vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT");
    if (vk_func == nullptr) {
        return VK_ERROR_EXTENSION_NOT_PRESENT;
    }

    VkDebugUtilsMessengerCreateInfoEXT final_info = *create_info;
    final_info.pfnUserCallback = vk_debug_msg_callback;
    return vk_func(instance, &final_info, allocator, messenger);
}

void vk_destroy_debug_utils_messenger_ex(
    VkInstance                                  instance,
    VkDebugUtilsMessengerEXT                    messenger,
    DebugMsgContext*                            debug_ctx,
    const VkAllocationCallbacks*                allocator,
    Context *                                   ctx
) {
    auto vk_func = (PFN_vkDestroyDebugUtilsMessengerEXT)
        vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT");
    if (vk_func == nullptr) {
        ctx->throw_error("vkDestroyDebugUtilsMessengerEXT not found");
    }
    if ( debug_ctx == nullptr ) {
        ctx->throw_error("debug_ctx must not be null");
    }
    if ( debug_ctx->ctx != ctx ) {
        ctx->throw_error("must call from same context as was created");
    }
    vk_func(instance, messenger, allocator);
    delete debug_ctx;
}


class Module_vulkan : public GeneratedModule_vulkan {
public:
    Module_vulkan() : GeneratedModule_vulkan() {
        ModuleLibrary lib;
        lib.addModule(this);
        lib.addBuiltInModule();
        addGenerated(lib);
        addVulkanCustom(*this, lib);

        addAnnotation(make_smart<VkHandleAnnotation<
            DebugMsgContext_DasHandle> >(
                "DebugMsgContext_DasHandle", "DebugMsgContext_DasHandle"));

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
        addExtern<DAS_BIND_FUN(vk_create_debug_utils_messenger_ex)>(
            *this, lib, "vkCreateDebugUtilsMessengerEx",
            SideEffects::worstDefault, "vkCreateDebugUtilsMessengerEx");
        addExtern<DAS_BIND_FUN(vk_destroy_debug_utils_messenger_ex)>(
            *this, lib, "vkDestroyDebugUtilsMessengerEx",
            SideEffects::worstDefault, "vkDestroyDebugUtilsMessengerEx");
    }
};

REGISTER_MODULE(Module_vulkan);
