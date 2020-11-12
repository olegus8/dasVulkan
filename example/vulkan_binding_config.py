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
        #FIXME: make it work for all fields
        if field.name.startswith('pfn') and field.struct.name in [
            'VkAllocationCallbacks',
        ]:
            field.ignore()
