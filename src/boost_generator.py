from das_shared.object_base import LoggingObject
from das_shared.assertions import assert_starts_with, assert_ends_with
import re


#TODO: add pAllocator support


class VulkanBoostError(Exception):
    pass


class BoostGenerator(LoggingObject):

    def __init__(self, context):
        self.__context = context
        self.__gen_handles = []
        self.__gen_structs = []
        self.__gen_query_funcs = []

        self.enums = dict((x.name, x)
            for x in self.__context.main_c_header.enums)
        self.structs = dict((x.name, x)
            for x in self.__context.main_c_header.structs)
        self.opaque_structs = dict((x.name, x)
            for x in self.__context.main_c_header.opaque_structs)
        self.functions = dict((x.name, x)
            for x in self.__context.main_c_header.functions)

    def add_gen_handle(self, **kwargs):
        handle = GenHandle(generator=self, **kwargs)
        self.__gen_handles.append(handle)
        return handle

    def add_gen_struct(self, **kwargs):
        struct = GenStruct(generator=self, **kwargs)
        self.__gen_structs.append(struct)
        return struct

    def add_gen_query_func(self, **kwargs):
        func = GenQueryFunc(generator=self, **kwargs)
        self.__gen_query_funcs.append(func)
        return func

    def get_func_params_ex(self, vk_func):
        return [ParamEx(vk_param=p, generator=self) for p in vk_func.params]

    def get_struct_fields_ex(self, vk_struct):
        return [StructFieldEx(vk_field=f, generator=self)
            for f in vk_struct.fields]

    def get_boost_type(self, c_type):
        for type_class in [
            BoostVkHandleType,
            BoostVkHandlePtrType,
            BoostVkStructPtrType,
            BoostStringType,
            BoostFixedStringType,
            BoostStringPtrType,
            BoostUInt32Type,
            BoostUnknownType,
        ]:
            boost_type = type_class.maybe_create(
                c_type_name=c_type, generator=self)
            if boost_type:
                return boost_type

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
            '',
            '//',
            '// Helpers',
            '//',
            '',
            'def with_p_view(',
            '    p_boost_struct : auto(BOOST_T)?;',
            '    b : block<(p_vk_struct : auto(VK_T)?)>',
            ')',
            '    if p_boost_struct == null',
            '        b |> invoke([[VK_T?]])',
            '    else',
            '        *p_boost_struct |> with_view() <| $(vk_struct)',
            '            unsafe',
            '                b |> invoke(addr(vk_struct))',
            '',
            'def to_string(bytes : int8[])',
            '    unsafe',
            '        return reinterpret<string>(addr(bytes[0]))',
        ] + [
            line for items in [
                self.__gen_structs,
                self.__gen_handles,
                self.__gen_query_funcs,
            ] for item in items for line in item.generate()
        ]


class GenQueryFunc(object):

    def __init__(self, generator, func, p_output):
        self.__generator = generator
        self.__vk_func_name = func
        self.__p_output = p_output

    @property
    def __boost_func(self):
        assert_starts_with(self.__vk_func_name, 'vk')
        return boost_camel_to_lower(self.__vk_func_name[2:])

    @property
    def __params(self):
        return self.__generator.get_func_params_ex(self.__vk_func_name)

    @property
    def __output_param(self):
        for param in self.__params:
            if param.vk.name == self.__p_output:
                return param

    @property
    def __vk_func(self):
        return self.__generator.functions[self.__vk_func_name]

    @property
    def __returns_vk_result(self):
        return returns_vk_result(self.__vk_func)

    def generate(self):
        # TODO: refactor BoostType into VkType and BoostType
        # TODO: rename vk_type to c_type everywhere
        return [] 
        lines = []
        lines += [
           f'def {self.__boost_func}('
        ]
        for param in self.__params:
            if param.vk.name == self.__p_output:
                continue
            lines.append(f'    {param.boost.name} : {param.boost.type},')
        if self.__returns_vk_result:
            lines.append(f'    var result : VkResult? = [[VkResult?]]')
        if lines[-1].endswith(','):
            lines[-1] = lines[-1][:-1]
        lines += [
           f') : {self.__output_param.boost.type_deref}',
           f'    var vk_output : {self.__output_param.vk.type_deref}',
           f'    physical_device.physical_device |> vkGetPhysicalDeviceProperties(',
           f'        safe_addr(props))',
           f'    return <- props',
        ]
        return lines


