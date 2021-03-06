// generated by dasVulkan for Vulkan 1.2.162

static VkInstance g_vk_linked_instance = VK_NULL_HANDLE;

static VkInstance vk_get_linked_instance() {
    return g_vk_linked_instance;
}

static PFN_vkCreateDebugUtilsMessengerEXT
    g_vk_linked_vkCreateDebugUtilsMessengerEXT = nullptr;
VKAPI_ATTR VkResult VKAPI_CALL vkCreateDebugUtilsMessengerEXT(
    struct VkInstance_T * instance,
    const VkDebugUtilsMessengerCreateInfoEXT * pCreateInfo,
    const VkAllocationCallbacks * pAllocator,
    VkDebugUtilsMessengerEXT * pMessenger
) {
    if ( g_vk_linked_vkCreateDebugUtilsMessengerEXT == nullptr ) {
        DAS_ASSERTF(0, "vkCreateDebugUtilsMessengerEXT not found");
        DAS_FATAL_ERROR
    }
    return (*g_vk_linked_vkCreateDebugUtilsMessengerEXT)(
        instance,
        pCreateInfo,
        pAllocator,
        pMessenger
    );
}

static PFN_vkDestroyDebugUtilsMessengerEXT
    g_vk_linked_vkDestroyDebugUtilsMessengerEXT = nullptr;
VKAPI_ATTR void VKAPI_CALL vkDestroyDebugUtilsMessengerEXT(
    struct VkInstance_T * instance,
    struct VkDebugUtilsMessengerEXT_T * messenger,
    const VkAllocationCallbacks * pAllocator
) {
    if ( g_vk_linked_vkDestroyDebugUtilsMessengerEXT == nullptr ) {
        DAS_ASSERTF(0, "vkDestroyDebugUtilsMessengerEXT not found");
        DAS_FATAL_ERROR
    }
    return (*g_vk_linked_vkDestroyDebugUtilsMessengerEXT)(
        instance,
        messenger,
        pAllocator
    );
}

static void vk_link_instance(VkInstance instance) {
    g_vk_linked_instance = instance;
    g_vk_linked_vkCreateDebugUtilsMessengerEXT =
        (PFN_vkCreateDebugUtilsMessengerEXT) vkGetInstanceProcAddr(
            instance, "vkCreateDebugUtilsMessengerEXT");
    g_vk_linked_vkDestroyDebugUtilsMessengerEXT =
        (PFN_vkDestroyDebugUtilsMessengerEXT) vkGetInstanceProcAddr(
            instance, "vkDestroyDebugUtilsMessengerEXT");
}

static void vk_unlink_instance() {
    g_vk_linked_instance = VK_NULL_HANDLE;
    g_vk_linked_vkCreateDebugUtilsMessengerEXT = nullptr;
    g_vk_linked_vkDestroyDebugUtilsMessengerEXT = nullptr;
}

void addVulkanBoostGenerated(Module & module, ModuleLibrary & lib) {
    addExtern<DAS_BIND_FUN(vk_link_instance)>(
        module, lib, "vk_link_instance",
        SideEffects::worstDefault, "vk_link_instance");
    addExtern<DAS_BIND_FUN(vk_unlink_instance)>(
        module, lib, "vk_unlink_instance",
        SideEffects::worstDefault, "vk_unlink_instance");
    addExtern<DAS_BIND_FUN(vk_get_linked_instance)>(
        module, lib, "vk_get_linked_instance",
        SideEffects::worstDefault, "vk_get_linked_instance");
}
