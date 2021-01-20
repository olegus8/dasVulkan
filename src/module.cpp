#include "module.h"

MAKE_TYPE_FACTORY(PFN_vkDebugUtilsMessengerCallbackEXT, PFN_vkDebugUtilsMessengerCallbackEXT);

#include "module_generated.inc"

void addVulkanCustomBeforeGenerated(Module &, ModuleLibrary &);
void addVulkanCustomAfterGenerated(Module &, ModuleLibrary &);


class Module_vulkan : public GeneratedModule_vulkan {
public:
    Module_vulkan() : GeneratedModule_vulkan() {
        ModuleLibrary lib;
        lib.addModule(this);
        lib.addBuiltInModule();

        addVulkanCustomBeforeGenerated(*this, lib);
        addGenerated(lib);
        addVulkanCustomAfterGenerated(*this, lib);
    }
};

REGISTER_MODULE(Module_vulkan);