class GenStruct(object):

    def __init__(self, generator, struct,
        boost_to_vk=False, vk_to_boost=False,
    ):
        self.__generator = generator
        self.__vk_type_name = struct
        self.__boost_to_vk = boost_to_vk
        self.__vk_to_boost = vk_to_boost
        self.__arrays = []

    def declare_array(self, **kwargs):
        array = GenStructFieldArray(**kwargs)
        self.__arrays.append(array)
        return self

    @property
    def __vk_struct(self):
        return self.__generator.structs[self.__vk_type_name]

    @property
    def __fields(self):
        return self.__generator.get_struct_fields_ex(self.__vk_struct)

    @property
    def __boost_type(self):
        assert_starts_with(self.__vk_type_name, 'Vk')
        return self.__vk_type_name[2:]

    def __is_array_count(self, vk_field):
        for array in self.__arrays:
            if vk_field == array.vk_count_name:
                return True
        return False

    def __is_array_items(self, vk_field):
        for array in self.__arrays:
            if vk_field == array.vk_items_name:
                return True
        return False

    @property
    def __vk_structure_type(self):
        return 'VK_STRUCTURE_TYPE_' + (
            boost_camel_to_lower(self.__boost_type).upper())

    def __get_array(self, vk_items_name):
        for array in self.__arrays:
            if vk_items_name == array.vk_items_name:
                return array

    def generate(self):
        lines = []
        lines += [
            '',
            '//',
           f'// {self.__boost_type}',
            '//',
        ]
        lines += self.__generate_type()
        if self.__boost_to_vk:
            lines += self.__generate_boost_to_vk()
        if self.__vk_to_boost:
            lines += self.__generate_vk_to_boost()
        return lines

    def __generate_type(self):
        lines = []
        lines += [
            '',
           f'struct {self.__boost_type}',
        ]
        for field in self.__fields:
            if self.__is_array_count(field.vk.name):
                continue
            if field.vk.name in ['sType', 'pNext']:
                continue
            elif self.__is_array_items(field.vk.name):
                boost_name = field.boost.name_ptr_as_array
                boost_type = field.boost.type_ptr_as_array
                lines += [f'    {boost_name} : {boost_type}']
            else:
                lines += [f'    {field.boost.name} : {field.boost.type}']
        return lines

    def __generate_vk_to_boost(self):
        lines = []
        lines += [
            '',
           f'def construct(vk_struct : {self.__vk_type_name}) '
                f': {self.__boost_type}',
           f'    return <- [[{self.__boost_type}'
        ]
        for field in self.__fields:
            if field.vk.name in ['sType', 'pNext']:
                continue
            vk_value = field.boost.to_boost_value(
                f'vk_struct.{field.vk.name}')
            lines += [f'        {field.boost.name} = {vk_value},']
        assert_ends_with(lines[-1], ',')
        lines[-1] = lines[-1][:-1]
        lines += [
            '    ]]'
        ]
        return lines

    def __generate_boost_to_vk(self):
        lines = []
        lines += [
            '',
            'def with_view(',
           f'    boost_struct : {self.__boost_type};',
           f'    b : block<(vk_struct : {self.__vk_type_name})>',
            ') {',
        ]

        depth = 0
        for field in self.__fields:
            if field.vk.name in ['sType', 'pNext']:
                continue
            if self.__is_array_count(field.vk.name):
                continue
            elif self.__is_array_items(field.vk.name):
                depth += 1
                ar = self.__get_array(field.vk.name)
                items_name = field.boost.name_ptr_as_array
                count_name = boost_camel_to_lower(ar.vk_count_name)
                lines += [
                   f'    boost_struct.{items_name} |> lock_data() <| $(',
                   f'        vk_p_{items_name}, vk_{count_name}',
                    '    ) {',
                ]
            elif field.boost.needs_view_to_vk:
                depth += 1
                boost_name = field.boost.name
                view_type = field.boost.view_to_vk_type
                lines += [
                   f'    boost_struct.{boost_name} |> with_p_view() <| $(',
                   f'        vk_{boost_name} : {view_type}',
                    '    ) {',
                ]

        lines += [
           f'    let vk_struct <- [[ {self.__vk_type_name}',
        ]

        for field in self.__fields:
            if field.vk.name in ['sType', 'pNext']:
                continue
            if self.__is_array_count(field.vk.name):
                boost_value = f'uint(vk_{field.boost.name})'
            elif self.__is_array_items(field.vk.name):
                boost_value = f'vk_p_{field.boost.name_ptr_as_array}' 
            elif field.boost.needs_view_to_vk:
                boost_value = f'vk_{field.boost.name}'
            else:
                boost_value = field.boost.to_vk_value(
                    f'boost_struct.{field.boost.name}')
            lines.append(f'        {field.vk.name} = {boost_value},')

        lines += [
           f'        sType = VkStructureType {self.__vk_structure_type}',
           f'    ]];',
           f'    b |> invoke(vk_struct);',
        ]
        if depth > 0:
            lines += ['    ' + ('}'*depth) + ';']
        lines += [
            '}',
        ]
        return lines


