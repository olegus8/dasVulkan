from das.binder.config import ConfigBase


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
            #TODO: hints from Boris:
            # ast_typedecl.h -- add size_t and char there
            # options log_infer_passes = true
            # options log = true
            # ast_lint.cpp -- for options

            '*',
            'unsigned long',

            #TODO: bind unions as structs
            # the following are unions:
            #'VkPerformanceValueDataINTEL',
            #'VkPipelineExecutableStatisticValueKHR',
        ]:
            if kw in field.type:
                field.ignore()
