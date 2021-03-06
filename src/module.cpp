#include "dasVulkan/module.h"

#define GLFW_INCLUDE_VULKAN
#define GLFW_INCLUDE_NONE
#include <GLFW/glfw3.h>

using namespace das;
using namespace std;

#include "../../dasGlfw/src/module_glfw_include.h"

IMPLEMENT_EXTERNAL_TYPE_FACTORY(PFN_vkDebugUtilsMessengerCallbackEXT, PFN_vkDebugUtilsMessengerCallbackEXT);

#include "module_generated.cpp.inc"
#include "module_boost_generated.inc"

void addVulkanCustomBeforeGenerated(Module &, ModuleLibrary &);
void addVulkanCustomAfterGenerated(Module &, ModuleLibrary &);


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

class Module_vulkan : public GeneratedModule_vulkan {
public:
    Module_vulkan() : GeneratedModule_vulkan() {
    }

    bool initialized = false;
    virtual bool initDependencies() override {
        if ( initialized ) return true;

        // GLFW
        auto mod_glfw = Module::require("glfw");
        if ( !mod_glfw ) return false;
        if ( !mod_glfw->initDependencies() ) return false;

        initialized = true;

        ModuleLibrary lib;
        lib.addModule(this);
        lib.addBuiltInModule();
        lib.addModule(mod_glfw);

        addAnnotation(make_smart<VkHandleAnnotation<
            PFN_vkDebugUtilsMessengerCallbackEXT> >(
              "PFN_vkDebugUtilsMessengerCallbackEXT",
              "PFN_vkDebugUtilsMessengerCallbackEXT"
        ));

        addVulkanCustomBeforeGenerated(*this, lib);
        addGenerated(lib);
        addVulkanBoostGenerated(*this, lib);
        addVulkanCustomAfterGenerated(*this, lib);

        addExtern<DAS_BIND_FUN(glfwCreateWindowSurface)>(*this, lib,
            "glfwCreateWindowSurface",
            SideEffects::worstDefault,
            "glfwCreateWindowSurface");

        addConstant(*this, "vk_debug_msg_callback",
            reinterpret_cast<uint64_t>(&vk_debug_msg_callback));

        return true;
    }
};

REGISTER_MODULE(Module_vulkan);
