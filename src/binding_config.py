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
        name          = 'VkDevice',
        ctor            = 'vkCreateDevice',
        dtor            = 'vkDestroyDevice')
    g.add_gen_handle(
        name          = 'VkCommandPool',
        ctor            = 'vkCreateCommandPool',
        dtor            = 'vkDestroyCommandPool')
    g.add_gen_handle(name = 'VkDescriptorSetLayout',
        ).declare_ctor(GenHandleCtor(name = 'vkCreateDescriptorSetLayout')
        ).declare_dtor(GenHandleDtor(name = 'vkDestroyDescriptorSetLayout'))
    g.add_gen_handle(name = 'VkFence',
        ).declare_ctor(GenHandleCtor(name = 'vkCreateFence')
        ).declare_dtor(GenHandleDtor(name = 'vkDestroyFence'))
    g.add_gen_handle(name = 'VkFramebuffer',
        ).declare_ctor(GenHandleCtor(name = 'vkCreateFramebuffer')
        ).declare_dtor(GenHandleDtor(name = 'vkDestroyFramebuffer'))
    g.add_gen_handle(name = 'VkImage',
        ).declare_ctor(GenHandleCtor(name = 'vkCreateImage')
        ).declare_dtor(GenHandleDtor(name = 'vkDestroyImage'))
    g.add_gen_handle(name = 'VkImageView',
        ).declare_ctor(GenHandleCtor(name = 'vkCreateImageView')
        ).declare_dtor(GenHandleDtor(name = 'vkDestroyImageView'))
    g.add_gen_handle(name = 'VkInstance',
        ).declare_ctor(GenHandleCtor(name = 'vkCreateInstance')
        ).declare_dtor(GenHandleDtor(name = 'vkDestroyInstance'))
    g.add_gen_handle(name = 'VkPhysicalDevice')
    g.add_gen_handle(name = 'VkQueue')
    g.add_gen_handle(name = 'VkPipeline'
        ).declare_ctor(GenHandleCtor(name = 'vkCreateGraphicsPipelines',
            ).declare_array(count = 'createInfoCount', items = 'pCreateInfos'
            ).declare_array(count = 'createInfoCount', items = 'pPipelines')
        ).declare_ctor(GenHandleCtor(name = 'vkCreateComputePipelines',
            ).declare_array(count = 'createInfoCount', items = 'pCreateInfos'
            ).declare_array(count = 'createInfoCount', items = 'pPipelines')
        ).declare_dtor(GenHandleDtor(name = 'vkDestroyPipeline'))

    g.add_gen_handle(
        name          = 'VkPipelineLayout',
        ctor            = 'vkCreatePipelineLayout',
        dtor            = 'vkDestroyPipelineLayout')
    g.add_gen_handle(
        name          = 'VkRenderPass',
        ctor            = 'vkCreateRenderPass',
        dtor            = 'vkDestroyRenderPass')
    g.add_gen_handle(
        name          = 'VkSampler',
        ctor            = 'vkCreateSampler',
        dtor            = 'vkDestroySampler')
    g.add_gen_handle(
        name          = 'VkSemaphore',
        ctor            = 'vkCreateSemaphore',
        dtor            = 'vkDestroySemaphore')
    g.add_gen_handle(
        name          = 'VkShaderModule',
        ctor            = 'vkCreateShaderModule',
        dtor            = 'vkDestroyShaderModule')
    g.add_gen_handle(
        name          = 'VkSwapchainKHR',
        ctor            = 'vkCreateSwapchainKHR',
        dtor            = 'vkDestroySwapchainKHR')

    #
    # Structs
    #

    g.add_gen_struct(name = 'VkApplicationInfo', b2v = True)
    g.add_gen_struct(name = 'VkAttachmentDescription', b2v = True)
    g.add_gen_struct(name = 'VkAttachmentReference', b2v = True)
    g.add_gen_struct(name = 'VkCommandPoolCreateInfo', b2v = True)
    g.add_gen_struct(name = 'VkComponentMapping', b2v = True)
    g.add_gen_struct(name = 'VkDescriptorSetLayoutBinding', b2v = True,
        ).declare_array(items = 'pImmutableSamplers')
    g.add_gen_struct(name = 'VkDescriptorSetLayoutCreateInfo', b2v = True,
        ).declare_array(count = 'bindingCount', items = 'pBindings')
    g.add_gen_struct(name = 'VkDeviceCreateInfo', b2v = True,
        ).declare_array(count = 'queueCreateInfoCount', items = 'pQueueCreateInfos',
        ).declare_array(count = 'enabledLayerCount', items = 'ppEnabledLayerNames',
        ).declare_array(count = 'enabledExtensionCount', items = 'ppEnabledExtensionNames')
    g.add_gen_struct(name = 'VkDeviceQueueCreateInfo', b2v = True
        ).declare_array(count = 'queueCount', items = 'pQueuePriorities')
    g.add_gen_struct(name = 'VkExtensionProperties', v2b = True)
    g.add_gen_struct(name = 'VkExtent2D', v2b = True, b2v = True)
    g.add_gen_struct(name = 'VkExtent3D', v2b = True, b2v = True)
    g.add_gen_struct(name = 'VkFenceCreateInfo', b2v = True)
    g.add_gen_struct(name = 'VkFramebufferCreateInfo', b2v = True
        ).declare_array(count = 'attachmentCount', items = 'pAttachments')
    g.add_gen_struct(name = 'VkImageCreateInfo', b2v = True,
        ).declare_array(count = 'queueFamilyIndexCount', items = 'pQueueFamilyIndices')
    g.add_gen_struct(name = 'VkImageSubresourceRange', b2v = True)
    g.add_gen_struct(name = 'VkImageViewCreateInfo', b2v = True)
    g.add_gen_struct(name = 'VkInstanceCreateInfo', b2v = True
        ).declare_array(count = 'enabledLayerCount', items = 'ppEnabledLayerNames',
        ).declare_array(count = 'enabledExtensionCount', items = 'ppEnabledExtensionNames')
    g.add_gen_struct(name = 'VkOffset2D', b2v = True)
    g.add_gen_struct(name = 'VkPhysicalDeviceLimits', v2b = True)
    g.add_gen_struct(name = 'VkPhysicalDeviceProperties', v2b = True)
    g.add_gen_struct(name = 'VkPhysicalDeviceFeatures', b2v = True)
    g.add_gen_struct(name = 'VkPhysicalDeviceSparseProperties', v2b = True)
    g.add_gen_struct(name = 'VkPipelineLayoutCreateInfo', b2v = True,
        ).declare_array(count = 'setLayoutCount', items = 'pSetLayouts',
        ).declare_array(count = 'pushConstantRangeCount', items = 'pPushConstantRanges')
    g.add_gen_struct(name = 'VkPipelineViewportStateCreateInfo', b2v = True,
        ).declare_array(count = 'viewportCount', items = 'pViewports',
        ).declare_array(count = 'scissorCount', items = 'pScissors')
    g.add_gen_struct(name = 'VkPushConstantRange', b2v = True)
    g.add_gen_struct(name = 'VkQueueFamilyProperties', v2b = True)
    g.add_gen_struct(name = 'VkRect2D', b2v = True)
    g.add_gen_struct(name = 'VkRenderPassCreateInfo', b2v = True
        ).declare_array(count = 'attachmentCount', items = 'pAttachments',
        ).declare_array(count = 'subpassCount', items = 'pSubpasses',
        ).declare_array(count = 'dependencyCount', items = 'pDependencies')
    g.add_gen_struct(name = 'VkSamplerCreateInfo', b2v = True)
    g.add_gen_struct(name = 'VkSemaphoreCreateInfo', b2v = True)
    g.add_gen_struct(name = 'VkShaderModuleCreateInfo', b2v = True,
        ).declare_array(count = 'codeSize', items = 'pCode', force_item_type = 'uint8')
    g.add_gen_struct(name = 'VkSubpassDependency', b2v = True)
    g.add_gen_struct(name = 'VkSubpassDescription', b2v = True
        ).declare_array(count = 'inputAttachmentCount', items = 'pInputAttachments',
        ).declare_array(count = 'colorAttachmentCount', items = 'pColorAttachments'
        ).declare_array(count = 'colorAttachmentCount', items = 'pResolveAttachments',
        ).declare_can_be_null(name = 'pResolveAttachments',
        ).declare_array(count = 'preserveAttachmentCount', items = 'pPreserveAttachments')
    g.add_gen_struct(name = 'VkSurfaceCapabilitiesKHR', v2b = True)
    g.add_gen_struct(name = 'VkSurfaceFormatKHR', v2b = True, b2v = True)
    g.add_gen_struct(name = 'VkSwapchainCreateInfoKHR', b2v = True,
        ).declare_array(count = 'queueFamilyIndexCount', items = 'pQueueFamilyIndices')
    g.add_gen_struct(name = 'VkViewport', b2v = True)

    #
    # Functions
    #

    g.add_gen_func(name = 'vkEnumerateDeviceExtensionProperties',
        ).declare_array(count = 'pPropertyCount', items = 'pProperties',
        ).declare_output(name = 'pProperties')
    g.add_gen_func(name = 'vkEnumeratePhysicalDevices',
        ).declare_array(count = 'pPhysicalDeviceCount', items = 'pPhysicalDevices'.
        ).declare_output(name = 'pPhysicalDevices')
    g.add_gen_func(name = 'vkGetDeviceQueue'
        ).declare_output(name = 'pQueue')
    g.add_gen_func(name = 'vkGetPhysicalDeviceProperties',
        ).declare_output(name = 'pProperties')
    g.add_gen_func(name = 'vkGetPhysicalDeviceSurfaceCapabilitiesKHR',
        ).declare_output(name = 'pSurfaceCapabilities')
    g.add_gen_func(name = 'vkGetPhysicalDeviceSurfaceSupportKHR',
        ).declare_output(name = 'pSupported')
    g.add_gen_func(name = 'vkGetPhysicalDeviceQueueFamilyProperties',
        ).declare_array(count = 'pQueueFamilyPropertyCount', items = 'pQueueFamilyProperties',
        ).declare_output(name = 'pQueueFamilyProperties')
    g.add_gen_func(name = 'vkGetPhysicalDeviceSurfaceFormatsKHR',
        ).declare_array(count = 'pSurfaceFormatCount', items = 'pSurfaceFormats',
        ).declare_output(name = 'pSurfaceFormats')
    g.add_gen_func(name = 'vkGetPhysicalDeviceSurfacePresentModesKHR',
        ).declare_array(count = 'pPresentModeCount', items = 'pPresentModes',
        ).declare_output(output = 'pPresentModes')
    g.add_gen_func(name = 'vkGetSwapchainImagesKHR',
        ).declare_array(count = 'pSwapchainImageCount', items = 'pSwapchainImages',
        ).declare_output(name = 'pSwapchainImages')
