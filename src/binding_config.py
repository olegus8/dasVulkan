from das_binder.config import ConfigBase


class Config(ConfigBase):

    @property
    def das_module_name(self):
        return 'vulkan'

    @property
    def c_headers_to_extract_macro_consts_from(self):
        return ['GLFW/glfw3.h', 'vulkan/vulkan_core.h']

    def configure_macro_const(self, macro_const):
        if '"' in macro_const.value:
            macro_const.ignore()
            return
        for prefix in [
            #'VK_API_VERSION',
        ]:
            if macro_const.name.startswith(prefix):
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
        #TODO: capturing returned value into variable crashes when
        #   side effects are set to not none.
        #   Remove this line after fixed.
        func.set_side_effects('none')

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
