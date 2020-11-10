from das_binder.config import ConfigBase


class Config(ConfigBase):

    @property
    def das_module_name(self):
        return 'vulkan'

    @property
    def c_header_include(self):
        return 'vulkan/vulkan.h'

    def configure_struct_field(self, field):
        #FIXME: make it work for all fields
        if (field.is_array
            or field.name.startswith('pfn')

            #TODO: generate accessors for these
            or field.is_bit_field
        ):
            field.ignore()
        for kw in [
            #TODO: bind _T * handles as DummyType(..._T)
            '*',

            #TODO: add size_t and char to ast_typedecl.h
            'unsigned long',
        ]:
            if kw in field.type:
                field.ignore()