class GenStructFieldArray(object):

    def __init__(self, count, items):
        self.vk_count_name = count
        self.vk_items_name = items


class GenHandle(object):

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
        return self.__generator.get_func_params_ex(self.__vk_enumerator)

    @property
    def __vk_ctor_params(self):
        return self.__generator.get_func_params_ex(self.__vk_ctor)

    @property
    def __vk_dtor_params(self):
        return self.__generator.get_func_params_ex(self.__vk_dtor)

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
    def __boost_create_info(self):
        param = boost_camel_to_lower(self.__p_create_info)
        assert_starts_with(param, 'p_')
        return param[2:]

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
                pname = self.__boost_create_info
                ptype = param.boost.type_deref
                lines += [f'    {pname} : {ptype} = [[ {ptype} ]];']
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
           f'        result ?? result_ = {self.__vk_ctor_name}(',
        ]
        params = []
        for param in self.__vk_ctor_params:
            if param.vk.name == self.__p_create_info:
                params.append('safe_addr(vk_info)')
            elif param.boost.type == self.__boost_type+' ?':
                params.append(
                    f'safe_addr({self.__boost_attr}.{self.__boost_attr})')
            elif param.vk.name == 'pAllocator':
                params.append('null')
            else:
                raise Exception(f'TODO: add support for extra param '
                    f'{param.vk.name}')
                params.append(param.boost.vk_value)
        params_text = ', '.join(params)
        lines += [
           f'            {params_text}',
           f'        )',
           f'        assert(result_ == VkResult VK_SUCCESS)',
           f'    return <- {self.__boost_attr}',
        ]
        return lines

    def __generate_dtor(self):
        lines = []
        lines += [
            '',
           f'def finalize(var {self.__boost_attr} : {self.__boost_type})',
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
           f'    {self.__vk_dtor_name}({params_text})',
           f'    memzero({self.__boost_attr})',
        ]
        return lines


class BoostType(object):

    def __init__(self, c_type_name, generator):
        self.c_type_name = c_type_name
        self.generator = generator

    @property
    def name(self):
        return self.c_type_name

    def to_vk_value(self, boost_value):
        return boost_value

    def to_boost_value(self, vk_value):
        return vk_value

    @property
    def deref_name(self):
        assert_ends_with(self.name, '?')
        return self.name[:-1].strip()

    def adjust_field_name(self, name):
        return name

    @property
    def needs_view_to_vk(self):
        return False

    @property
    def view_to_vk_type(self):
        raise NotImplemented()


class BoostVkHandleType(BoostType):

    @classmethod
    def maybe_create(cls, c_type_name, **kwargs):
        if cls.__get_boost_handle_type_name(c_type_name):
            return cls(c_type_name=c_type_name, **kwargs)

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


class BoostVkHandlePtrType(BoostType):

    @classmethod
    def maybe_create(cls, c_type_name, generator):
        name = cls.__get_boost_handle_type_name(c_type_name)
        if f'Vk{name}_T' in generator.opaque_structs:
            return cls(c_type_name=c_type_name, generator=generator)

    @staticmethod
    def __get_boost_handle_type_name(c_type_name):
        m = re.match(r'Vk(\S*) \*', c_type_name)
        if m:
            return m.group(1)

    @property
    def name(self):
        return self.__get_boost_handle_type_name(self.c_type_name) + ' ?'

    def to_vk_value(self, boost_value):
        raise Exception(f'TODO: add if needed ({self.name})')


class BoostFixedStringType(BoostType):

    @classmethod
    def maybe_create(cls, c_type_name, **kwargs):
        if re.match(r'char \[\d+\]', c_type_name):
            return cls(c_type_name=c_type_name, **kwargs)

    @property
    def name(self):
        return 'string'

    def to_vk_value(self, boost_value):
        raise Exception(f'TODO: add if needed')

    def to_boost_value(self, vk_value):
        return f'to_string({vk_value})'


