from das_shared.object_base import LoggingObject
from das_shared.assertions import assert_starts_with, assert_ends_with
import re


#TODO: add pAllocator support


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
            handle          = 'VkPhysicalDevice',
            enumerator      = 'vkEnumeratePhysicalDevices',
            p_count         = 'pPhysicalDeviceCount',
            p_handles       = 'pPhysicalDevices')
        self.__add_vk_handle(
            handle          = 'VkInstance',
            ctor            = 'vkCreateInstance',
            dtor            = 'vkDestroyInstance',
            p_create_info   = 'pCreateInfo')

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

    def __init__(self, generator, handle,
        enumerator=None, ctor=None, dtor=None,
        p_count=None, p_handles=None, p_create_info=None,
    ):
        self.__generator = generator
        self.__vk_type_name = handle
        self.__vk_enumerator_name = enumerator
        self.__vk_ctor_name = ctor
        self.__vk_dtor_name = dtor
        self.__p_count = p_count
        self.__p_handles = p_handles
        self.__p_create_info = p_create_info

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
    def __vk_enumerator_params(self):
        return self.__func_params_ex(self.__vk_enumerator)

    @property
    def __vk_ctor_params(self):
        return self.__func_params_ex(self.__vk_ctor)

    @property
    def __vk_dtor_params(self):
        return self.__func_params_ex(self.__vk_ctor)

    def __func_params_ex(self, vk_func):
        return map(ParamEx, vk_func.params)

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
        lines += self.__generate_type()
        if self.__is_batched:
            lines += self.__generate_batched_type()
            lines += self.__generate_enumerator_batched()
            lines += self.__generate_enumerator_not_batched()
        else:
            lines += self.__generate_ctor()
            lines += self.__generate_dtor()
        return lines

    def __generate_type(self):
        return [
            '',
           f'struct {self.__boost_type}',
           f'    {self.__boost_attr} : {self.__vk_type_name}',
        ]

    def __generate_batched_type(self):
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
        return to_boost_func_name(self.__vk_enumerator_name)

    @property
    def __boost_ctor(self):
        return to_boost_func_name(self.__vk_ctor_name)

    def __generate_enumerator_batched(self):
        lines = []
        lines += [
            '',
           f'def {self.__boost_enumerator}(']
        for param in self.__vk_enumerator_params:
            if param.vk.name in [self.__p_count, self.__p_handles]:
                continue
            lines += [
               f'    {param.boost.name} : {param.boost.type};',
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
        for param in self.__vk_enumerator_params:
            if param.vk.name == self.__p_count:
                params.append('safe_addr(count)')
            elif param.vk.name == self.__p_handles:
                params.append('null')
            else:
                params.append(param.boost.vk_value)
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
        for param in self.__vk_enumerator_params:
            if param.vk.name == self.__p_count:
                params.append('safe_addr(count)')
            elif param.vk.name == self.__p_handles:
                params.append('addr(thandles[0])')
            else:
                params.append(param.boost.vk_value)
        lines += [
            '                ' + ', '.join(params),
           f'            )',
           f'            assert(result_ == VkResult VK_SUCCESS)',
            '',
           f'    return <- [[{self.__boost_batch_type} '
                    f'{self.__boost_batch_attr} <- vk_handles]]',
        ]
        return lines

    def __generate_enumerator_not_batched(self):
        lines = []
        lines += [
            '',
           f'def {self.__boost_enumerator}_no_batch(',
        ]
        for param in self.__vk_enumerator_params:
            if param.vk.name in [self.__p_count, self.__p_handles]:
                continue
            lines += [
               f'    {param.boost.name} : {param.boost.type};',
            ]
        lines += [
           f'    var result : VkResult? = [[VkResult?]]',
           f'): array<{self.__boost_type}>',
        ]
        params = []
        for param in self.__vk_enumerator_params:
            if param.vk.name in [self.__p_count, self.__p_handles]:
                continue
            params.append(param.boost.name)
        params_text = ', '.join(params + ['result'])
        lines += [
           f'    var handles <- {self.__boost_enumerator}({params_text})',
            '    defer() <| ${ delete handles; }',
           f'    return <- handles |> split()',
        ]
        return lines

    def __generate_ctor(self):
        lines = []
        lines += [
            '',
           f'def {self.__boost_ctor}(']
        for param in self.__vk_ctor_params:
            if param.vk.name == 'pAllocator':
                continue
            elif param.vk.type == f'{self.__vk_type_name} *':
                continue
            elif param.vk.name == self.__p_create_info:
                lines += [f'    {param.boost.name} : {param.boost.type_deref}']
            else:
                raise Exception(f'TODO: add support for extra param '
                    f'{param.vk.name}')
                lines += [f'    {param.boost.name} : {param.boost.type};']
        lines += [
           f'    var result : VkResult? = [[VkResult?]]',
           f') : {self.__boost_type}',
            '',
           f'    var {self.__boost_attr} : {self.__boost_type}',
           f'    {self.__boost_create_info} |> with_view() <| $(vk_info)',
           f'        var result_ = VkResult VK_SUCCESS',
           f'        result ?? result_ = self.__vk_ctor_name(',
        ]
        params = []
        for param in self.__vk_ctor_params:
            if param.vk.name == self.__p_create_info:
                params.append('safe_addr(vk_info)')
            elif param.boost.type == self.__boost_type+' *':
                params.append(
                    f'safe_addr({self.__boost_attr}.{self.__boost_attr})')
            elif param.vk.name == 'pAllocator':
                params.append('null')
            else:
                raise Exception(f'TODO: add support for extra param '
                    f'{param.vk.name}')
                params.append(param.boost.vk_value)
        params_text = ', '.join(params)
        lines + [
           f'            {params_text}',
           f'        )',
           f'        assert(result_ == VkResult VK_SUCCESS)',
           f'    return <- {self.__boost_attr}',
        ]
        return lines

    def __generate_dtor(self):
        lines = []
        lines += [
           f'def finalize(var {self.__boost_attr} : {self.__boost_type})',
           f'    self.__vk_dtor_name(',
        ]
        params = []
        for param in self.__vk_dtor_params:
            if param.boost.type == self.__boost_type:
                params.append(f'{self.__boost_attr}.{self.__boost_attr}')
            elif param.vk.name == 'pAllocator':
                params.append('null')
            else:
                raise Exception(f'TODO: add support for extra param '
                    f'{param.vk.name}')
        params_text = ', '.join(params)
        lines += [
           f'        {params_text}',
           f'    )',
           f'    memzero({self.__boost_attr})',
        ]
        return lines


class BoostType(object):

    def __init__(self, c_type_name):
        self.c_type_name = c_type_name

    @property
    def name(self):
        return self.c_type_name

    def to_vk_value(self, boost_value):
        return boost_value


class BoostVkHandleType(BoostType):

    @classmethod
    def maybe_create(cls, c_type_name):
        if cls.__get_boost_handle_type_name(c_type_name):
            return cls(c_type_name=c_type_name)

    @staticmethod
    def __get_boost_handle_type_name(c_type_name):
        m = re.match(r'struct Vk(\S*)_T \*', c_type_name)
        if m:
            return m.group(1)

    @property
    def name(self):
        return self.__get_boost_handle_type_name(self.c_type_name)

    def to_vk_value(self, boost_value):
        attr = boost_camel_to_lower(self.name)
        return f'{boost_value}.{attr}'


class BoostVkStructConstPtrType(BoostType):

    @classmethod
    def maybe_create(cls, c_type_name):
        if cls.__get_vk_struct_name(c_type_name):
            return cls(c_type_name=c_type_name)

    @staticmethod
    def __get_vk_struct_name(c_type_name):
        m = re.match(r'const (Vk\S*) \*', c_type_name)
        if m:
            return m.group(1)

    @property
    def __vk_struct_name(self):
        return self.__get_vk_struct_name(self.c_type_name)

    @property
    def name(self):
        assert_starts_with(self.__vk_struct_name, 'Vk')
        return self.__vk_struct_name[2:] + ' *'

    def to_vk_value(self, boost_value):
        raise Exception('Not supported')


class BoostUnknownType(BoostType):

    @property
    def name(self):
        raise VulkanBoostError(
            f'Cannot convert to boost type: {self.c_type_name}')


class ParamEx(object):

    def __init__(self, vk_param):
        self.vk = vk_param
        self.boost = BoostParam(vk_param)


class BoostParam(object):

    def __init__(self, vk_param):
        self.__vk_param = vk_param
        self.__type = to_boost_type(self.__vk_param.type)

    @property
    def name(self):
        return boost_camel_to_lower(self.__vk_param.das_name)

    @property
    def type(self):
        return self.__type.name

    @property
    def type_deref(self):
        t = self.type
        assert_ends_with(t, '*')
        return t[:-1].strip()

    @property
    def vk_value(self):
        return self.__type.to_vk_value(self.name)


def boost_camel_to_lower(camel):
    result = ''
    for c in camel:
        if c.isupper() and result and result[-1] != '_':
            result += '_'
        result += c.lower()
    return result

def to_boost_type(c_type):
    for type_class in [
        BoostVkHandleType,
        BoostVkStructConstPtrType,
    ]:
        boost_type = type_class.maybe_create(c_type)
        if boost_type:
            return boost_type
    return BoostUnknownType(c_type_name=c_type)

def to_boost_func_name(vk_name):
    assert_starts_with(vk_name, 'vk')
    return boost_camel_to_lower(vk_name[2:])
