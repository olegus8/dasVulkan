from das_shared.object_base import LoggingObject
from das_shared.assertions import assert_starts_with
import re


class VulkanBoostError(Exception):
    pass


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
        self.__add_vk_handle(
            handle      = 'VkPhysicalDevice',
            enumerator  = 'vkEnumeratePhysicalDevices',
            p_count     = 'pPhysicalDeviceCount',
            p_handles   = 'pPhysicalDevices')
        self.__add_vk_handle(
            handle      = 'VkInstance',
            ctor        = 'vkCreateInstance',
            dtor        = 'vkDestroyInstance')

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
            '',
            'require daslib/defer',
            'require daslib/safe_addr',
            '',
            'require vulkan',
            'require instance',
        ] + [
            line for handle in self.__handles for line in handle.generate()
        ]


class VkHandle(object):

    def __init__(self, generator, handle, enumerator=None,
        p_count=None, p_handles=None, ctor=None, dtor=None,
    ):
        self.__generator = generator
        self.__vk_type_name = handle
        self.__vk_enumerator_name = enumerator
        self.__vk_ctor_name = ctor
        self.__vk_dtor_name = dtor
        self.__p_count = p_count
        self.__p_handles = p_handles

    @property
    def __vk_enumerator(self):
        return self.__generator.functions[self.__vk_enumerator_name]

    @property
    def __vk_ctor(self):
        return self.__generator.functions[self.__vk_ctor_name]

    @property
    def __vk_dtor(self):
        return self.__generator.functions[self.__vk_dtor_name]

    @property
    def __is_batched(self):
        return self.__p_count is not None

    @property
    def __boost_type(self):
        assert_starts_with(self.__vk_type_name, 'Vk')
        return self.__vk_type_name[2:]

    @property
    def __boost_batch_type(self):
        return self.__boost_type + 'Batch'

    @property
    def __boost_attr(self):
        return boost_camel_to_lower(self.__boost_type)

    @property
    def __boost_batch_attr(self):
        return self.__boost_attr + '_batch'

    def generate(self):
        lines = []
        lines += [
            '',
            '//',
           f'// {self.__boost_type}',
            '//',
        ]
        lines += self.__generate_types()
        if self.__is_batched:
            lines += self.__generate_batched_types()
            lines += self.__generate_enumerators()
        return lines

    def __generate_types(self):
        return [
            '',
           f'struct {self.__boost_type}',
           f'    {self.__boost_attr} : {self.__vk_type_name}',
        ]

    def __generate_batched_types(self):
        return [
            '',
           f'struct {self.__boost_batch_type}',
           f'    {self.__boost_batch_attr} : '
                    f'array<{self.__vk_type_name}>',
            '',
           f'def split(batch : {self.__boost_batch_type}) '
                f': array<{self.__boost_type}>',
           f'    return <- [{{for h in batch.{self.__boost_batch_attr} ;',
           f'        [[{self.__boost_type} {self.__boost_attr}=h]]}}]',
        ]

    @property
    def __boost_enumerator(self):
        assert_starts_with(self.__vk_enumerator_name, 'vk')
        return boost_camel_to_lower(self.__vk_enumerator_name[2:])

    def __generate_enumerators(self):
        lines = []
        lines += [
            '',
           f'def {self.__boost_enumerator}(']
        for param in self.__vk_enumerator.params:
            if param.name in [self.__p_count, self.__p_handles]:
                continue
            boost_type = to_boost_type(param.type)
            lines += [
               f'    {param.das_name} : {boost_type.name};',
            ]
        lines += [
           f'    var result : VkResult? = [[VkResult?]]',
           f') : {self.__boost_batch_type}',
            '',
           f'    var count : uint',
           f'    var result_ = VkResult VK_SUCCESS',
            '',
           f'    result ?? result_ = {self.__vk_enumerator_name}('
        ]
        params = []
        for param in self.__vk_enumerator.params:
            if param.name == self.__p_count:
                params.append('safe_addr(count)')
            elif param.name == self.__p_handles:
                params.append('null')
            else:
                boost_type = to_boost_type(param.type)
                params.append(boost_type.to_vk_value(param.das_name))
        lines += [
            '        ' + ', '.join(params),
            '    )',
           f'    assert(result_ == VkResult VK_SUCCESS)',
            '',
           f'    var vk_handles : array<{self.__vk_type_name}>',
           f'    if result ?? result_ == VkResult VK_SUCCESS && count > 0u',
           f'        vk_handles |> resize(int(count))',
           f'        vk_handles |> lock() <| $(thandles)',
           f'            result ?? result_ = {self.__vk_enumerator_name}(',
        ]
        params = []
        for param in self.__vk_enumerator.params:
            if param.name == self.__p_count:
                params.append('safe_addr(count)')
            elif param.name == self.__p_handles:
                params.append('addr(thandles[0])')
            else:
                boost_type = to_boost_type(param.type)
                params.append(boost_type.to_vk_value(param.das_name))
        lines += [
            '                ' + ', '.join(params),
           f'            )',
           f'            assert(result_ == VkResult VK_SUCCESS)',
            '',
           f'    return <- [[{self.__boost_batch_type} '
                    f'{self.__boost_batch_attr} <- vk_handles]]',
            '',
           f'def {self.__boost_enumerator}_no_batch(',
        ]
        for param in self.__vk_enumerator.params:
            if param.name in [self.__p_count, self.__p_handles]:
                continue
            boost_type = to_boost_type(param.type)
            lines += [
               f'    {param.das_name} : {boost_type.name};',
            ]
        lines += [
           f'    var result : VkResult? = [[VkResult?]]',
           f'): array<{self.__boost_type}>',
        ]
        params = []
        for param in self.__vk_enumerator.params:
            if param.name in [self.__p_count, self.__p_handles]:
                continue
            params.append(param.das_name)
        params_text = ', '.join(params + ['result'])
        lines += [
           f'    var handles <- {self.__boost_enumerator}({params_text})',
            '    defer() <| ${ delete handles; }',
           f'    return <- handles |> split()',
        ]
        return lines


class BoostType(object):

    def __init__(self, name):
        self.name = name

    def to_vk_value(self, boost_value):
        return boost_value


class BoostVkHandleType(BoostType):

    def to_vk_value(self, boost_value):
        attr = boost_camel_to_lower(self.name)
        return f'{boost_value}.{attr}'


class BoostVkHandlePassthroughType(BoostType):
    pass


def boost_camel_to_lower(camel):
    result = ''
    for c in camel:
        if c.isupper() and result and result[-1] != '_':
            result += '_'
        result += c.lower()
    return result


def to_boost_type(c_type):
    m = re.match(r'struct Vk(.*)_T \*', c_type)
    if m:
        return BoostVkHandleType(name=m.group(1))
    raise VulkanBoostError(f'Unknown type: {c_type}')