class BoostStringType(BoostType):

    @classmethod
    def maybe_create(cls, c_type_name, **kwargs):
        if c_type_name == 'const char *':
            return cls(c_type_name=c_type_name, **kwargs)

    @property
    def name(self):
        return 'string'

    def adjust_field_name(self, name):
        return name[2:] if name.startswith('p_') else name


class BoostStringPtrType(BoostType):

    @classmethod
    def maybe_create(cls, c_type_name, **kwargs):
        if c_type_name == 'const char *const *':
            return cls(c_type_name=c_type_name, **kwargs)

    @property
    def name(self):
        return 'string ?'

    def adjust_field_name(self, name):
        return name[1:] if name.startswith('pp_') else name


class BoostUInt32Type(BoostType):

    @classmethod
    def maybe_create(cls, c_type_name, **kwargs):
        if c_type_name == 'unsigned int':
            return cls(c_type_name=c_type_name, **kwargs)

    @property
    def name(self):
        return 'uint'


class BoostVkStructPtrType(BoostType):

    @classmethod
    def maybe_create(cls, c_type_name, generator):
        if cls.__get_vk_type_name(c_type_name) in generator.structs:
            return cls(c_type_name=c_type_name, generator=generator)

    @staticmethod
    def __get_vk_type_name(c_type_name):
        m = re.match(r'(const )?(Vk\S*) \*', c_type_name)
        if m:
            return m.group(2)

    @property
    def __vk_type_name(self):
        return self.__get_vk_type_name(self.c_type_name)

    @property
    def name(self):
        assert_starts_with(self.__vk_type_name, 'Vk')
        return self.__vk_type_name[2:] + ' ?'

    def to_vk_value(self, boost_value):
        raise Exception('Use view for conversion')

    @property
    def needs_view_to_vk(self):
        return True

    @property
    def view_to_vk_type(self):
        return f'{self.__vk_type_name} const ?'


class BoostUnknownType(BoostType):

    @classmethod
    def maybe_create(cls, **kwargs):
        return cls(**kwargs)

    @property
    def name(self):
        raise VulkanBoostError(
            f'Cannot convert to boost type: {self.c_type_name}')


class ParamEx(object):

    def __init__(self, vk_param, generator):
        self.vk = vk_param
        self.boost = BoostParam(vk_param=vk_param, generator=generator)


class BoostFieldBase(object):

    def __init__(self, generator):
        self.__cached_type = None
        self.__generator = generator

    @property
    def _vk_field(self):
        raise NotImplemented()

    @property
    def _type(self):
        if self.__cached_type is None:
            self.__cached_type = self.__generator.get_boost_type(
                self._vk_field.type)
        return self.__cached_type

    @property
    def name(self):
        return self._type.adjust_field_name(
            boost_camel_to_lower(self._vk_field.das_name))

    @property
    def type(self):
        return self._type.name

    @property
    def type_deref(self):
        return self._type.deref_name

    @property
    def type_ptr_as_array(self):
        return f'array<{self.type_deref}>'

    @property
    def name_ptr_as_array(self):
        name = self.name
        return name[2:] if name.startswith('p_') else name

    @property
    def vk_value(self):
        return self._type.to_vk_value(self.name)

    def to_vk_value(self, boost_value):
        return self._type.to_vk_value(boost_value)

    def to_boost_value(self, vk_value):
        return self._type.to_boost_value(vk_value)

    @property
    def needs_view_to_vk(self):
        return self._type.needs_view_to_vk

    @property
    def view_to_vk_type(self):
        return self._type.view_to_vk_type


class BoostParam(BoostFieldBase):

    def __init__(self, vk_param, **kwargs):
        super(BoostParam, self).__init__(**kwargs)
        self.__vk_param = vk_param

    @property
    def _vk_field(self):
        return self.__vk_param


class StructFieldEx(object):

    def __init__(self, vk_field, generator):
        self.vk = vk_field
        self.boost = BoostStructField(vk_field=vk_field, generator=generator)


class BoostStructField(BoostFieldBase):

    def __init__(self, vk_field, **kwargs):
        super(BoostStructField, self).__init__(**kwargs)
        self.__vk_field = vk_field

    @property
    def _vk_field(self):
        return self.__vk_field


def boost_camel_to_lower(camel):
    result = ''
    for c in camel:
        if c.isupper() and result and result[-1] != '_':
            result += '_'
        result += c.lower()
    return result

def to_boost_func_name(vk_name):
    assert_starts_with(vk_name, 'vk')
    return boost_camel_to_lower(vk_name[2:])

def returns_vk_result(func):
    return func.return_type == 'VkResult'
