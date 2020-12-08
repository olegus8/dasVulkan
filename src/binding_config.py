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
        dtor            = 'vkDestroyDevice')
    g.add_gen_handle(
        handle          = 'VkCommandPool',
        ctor            = 'vkCreateCommandPool',
        dtor            = 'vkDestroyCommandPool')
    g.add_gen_handle(
        handle          = 'VkDescriptorSetLayout',
        ctor            = 'vkCreateDescriptorSetLayout',
        dtor            = 'vkDestroyDescriptorSetLayout')
    g.add_gen_handle(
        handle          = 'VkFence',
        ctor            = 'vkCreateFence',
        dtor            = 'vkDestroyFence')
    g.add_gen_handle(
        handle          = 'VkFramebuffer',
        ctor            = 'vkCreateFramebuffer',
        dtor            = 'vkDestroyFramebuffer')
    g.add_gen_handle(
        handle          = 'VkImage',
        ctor            = 'vkCreateImage',
        dtor            = 'vkDestroyImage')
    g.add_gen_handle(handle = 'VkImageView',
        ).declare_ctor(GenHandleCtor(name = 'vkCreateImageView')
        ).declare_dtor(GenHandleDtor(name = 'vkDestroyImageView'))
    g.add_gen_handle(handle = 'VkInstance',
        ).declare_ctor(GenHandleCtor(name = 'vkCreateInstance')
        ).declare_dtor(GenHandleDtor(name = 'vkDestroyInstance'))
    g.add_gen_handle(handle = 'VkPhysicalDevice')
    g.add_gen_handle(handle = 'VkQueue')
    g.add_gen_handle(handle = 'VkPipeline'
        ).declare_ctor(GenHandleCtor(name = 'vkCreateGraphicsPipelines',
            ).declare_array(count = 'createInfoCount', items = 'pCreateInfos'
            ).declare_array(count = 'createInfoCount', items = 'pPipelines')
        ).declare_ctor(GenHandleCtor(name = 'vkCreateComputePipelines',
            ).declare_array(count = 'createInfoCount', items = 'pCreateInfos'
            ).declare_array(count = 'createInfoCount', items = 'pPipelines')
        ).declare_dtor(GenHandleDtor(name = 'vkDestroyPipeline'))

    g.add_gen_handle(
        handle          = 'VkPipelineLayout',
        ctor            = 'vkCreatePipelineLayout',
        dtor            = 'vkDestroyPipelineLayout')
    g.add_gen_handle(
        handle          = 'VkRenderPass',
        ctor            = 'vkCreateRenderPass',
        dtor            = 'vkDestroyRenderPass')
    g.add_gen_handle(
        handle          = 'VkSampler',
        ctor            = 'vkCreateSampler',
        dtor            = 'vkDestroySampler')
    g.add_gen_handle(
        handle          = 'VkSemaphore',
        ctor            = 'vkCreateSemaphore',
        dtor            = 'vkDestroySemaphore')
    g.add_gen_handle(
        handle          = 'VkShaderModule',
        ctor            = 'vkCreateShaderModule',
        dtor            = 'vkDestroyShaderModule')
    g.add_gen_handle(
        handle          = 'VkSwapchainKHR',
        ctor            = 'vkCreateSwapchainKHR',
        dtor            = 'vkDestroySwapchainKHR')

    #
    # Structs
    #

    g.add_gen_struct(struct = 'VkApplicationInfo', b2v = True)
    g.add_gen_struct(struct = 'VkAttachmentDescription', b2v = True)
    g.add_gen_struct(struct = 'VkAttachmentReference', b2v = True)
    g.add_gen_struct(struct = 'VkCommandPoolCreateInfo', b2v = True)
    g.add_gen_struct(struct = 'VkComponentMapping', b2v = True)
    g.add_gen_struct(struct = 'VkDescriptorSetLayoutBinding', b2v = True,
        ).declare_array(items = 'pImmutableSamplers')
    g.add_gen_struct(struct = 'VkDescriptorSetLayoutCreateInfo', b2v = True,
        ).declare_array(count = 'bindingCount', items = 'pBindings')
    g.add_gen_struct(struct = 'VkDeviceCreateInfo', b2v = True,
        ).declare_array(count = 'queueCreateInfoCount', items = 'pQueueCreateInfos',
        ).declare_array(count = 'enabledLayerCount', items = 'ppEnabledLayerNames',
        ).declare_array(count = 'enabledExtensionCount', items = 'ppEnabledExtensionNames')
    g.add_gen_struct(struct = 'VkDeviceQueueCreateInfo', b2v = True
        ).declare_array(count = 'queueCount', items = 'pQueuePriorities')
    g.add_gen_struct(struct = 'VkExtensionProperties', v2b = True)
    g.add_gen_struct(struct = 'VkExtent2D', v2b = True, b2v = True)
    g.add_gen_struct(struct = 'VkExtent3D', v2b = True, b2v = True)
    g.add_gen_struct(struct = 'VkFenceCreateInfo', b2v = True)
    g.add_gen_struct(struct = 'VkFramebufferCreateInfo', b2v = True
        ).declare_array(count = 'attachmentCount', items = 'pAttachments')
    g.add_gen_struct(struct = 'VkImageCreateInfo', b2v = True,
        ).declare_array(count = 'queueFamilyIndexCount', items = 'pQueueFamilyIndices')
    g.add_gen_struct(struct = 'VkImageSubresourceRange', b2v = True)
    g.add_gen_struct(struct = 'VkImageViewCreateInfo', b2v = True)
    g.add_gen_struct(struct = 'VkInstanceCreateInfo', b2v = True
        ).declare_array(count = 'enabledLayerCount', items = 'ppEnabledLayerNames',
        ).declare_array(count = 'enabledExtensionCount', items = 'ppEnabledExtensionNames')
    g.add_gen_struct(struct = 'VkOffset2D', b2v = True)
    g.add_gen_struct(struct = 'VkPhysicalDeviceLimits', v2b = True)
    g.add_gen_struct(struct = 'VkPhysicalDeviceProperties', v2b = True)
    g.add_gen_struct(struct = 'VkPhysicalDeviceFeatures', b2v = True)
    g.add_gen_struct(struct = 'VkPhysicalDeviceSparseProperties', v2b = True)
    g.add_gen_struct(struct = 'VkPipelineLayoutCreateInfo', b2v = True,
        ).declare_array(count = 'setLayoutCount', items = 'pSetLayouts',
        ).declare_array(count = 'pushConstantRangeCount', items = 'pPushConstantRanges')
    g.add_gen_struct(struct = 'VkPipelineViewportStateCreateInfo', b2v = True,
        ).declare_array(count = 'viewportCount', items = 'pViewports',
        ).declare_array(count = 'scissorCount', items = 'pScissors')
    g.add_gen_struct(struct = 'VkPushConstantRange', b2v = True)
    g.add_gen_struct(struct = 'VkQueueFamilyProperties', v2b = True)
    g.add_gen_struct(struct = 'VkRect2D', b2v = True)
    g.add_gen_struct(struct = 'VkRenderPassCreateInfo', b2v = True
        ).declare_array(count = 'attachmentCount', items = 'pAttachments',
        ).declare_array(count = 'subpassCount', items = 'pSubpasses',
        ).declare_array(count = 'dependencyCount', items = 'pDependencies')
    g.add_gen_struct(struct = 'VkSamplerCreateInfo', b2v = True)
    g.add_gen_struct(struct = 'VkSemaphoreCreateInfo', b2v = True)
    g.add_gen_struct(struct = 'VkShaderModuleCreateInfo', b2v = True,
        ).declare_array(count = 'codeSize', items = 'pCode', force_item_type = 'uint8')
    g.add_gen_struct(struct = 'VkSubpassDependency', b2v = True)
    g.add_gen_struct(struct = 'VkSubpassDescription', b2v = True
        ).declare_array(count = 'inputAttachmentCount', items = 'pInputAttachments',
        ).declare_array(count = 'colorAttachmentCount', items = 'pColorAttachments'
        ).declare_array(count = 'colorAttachmentCount', items = 'pResolveAttachments',
        ).declare_can_be_null(name = 'pResolveAttachments',
        ).declare_array(count = 'preserveAttachmentCount', items = 'pPreserveAttachments')
    g.add_gen_struct(struct = 'VkSurfaceCapabilitiesKHR', v2b = True)
    g.add_gen_struct(struct = 'VkSurfaceFormatKHR', v2b = True, b2v = True)
    g.add_gen_struct(struct = 'VkSwapchainCreateInfoKHR', b2v = True,
        ).declare_array(count = 'queueFamilyIndexCount', items = 'pQueueFamilyIndices')
    g.add_gen_struct(struct = 'VkViewport', b2v = True)

    #
    # Functions
    #

    g.add_gen_func(func = 'vkEnumerateDeviceExtensionProperties',
        ).declare_array(count = 'pPropertyCount', items = 'pProperties',
        ).declare_output(name = 'pProperties')
    g.add_gen_func(func = 'vkEnumeratePhysicalDevices',
        ).declare_array(count = 'pPhysicalDeviceCount', items = 'pPhysicalDevices'.
        ).declare_output(name = 'pPhysicalDevices')
    g.add_gen_func(func = 'vkGetDeviceQueue'
        ).declare_output(name = 'pQueue')
    g.add_gen_func(func = 'vkGetPhysicalDeviceProperties',
        ).declare_output(name = 'pProperties')
    g.add_gen_func(func = 'vkGetPhysicalDeviceSurfaceCapabilitiesKHR',
        ).declare_output(name = 'pSurfaceCapabilities')
    g.add_gen_func(func = 'vkGetPhysicalDeviceSurfaceSupportKHR',
        ).declare_output(name = 'pSupported')
    g.add_gen_func(func = 'vkGetPhysicalDeviceQueueFamilyProperties',
        ).declare_array(count = 'pQueueFamilyPropertyCount', items = 'pQueueFamilyProperties',
        ).declare_output(name = 'pQueueFamilyProperties')
    g.add_gen_func(func = 'vkGetPhysicalDeviceSurfaceFormatsKHR',
        ).declare_array(count = 'pSurfaceFormatCount', items = 'pSurfaceFormats',
        ).declare_output(name = 'pSurfaceFormats')
    g.add_gen_func(func = 'vkGetPhysicalDeviceSurfacePresentModesKHR',
        ).declare_array(count = 'pPresentModeCount', items = 'pPresentModes',
        ).declare_output(output = 'pPresentModes')
    g.add_gen_func(func = 'vkGetSwapchainImagesKHR',
        ).declare_array(count = 'pSwapchainImageCount', items = 'pSwapchainImages',
        ).declare_output(name = 'pSwapchainImages')
