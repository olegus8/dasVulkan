from das_binder.config import ConfigBase


class Config(ConfigBase):

    @property
    def das_module_name(self):
        return 'vulkan'

    @property
    def c_header_include(self):
        return 'vulkan/vulkan.h'

    @property
    def save_ast(self):
        return True

    def configure_opaque_struct(self, struct):
        if struct.name.endswith('_T'):
            struct.set_dummy_type(struct.name[:-2])

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
        return
        if func.name not in [
            'vkCreateInstance',
        ]:
            func.ignore()
