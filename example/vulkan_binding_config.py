from das_binder.config import ConfigBase


class Config(ConfigBase):

    @property
    def das_module_name(self):
        return 'vulkan'

    @property
    def c_headers_to_extract_macro_consts_from(self):
        return ['GLFW/glfw3.h']

    @property
    def save_ast(self):
        return True

    def configure_macro_const(self, macro_const):
        if not macro_const.name.startswith('GLFW_'):
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
