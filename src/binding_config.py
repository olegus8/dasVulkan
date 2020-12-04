from das_binder.config import ConfigBase
from boost_generator import BoostGenerator


class Config(ConfigBase):

    @property
    def das_module_name(self):
        return 'vulkan'

    @property
    def save_ast(self):
        return True

    @property
    def c_headers_to_extract_macro_consts_from(self):
        return ['GLFW/glfw3.h', 'vulkan/vulkan_core.h']

    def custom_pass(self, context):
        generator = BoostGenerator(context)
        add_boost_content(generator)
        generator.write()

    def configure_macro_const(self, macro_const):
        if '"' in macro_const.value:
            macro_const.ignore()
            return
        for prefix in [
            'GLFW_',
            'VK_',
        ]:
            if macro_const.name.startswith(prefix):
                return
        macro_const.ignore()

    def configure_opaque_struct(self, struct):
        if struct.name.endswith('_T'):
            struct.set_das_type(struct.name[:-2])
        if struct.name.startswith('GLFW'):
            ptr_type = struct.name + '_DasHandle'
            struct.set_das_type(ptr_type)
            struct.define_ptr_type(ptr_type)

    def configure_struct_field(self, field):
        # These structs have function pointers, but we can probably
        # live without them for a time being.
        if field.name.startswith('pfn') and field.struct.name in [
            'VkAllocationCallbacks',
            'VkDebugReportCallbackCreateInfoEXT',
            'VkDebugUtilsMessengerCreateInfoEXT',
        ]:
            field.ignore()

    def configure_function(self, func):
        # whitelist
        if func.name in [
            'vkAcquireNextImageKHR',
            'vkCreateSwapchainKHR',
            'vkDestroySurfaceKHR',
            'vkDestroySwapchainKHR',
            'vkGetPhysicalDeviceSurfaceCapabilitiesKHR',
            'vkGetPhysicalDeviceSurfaceFormatsKHR',
            'vkGetPhysicalDeviceSurfacePresentModesKHR',
            'vkGetPhysicalDeviceSurfaceSupportKHR',
            'vkGetSwapchainImagesKHR',
            'vkQueuePresentKHR',
        ]:
            return

        #TODO: make these work
        if ('size_t' in func.type
        or  'PFN_' in func.type
        or  func.name.endswith('KHR')
        or  func.name.endswith('EXT')
        or  func.name.endswith('INTEL')
        or  func.name.endswith('AMD')
        or  func.name.endswith('GOOGLE')
        or  func.name.endswith('NV')
        or  func.name.endswith('NVX')
        ):
            func.ignore()

        if func.name.startswith('glfw'):
            for kw in [
                'ProcAddress',
                'Callback',
            ]:
                if kw in func.name:
                    func.ignore()


def add_boost_content(g):

    #
    # Handles
    #

    g.add_gen_handle(
        handle          = 'VkDevice',
        ctor            = 'vkCreateDevice',
        dtor            = 'vkDestroyDevice', #TODO: do vkDeviceWaitIlde too
        p_create_info   = 'pCreateInfo')
    g.add_gen_handle(
        handle          = 'VkInstance',
        ctor            = 'vkCreateInstance',
        dtor            = 'vkDestroyInstance',
        p_create_info   = 'pCreateInfo')
    g.add_gen_handle(
        handle          = 'VkPhysicalDevice',
        enumerator      = 'vkEnumeratePhysicalDevices',
        p_count         = 'pPhysicalDeviceCount',
        p_handles       = 'pPhysicalDevices')

    #
    # Structs
    #

    g.add_gen_struct(
        struct      = 'VkApplicationInfo',
        boost_to_vk = True)
    g.add_gen_struct(
        struct      = 'VkDeviceCreateInfo',
        boost_to_vk = True,
        ).declare_array(
            count = 'queueCreateInfoCount',
            items = 'pQueueCreateInfos',
        ).declare_array(
            count = 'enabledLayerCount',
            items = 'ppEnabledLayerNames',
        ).declare_array(
            count = 'enabledExtensionCount',
            items = 'ppEnabledExtensionNames')
    g.add_gen_struct(
        struct      = 'VkDeviceQueueCreateInfo',
        boost_to_vk = True
        ).declare_array(
            count = 'queueCount',
            items = 'pQueuePriorities')
    g.add_gen_struct(
        struct      = 'VkExtensionProperties',
        vk_to_boost = True)
    g.add_gen_struct(
        struct      = 'VkExtent3D',
        vk_to_boost = True,
        boost_to_vk = True)
    g.add_gen_struct(
        struct      = 'VkInstanceCreateInfo',
        boost_to_vk = True
        ).declare_array(
            count = 'enabledLayerCount',
            items = 'ppEnabledLayerNames',
        ).declare_array(
            count = 'enabledExtensionCount',
            items = 'ppEnabledExtensionNames')
    g.add_gen_struct(
        struct      = 'VkPhysicalDeviceLimits',
        vk_to_boost = True)
    g.add_gen_struct(
        struct      = 'VkPhysicalDeviceProperties',
        vk_to_boost = True)
    g.add_gen_struct(
        struct      = 'VkPhysicalDeviceFeatures',
        boost_to_vk = True)
    g.add_gen_struct(
        struct      = 'VkPhysicalDeviceSparseProperties',
        vk_to_boost = True)
    g.add_gen_struct(
        struct      = 'VkQueueFamilyProperties',
        vk_to_boost = True)
    g.add_gen_struct(
        struct      = 'VkSurfaceFormatKHR',
        vk_to_boost = True,
        boost_to_vk = True)

    #
    # Query functions
    #

    g.add_gen_query_array_func(
        func        = 'vkEnumerateDeviceExtensionProperties',
        p_count     = 'pPropertyCount',
        p_items     = 'pProperties')
    g.add_gen_query_func(
        func        = 'vkGetPhysicalDeviceProperties',
        p_output    = 'pProperties')
    g.add_gen_query_func(
        func        = 'vkGetPhysicalDeviceSurfaceSupportKHR',
        p_output    = 'pSupported')
    g.add_gen_query_array_func(
        func        = 'vkGetPhysicalDeviceQueueFamilyProperties',
        p_count     = 'pQueueFamilyPropertyCount',
        p_items     = 'pQueueFamilyProperties')
    g.add_gen_query_array_func(
        func        = 'vkGetPhysicalDeviceSurfaceFormatsKHR',
        p_count     = 'pSurfaceFormatCount',
        p_items     = 'pSurfaceFormats')
    g.add_gen_query_array_func(
        func        = 'vkGetPhysicalDeviceSurfacePresentModesKHR',
        p_count     = 'pPresentModeCount',
        p_items     = 'pPresentModes')
