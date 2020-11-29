from das_shared.object_base import LoggingObject
from das_shared.assertions import assert_starts_with


class BoostGenerator(LoggingObject):

    def __init__(self, context):
        self.__context = context
        self.__handles = []

        self.enums = dict((x.name, x)
            for x in self.__context.main_c_header.enums)
        self.structs = dict((x.name, x)
            for x in self.__context.main_c_header.structs)
        self.opaque_structs = dict((x.name, x)
            for x in self.__context.main_c_header.opaque_structs)
        self.functions = dict((x.name, x)
            for x in self.__context.main_c_header.functions)

        self.__add_vk_handles()

    def __add_vk_handles(self):
        self.__add_vk_handle(name='VkPhysicalDevice',
            fn_create='vkEnumeratePhysicalDevices',
            p_count='pPhysicalDeviceCount',
            p_handles='pPhysicalDevices')

    def __add_vk_handle(self, **kwargs):
        handle = VkHandle(generator=self, **kwargs)
        self.__handles.append(handle)
        return handle

    def write(self):
        self.__context.write_to_file(
            fpath='../daslib/internal/generated.das',
            content='\n'.join(self.__generate() + ['']))

    def __generate(self):
        return [
            '// generated by dasVulkan',
            '',
            'options indenting = 4',
            'options no_aot = true',
        ] + [
            line for handle in self.__handles for line in handle.generate()
        ]


class VkHandle(object):

    def __init__(self, generator, name, fn_create,
        fn_destroy=None, params=None, p_count=None, p_handles=None
    ):
        self.__generator = generator
        self.__name = name
        self.__fn_create = fn_create
        self.__fn_destroy = fn_destroy
        self.__params = params or []
        self.__p_count = p_count
        self.__p_handles = p_handles

    @property
    def __is_batched(self):
        return self.__p_count is not None

    @property
    def __boost_type(self):
        assert_starts_with(self.__name, 'Vk')
        return self.__name[2:]

    @property
    def __boost_batch_type(self):
        return self.__boost_type + 'Batch'

    @property
    def __boost_attr(self):
        return boost_camel_to_lower(self.__boost_type)

    @property
    def __boost_batch_attr(self):
        return self.__boost_attr + '_batch'

    @property
    def __das_handle_type(self):
        return self.__name

    def generate(self):
        lines = []
        lines += [
            '',
           f'struct {self.__boost_type}',
           f'    {self.__boost_attr} : {self.__das_handle_type}',
        ]
        if self.__is_batched:
            lines += [
                '',
               f'struct {self.__boost_batch_type}',
               f'    {self.__boost_batch_attr} : '
                        f'array<{self.__das_handle_type}>',
                '',
               f'def split(batch : {self.__boost_batch_type}) '
                    f': array<self.__boost_type>',
               f'    return <- [{{for h in batch.{self.__boost_batch_attr} ;',
               f'        [[{self.__boost_type} {self.__boost_attr}=h]]}}]',
            ]

        return lines


def boost_camel_to_lower(camel):
    result = ''
    for c in camel:
        if c.isupper() and result and result[-1] != '_':
            result += '_'
        result += c.lower()
    return result
