from das_shared.object_base import LoggingObject
from das_shared.op_sys import full_path, write_to_file
from das_shared.assertions import (assert_starts_with, assert_ends_with,
    assert_not_in, assert_greater, assert_equal)
from das_shared.diag import log_on_exception
from os import path
import re


#TODO: move to shared
def assert_is(a, b):
    if a is not b:
        raise Exception(f'{a} is not {b}')


#TODO: add pAllocator support


class VulkanBoostError(Exception):
    pass


class BoostGenerator(LoggingObject):

    def __init__(self, context):
        self.__context = context
        self.__gen_handles = []
        self.__gen_structs = []
        self.__gen_funcs = []

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

    def add_gen_func(self, **kwargs):
        func = GenFunc(generator=self, **kwargs)
        self.__gen_funcs.append(func)
        return func

    def create_func_params(self, c_func):
        return list(map(self.create_param_from_node, c_func.params))

    def create_struct_fields(self, c_struct):
        return list(map(self.create_param_from_node, c_struct.fields))

    def create_param(self, c_name, c_type):
        for param_class in [
            ParamVk_pAllocator,
            ParamVk_pNext,
            ParamVk_sType,
            ParamVkHandle,
            ParamVkHandlePtr,
            ParamVkStruct,
            ParamVkEnum,
            ParamString,
            ParamFixedString,
            ParamStringPtr,
            ParamFloat,
            ParamInt32,
            ParamUInt8,
            ParamUInt32,
            ParamUInt64,
            ParamVkBool32,
            ParamVoidPtr,
            ParamUnknown,
        ]:
            param = param_class.maybe_create(
                c_param=C_Param(c_name=c_name, c_type=c_type,
                    generator=self))
            if param:
                return param

    def create_param_from_node(self, c_node):
        return self.create_param(c_node.name, c_node.type)

    def write(self):
        fpath = full_path(path.join(path.dirname(__file__),
            '../daslib/internal/generated.das'))
        self._log_info(f'Writing to: {fpath}')
        write_to_file(fpath=fpath,
            content='\n'.join(self.__generate() + ['']))

    def __generate(self):
        return [
            self.__preamble(),
            '//',
            '// Functions',
            '//',
        ] + [
            line for items in [
                self.__gen_funcs,
                self.__gen_structs,
                self.__gen_handles,
            ] for item in items for line in item.generate()
        ] 

    def __preamble(self):
        fpath = path.join(path.dirname(__file__), 'boost_preamble.das')
        with open(fpath, 'r') as f:
            return f.read()


class GenFunc(object):

    def __init__(self, generator, name, private=False):
        self.__generator = generator
        self._vk_func_name = name
        self._private = private

        self._params = self.__generator.create_func_params(self.__c_func)

    @property
    def _boost_func_name(self):
        return vk_func_name_to_boost(self._vk_func_name)

    @property
    def __c_func(self):
        return self.__generator.functions[self._vk_func_name]

    @property
    def _output_params(self):
        return [p for p in self._params if p._is_boost_func_output]

    @property
    def __have_array_outputs_of_unknown_size(self):
        for param in self._params:
            if param.vk_is_dyn_array_count and param.is_dyn_array_output:
                return True
        return False

    @property
    def _returns_vk_result(self):
        return returns_vk_result(self.__c_func)

    def __get_param(self, vk_name):
        for param in self._params:
            if param.vk_name == vk_name:
                return param

    def declare_array(self, items, count=None):
        with log_on_exception(func=self._vk_func_name,
             count=count, items=items
        ):
            p_count = self.__get_param(count) if count else None
            p_items = self.__get_param(items)
            if p_count:
                p_count.set_dyn_array(count=p_count, items=p_items)
            p_items.set_dyn_array(count=p_count, items=p_items)
        return self

    def declare_output(self, name):
        for param in self._params:
            if param.vk_name == name:
                param.set_boost_func_output()
        return self

    @property
    def _return_type(self):
        if len(self._output_params) > 1:
            raise Exception('TODO: add multiple outputs support if needed')
        for output in self._output_params:
            return output._boost_func_param_type
        return 'void'

    @property
    def __return_value(self):
        if len(self._output_params) > 1:
            raise Exception('TODO: add multiple outputs support if needed')
        for output in self._output_params:
            return output.boost_func_return_value

    def generate(self):
        lines = []
        lines += [
            '',
        ]
        if self._private:
            lines += ['[private]']
        lines += [
           f'def {self._boost_func_name}('
        ]
        for param in self._params:
            lines += [f'    {line}'
                for line in param.generate_boost_func_param_decl()]
        if self._returns_vk_result:
            lines.append(f'    var result : VkResult? = [[VkResult?]];')
        remove_last_char(lines, ';')
        lines += [
           f') : {self._return_type}',
            '',
        ]
        for param in self._params:
            lines += [f'    {line}'
                for line in param.generate_boost_func_temp_vars_init()]

        if self._returns_vk_result:
            lines.append(f'    var result_ = VkResult VK_SUCCESS')
        maybe_capture_result = ('result ?? result_ = '
            if self._returns_vk_result else '')

        if lines[-1] != '':
            lines.append('')
        if self.__have_array_outputs_of_unknown_size:
            lines += [
               f'    {maybe_capture_result}{self._vk_func_name}(',
            ]
            for param in self._params:
                lines += ['        {},'.format(
                    param.boost_func_query_array_size_param)]
            remove_last_char(lines, ',')
            lines += [
               f'    )',
            ]
            if self._returns_vk_result:
                lines.append('    assert(result_ == VkResult VK_SUCCESS)')
                maybe_null_output = (f' <- [[ {self._return_type} ]]'
                    if self._return_type != 'void' else '')
                lines += [
                   f'    if result_ != VkResult VK_SUCCESS',
                   f'        return{maybe_null_output}',
                ]

        for param in self._params:
            lines += [f'    {line}'
                for line in param.generate_boost_func_temp_vars_update()]

        lines += [
           f'    {maybe_capture_result}{self._vk_func_name}(',
        ]
        for param in self._params:
            lines += ['        {},'.format(param.boost_func_call_vk_param)]
        remove_last_char(lines, ',')
        lines += [
           f'    )',
        ]
        if self._returns_vk_result:
            lines.append('    assert(result_ == VkResult VK_SUCCESS)')

        if self._return_type != 'void':
            lines.append(f'    return {self.__return_value}')
        return lines


class GenStruct(object):

    def __init__(self, generator, name, boost_to_vk=True, vk_to_boost=True):
        self.__generator = generator
        self.__vk_type_name = name
        self.__boost_to_vk = boost_to_vk
        self.__vk_to_boost = vk_to_boost

        self.__fields = self.__generator.create_struct_fields(self.__c_struct)
        for field in self.__fields:
            field.set_gen_struct(self)

    @property
    def __c_struct(self):
        return self.__generator.structs[self.__vk_type_name]

    @property
    def boost_type_name(self):
        return vk_struct_type_to_boost(self.__vk_type_name)

    def __get_field(self, vk_name):
        for field in self.__fields:
            if field.vk_name == vk_name:
                return field

    def declare_array(self, items, count=None,
        optional=False, force_item_type=None
    ):
        p_count = self.__get_field(count) if count else None
        p_items = self.__get_field(items)
        if p_count:
            p_count.set_dyn_array(count=p_count, items=p_items)
        p_items.set_dyn_array(count=p_count, items=p_items)
        p_items.set_optional(optional)
        p_items.force_boost_unqual_type(force_item_type)
        return self

    def generate(self):
        lines = []
        lines += [
            '',
            '//',
           f'// {self.boost_type_name}',
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
           f'struct {self.boost_type_name}',
        ]
        lines += [f'    {line}' for field in self.__fields
            for line in field.generate_boost_struct_field_decl()]

        if self.__boost_to_vk:
            lines += [f'    {line}' for field in self.__fields
                for line in field.generate_boost_struct_field_view_decl()]
            lines += [f'    _vk_view__active : bool']
        return lines

    def __generate_vk_to_boost(self):
        lines = []
        lines += [
            '',
           f'def vk_value_to_boost(vk_struct : {self.__vk_type_name}) '
                f': {self.boost_type_name}',
        ] + [
           f'    {line}' for field in self.__fields for line in
                 field.generate_boost_struct_v2b_vars()
        ] + [
           f'    return <- [[{self.boost_type_name}'
        ] + [
           f'        {line}' for field in self.__fields for line in
                     field.generate_boost_struct_v2b_field()
        ]
        remove_last_char(lines, ',')
        lines += [
            '    ]]'
        ]
        return lines

    def __generate_boost_to_vk(self):
        return (self.__generate_vk_view_create()
            + self.__generate_vk_view_destroy())

    def __generate_vk_view_create(self):
        btype = self.boost_type_name
        vtype = self.__vk_type_name
        lines = []
        lines += [
            '',
           f'def vk_view_create_unsafe(var boost_struct : {btype}',
           f') : {vtype}',
            '',
            '    assert(!boost_struct._vk_view__active)',
            '    boost_struct._vk_view__active = true',
        ] + [
           f'    {line}' for field in self.__fields for line in
                 field.generate_boost_struct_view_create_init()
        ] + [
           f'    return <- [[ {vtype}',
        ] + [
           f'        {line}' for field in self.__fields for line in
                     field.generate_boost_struct_view_create_field()
        ]
        remove_last_char(lines, ',')
        lines += [
           f'    ]]',
        ]
        return lines

    def __generate_vk_view_destroy(self):
        return [
            '',
           f'def vk_view_destroy(var boost_struct : {self.boost_type_name})',
            '    assert(boost_struct._vk_view__active)',
        ] + [
           f'    {line}' for field in self.__fields for line in
                 field.generate_boost_struct_view_destroy()
        ] + [
            '    boost_struct._vk_view__active = false',
        ]


class GenHandle(object):

    def __init__(self, generator, name):
        self._generator = generator
        self.vk_handle_type_name = name

        self.dtor = self.__maybe_create_default_dtor()
        self._ctors = self.__create_default_ctors()

    def __maybe_create_default_dtor(self):
        name = vk_handle_type_to_vk_dtor(self.vk_handle_type_name)
        if name in self._generator.functions:
            return GenHandleDtor(handle=self, name=name)

    def __create_default_ctors(self):
        ctors = []
        name = vk_handle_type_to_vk_ctor(self.vk_handle_type_name)
        if name in self._generator.functions:
            ctors.append(GenHandleCtor(handle=self, name=name))
        return ctors

    def declare_ctor(self, name):
        ctor = GenHandleCtor(handle=self, name=name)
        self._ctors.append(ctor)
        return ctor

    @property
    def boost_handle_type_name(self):
        return vk_handle_type_to_boost(self.vk_handle_type_name)

    @property
    def boost_handle_attr(self):
        return boost_handle_attr_name(self.boost_handle_type_name)

    def __generate_handle_fields(self):
        lines = []
        if self.dtor:
            lines += [line for param in self.dtor._params
                for line in param.generate_boost_handle_field()
                if param.vk_unqual_type != self.vk_handle_type_name]
        return lines

    def generate(self):
        lines = []
        lines += [
            '',
            '//',
           f'// {self.boost_handle_type_name}',
            '//',
        ]
        lines += self.__generate_type()
        for ctor in self._ctors:
            lines += ctor.generate()
        if self.dtor:
            lines += self.dtor.generate()
        return lines

    def __generate_type(self):
        lines = []
        bhtype = self.boost_handle_type_name
        vhtype = self.vk_handle_type_name
        attr = self.boost_handle_attr
        lines += [
            '',
           f'struct {bhtype}',
           f'    {attr} : {vhtype}',
            '    _needs_delete : bool',
        ]
        if self.dtor:
            lines += [f'    {line}'
                for line in self.__generate_handle_fields()]
        lines += [
            '',
           f'def boost_value_to_vk(b : {bhtype}) : {vhtype}',
           f'    return b.{attr}',
            '',
           f'def boost_value_to_vk(b : {bhtype} ?) : {vhtype} ?',
           f'    return b?.{attr}',
            '',
           f'def vk_value_to_boost(v : {vhtype}) : {bhtype}',
           f'    return [[ {bhtype} {attr}=v ]]',
        ]
        return lines


class GenHandleCtor(GenFunc):

    def __init__(self, handle, name):
        super(GenHandleCtor, self).__init__(
            generator=handle._generator, name=name, private=True)
        self.__handle = handle

        self.__handle_param.set_boost_func_output()

    @property
    def _boost_func_name(self):
        return self.__boost_inner_ctor_func_name

    @property
    def __boost_inner_ctor_func_name(self):
        return vk_func_name_to_boost(self._vk_func_name) + '__inner'

    @property
    def __boost_outer_ctor_func_name(self):
        return vk_func_name_to_boost(self._vk_func_name)

    @property
    def __handle_param(self):
        for param in self._params:
            if param.vk_unqual_type == self.__handle.vk_handle_type_name:
                return param

    @property
    def __returns_array(self):
        return self.__handle_param.vk_is_dyn_array_items

    def __generate_handle_init_fields(self):
        lines = []
        if self.__handle.dtor:
            lines += [f'handle._needs_delete = true']
            lines += [line for param in self.__handle.dtor._params
                for line in param.generate_boost_handle_ctor_init_field()
                if param.vk_unqual_type != self.__handle.vk_handle_type_name]
        return lines

    @property
    def __return_var(self):
        return 'handles' if self.__returns_array else 'handle'

    def generate(self):
        assert_equal(len(self._output_params), 1)

        lines = super(GenHandleCtor, self).generate()
        lines += [
            '',
           f'def {self.__boost_outer_ctor_func_name}(']
        for param in self._params:
            lines += [f'    {line}'
                for line in param.generate_boost_func_param_decl()]
        if self._returns_vk_result:
            lines.append(f'    var result : VkResult? = [[VkResult?]];')
        remove_last_char(lines, ';')
        inner_ctor = self.__boost_inner_ctor_func_name
        lines += [
           f') : {self._return_type}',
            '',
           f'    var {self.__return_var} <- {inner_ctor}(',
        ]
        for param in self._params:
            lines += [f'        {line}'
                for line in param.generate_boost_func_param_call()]
        if self._returns_vk_result:
            lines.append(f'        result,')
        remove_last_char(lines, ',')
        lines += [
           f'    )',
        ]
        if self.__returns_array:
            lines += [f'    for handle in handles']
            lines += [f'        {line}'
                for line in self.__generate_handle_init_fields()]
        else:
            lines += [f'    {line}'
                for line in self.__generate_handle_init_fields()]
        lines += [
           f'    return <- {self.__return_var}',
        ]
        return lines


class GenHandleDtor(GenFunc):

    def __init__(self, handle, name):
        super(GenHandleDtor, self).__init__(
            generator=handle._generator, name=name, private=True)
        self.__handle = handle

    def generate(self):
        bh_type = self.__handle.boost_handle_type_name
        lines = super(GenHandleDtor, self).generate()
        lines += [
            '',
           f'def finalize(var handle : {bh_type} explicit)',
           f'    if handle._needs_delete',
           f'        {self._boost_func_name}(',
        ] + [
           f'            {line}' for param in self._params for line in
                         param.get_boost_dtor_call_param(bh_type)]
        remove_last_char(lines, ',')
        lines += [
            '        )',
           f'    memzero(handle)',
        ]
        return lines


class C_Param(object):

    def __init__(self, c_name, c_type, generator):
        self.name = c_name
        self.type = C_Type(name=c_type, generator=generator)
        self._generator = generator


class C_Type(object):

    def __init__(self, name, generator):
        self.name = name
        self._generator = generator

    @property
    def is_enum(self):
        return self.unqual_name in self._generator.enums

    @property
    def is_struct(self):
        return self.unqual_name in self._generator.structs

    @property
    def is_opaque_struct(self):
        return self.unqual_name in self._generator.opaque_structs

    @property
    def is_pointer(self):
        return self.name.endswith('*')

    @property
    def is_fixed_array(self):
        return self.fixed_array_size is not None

    @property
    def fixed_array_size(self):
        m = re.match(r'.*\[(\d+)\]$', self.name)
        if m:
            return int(m.group(1))

    @property
    def unqual_name(self):
        for pattern in [
            (   r'^(const)?(struct|enum)?\s*'
                r'(?P<type>(unsigned )?(long )?[A-z0-9_]+)'
                r'( \*| \[\d+\])?$'
            ),
        ]:
            m = re.match(pattern, self.name)
            if m:
                return m.groupdict()['type']

        unqual_name = {
            'const char *const *': 'char',
        }.get(self.name)

        if unqual_name:
            return unqual_name
        raise VulkanBoostError(f'Cannot extract unqualified C type from '
            f'"{self.name}"')


class ParamBase(object):

    def __init__(self, c_param):
        self._c_param = c_param
        self._dyn_arrays_items = []
        self._dyn_array_count = None
        self._optional = False
        self._forced_boost_unqual_type = None
        self._is_boost_func_output = False
        self._gen_struct = None

    @property
    def _c_unqual_type(self):
        return self._c_param.type.unqual_name

    @property
    def _vk_is_pointer(self):
        return self._c_param.type.is_pointer

    @property
    def _vk_is_fixed_array(self):
        return self._c_param.type.is_fixed_array

    @property
    def _vk_is_struct(self):
        return self._c_param.type.is_struct

    @property
    def vk_unqual_type(self):
        raise VulkanBoostError(f'Not implemented for '
            f'{self._c_param.type.name} {self._c_param.name}')

    @property
    def _boost_unqual_type(self):
        return self._forced_boost_unqual_type or self.vk_unqual_type

    def set_dyn_array(self, count, items):
        if self._dyn_array_count is not None:
            assert self._dyn_array_count is count
        else:
            self._dyn_array_count = count
        assert_not_in(items, self._dyn_arrays_items)
        self._dyn_arrays_items.append(items)

    def set_optional(self, optional):
        self._optional = optional

    def force_boost_unqual_type(self, type_name):
        self._forced_boost_unqual_type = type_name

    def set_boost_func_output(self):
        self._is_boost_func_output = True

    def set_gen_struct(self, struct):
        self._gen_struct = struct

    @property
    def vk_is_dyn_array_count(self):
        return self is self._dyn_array_count

    @property
    def vk_is_dyn_array_items(self):
        return self in self._dyn_arrays_items

    @property
    def __dyn_array_items_mandatory(self):
        return [p for p in self._dyn_arrays_items if not p._optional]

    @property
    def __dyn_array_items_optional(self):
        return [p for p in self._dyn_arrays_items if p._optional]

    @property
    def _vk_type(self):
        t = self.vk_unqual_type
        if self._vk_is_fixed_array:
            t += f' [{self._c_param.type.fixed_array_size}]'
        elif self._vk_is_pointer:
            t += ' ?'
        return t

    @property
    def vk_name(self):
        return self._c_param.name

    @property
    def _boost_base_name(self):
        bname = vk_param_name_to_boost(self.vk_name)
        if self.vk_is_dyn_array_items:
            bname = deref_boost_ptr_name(bname)
        return bname

    @property
    def _boost_base_type(self):
        t = self._boost_unqual_type
        if self.vk_is_dyn_array_items:
            t = f'array<{t}>'
        elif self._vk_is_fixed_array:
            t += f' [{self._c_param.type.fixed_array_size}]'
        elif self._vk_is_pointer:
            t += ' ?'
        return t

    @property
    def _boost_func_param_name(self):
        bname = self._boost_base_name
        if self._vk_is_pointer and not self.vk_is_dyn_array_items:
            assert not self._optional
            bname = deref_boost_ptr_name(bname)
        return bname

    @property
    def _boost_func_param_type(self):
        btype = self._boost_base_type
        if self._vk_is_pointer and not self.vk_is_dyn_array_items:
            assert not self._optional
            btype = deref_das_type(btype)
        return btype

    @property
    def _boost_struct_field_name(self):
        return self._boost_base_name

    @property
    def _boost_struct_field_type(self):
        return self._boost_base_type

    def generate_boost_func_param_decl(self):
        if self.vk_is_dyn_array_count or self._is_boost_func_output:
            return []
        bname = self._boost_func_param_name
        btype = self._boost_func_param_type
        return [f'{bname} : {btype} = [[ {btype} ]];']

    def generate_boost_struct_field_decl(self):
        if self.vk_is_dyn_array_count:
            return []
        bname = self._boost_struct_field_name
        btype = self._boost_struct_field_type
        return [f'{bname} : {btype}']

    def generate_boost_struct_field_view_decl(self):
        return []

    def generate_boost_struct_view_create_init(self):
        bname = self._boost_struct_field_name
        vtype = self._vk_type
        if self.vk_is_dyn_array_count:
            first = ('boost_struct.' +
                self.__dyn_array_items_mandatory[0]._boost_func_param_name)
            lines = []
            for ar_items in self.__dyn_array_items_mandatory[1:]:
                cur = 'boost_struct.' + ar_items._boost_func_param_name
                lines += [f'assert(length({cur}) == length({first}))']
            for ar_items in self.__dyn_array_items_optional:
                cur = 'boost_struct.' + ar_items._boost_func_param_name
                lines += [f'assert(length({cur}) == 0 || '
                    f'length({cur}) == length({first}))']
            lines += [f'let vk_{bname} = {vtype}({first} |> length())']
            return lines
        if self.vk_is_dyn_array_items:
            adr = f'array_addr_unsafe(boost_struct.{bname})'
            if self._boost_unqual_type == self.vk_unqual_type:
                return [f'let vk_p_{bname} = {adr}']
            else:
                return [
                   f'var vk_p_{bname} : {vtype}',
                   f'unsafe',
                   f'    vk_p_{bname} = reinterpret<{vtype}>({adr})',
                ]
        return []

    def generate_boost_struct_view_create_field(self):
        bname = self._boost_struct_field_name
        vname = self.vk_name
        if self.vk_is_dyn_array_count:
            return [f'{vname} = vk_{bname},']
        if self.vk_is_dyn_array_items:
            return [f'{vname} = vk_p_{bname},']
        return [f'{vname} = boost_value_to_vk(boost_struct.{bname}),']

    def generate_boost_struct_view_destroy(self):
        return []

    def generate_boost_struct_v2b_vars(self):
        bname = self._boost_struct_field_name
        btype = self._boost_struct_field_type
        vname = self.vk_name
        if self.vk_is_dyn_array_items:
            vk_count = self._dyn_array_count.vk_name
            return [
               f'var b_{bname} : {btype}',
               # for optional arrays vk pointer can be null, but
               # counter can be non-zero because it is shared with other
               # array(s).
               f'if vk_struct.{vname} != null',
               f'    b_{bname} |> resize(int(vk_struct.{vk_count}))',
               f'    for b, i in b_{bname}, range(INT_MAX)',
               f'        unsafe',
               f'            b <- vk_value_to_boost(*(vk_struct.{vname}+i))',
            ]
        if self._vk_is_pointer:
            bdtype = deref_das_type(self._boost_struct_field_type)
            return [
               f'var b_{bname} = new {bdtype}',
               f'if vk_struct.{vname} != null',
               f'    (*b_{bname}) <- '
                     f'vk_value_to_boost(*(vk_struct.{vname}))',
            ]
        return []

    def generate_boost_struct_v2b_field(self):
        bname = self._boost_struct_field_name
        vname = self.vk_name
        if self.vk_is_dyn_array_count:
            return []
        if self.vk_is_dyn_array_items:
            return [f'{bname} <- b_{bname},']
        if self._vk_is_pointer:
            return [f'{bname} = b_{bname},']
        return [f'{bname} = vk_value_to_boost(vk_struct.{vname}),']

    def generate_boost_func_param_call(self):
        if self.vk_is_dyn_array_count or self._is_boost_func_output:
            return []
        return [f'{self._boost_func_param_name},']

    @property
    def is_dyn_array_output(self):
        if self.vk_is_dyn_array_items:
            assert_equal(len(self._dyn_arrays_items), 1)
            assert_is(self._dyn_arrays_items[0], self)
            return self._is_boost_func_output
        if self.vk_is_dyn_array_count:
            # There are cases when the count is shared between
            # output and non-output arrays, and hence must not be queried.
            # E.g. vkCreateGraphicsPipelines
            outputs = [x._is_boost_func_output for x in self._dyn_arrays_items]
            return self._is_boost_func_output or all(outputs)
        return False

    @property
    def boost_func_return_value(self):
        bname = self._boost_func_param_name
        if self.vk_is_dyn_array_items:
            return f'<- [{{for x in vk_{bname}; vk_value_to_boost(x)}}]'
        if self._vk_is_pointer:
            return f'vk_value_to_boost(vk_{bname})'
        raise Exception('Return type not supported: {self.vk_name}')

    def generate_boost_func_temp_vars_init(self):
        if self.vk_is_dyn_array_count:
            vtype = self.vk_unqual_type
            if self.is_dyn_array_output:
                return [f'var vk_{self.vk_name} : {vtype}']
            lines = []
            first = self._dyn_arrays_items[0]._boost_func_param_name
            for ar_items in self._dyn_arrays_items[1:]:
                cur = ar_items._boost_func_param_name
                lines += [f'assert(length({first}) == length({cur}))']
            lines += [f'let vk_{self.vk_name} = {vtype}({first} |> length())']
            return lines
        if self.vk_is_dyn_array_items:
            bname = self._boost_func_param_name
            vtype = self.vk_unqual_type
            lines = [
                f'var vk_{bname} : array<{vtype}>',
                f'defer() <| ${{ delete vk_{bname}; }}',
            ]
            if not self._is_boost_func_output:
                lines += [
                    f'vk_{bname} <- [{{ '
                        f'for item in {bname} ; boost_value_to_vk({bname}) }}]'
                ]
            return lines
        if self._vk_is_pointer:
            #TODO: add null support if needed via declare_can_be_null
            bname = self._boost_func_param_name
            vtype = self.vk_unqual_type
            lines = [f'var vk_{bname} : {vtype}']
            if not self._is_boost_func_output:
                lines += [f'vk_{bname} <- boost_value_to_vk({bname})']
            return lines
        return []

    def generate_boost_func_temp_vars_update(self):
        if self.vk_is_dyn_array_items and self._is_boost_func_output:
            bname = self._boost_func_param_name
            vtype = self.vk_unqual_type
            vcname = self._dyn_array_count.vk_name
            return [f'vk_{bname} |> resize(int(vk_{vcname}))']
        return []

    def generate_boost_handle_field(self):
        return []

    def generate_boost_handle_ctor_init_field(self):
        return []

    def get_boost_dtor_call_param(self, boost_handle_type_name):
        raise Exception(f'Should not be here. {self.__class__.__name__}, '
            f'{self._c_param.type.name} {self._c_param.name}')

    @property
    def boost_func_query_array_size_param(self):
        bname = self._boost_func_param_name
        if self.vk_is_dyn_array_items:
            if self._is_boost_func_output:
                return f'[[ {self.vk_unqual_type} ? ]]'
            else:
                return f'array_addr_unsafe(vk_{bname})'
        return self.boost_func_call_vk_param

    @property
    def boost_func_call_vk_param(self):
        bname = self._boost_func_param_name
        if self.vk_is_dyn_array_count:
            if self.is_dyn_array_output:
                return f'safe_addr(vk_{self.vk_name})'
            else:
                return f'vk_{self.vk_name}'
        elif self.vk_is_dyn_array_items:
            return f'array_addr_unsafe(vk_{bname})'
        elif self._vk_is_pointer:
            return f'safe_addr(vk_{bname})'
        return f'boost_value_to_vk({bname})'


class ParamVk_pAllocator(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if (c_param.name == 'pAllocator'
        and c_param.type.name == 'const VkAllocationCallbacks *'
        ):
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return self._c_unqual_type

    def generate_boost_func_param_decl(self):
        return []

    def generate_boost_func_param_call(self):
        return []

    def generate_boost_func_temp_vars_init(self):
        return []

    def generate_boost_handle_field(self):
        return []

    def generate_boost_handle_ctor_init_field(self):
        return []

    @property
    def boost_func_call_vk_param(self):
        return 'null'

    def get_boost_dtor_call_param(self, boost_handle_type_name):
        return []


class ParamVk_pNext(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if c_param.name == 'pNext':
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return self._c_unqual_type

    def generate_boost_struct_field_decl(self):
        return []

    def generate_boost_struct_v2b_field(self):
        return []

    def generate_boost_struct_v2b_vars(self):
        return []

    def generate_boost_struct_view_create_init(self):
        return []

    def generate_boost_struct_view_create_field(self):
        return []


class ParamVk_sType(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if c_param.name == 'sType':
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return self._c_unqual_type

    def generate_boost_struct_field_decl(self):
        return []

    def generate_boost_struct_v2b_field(self):
        return []

    def generate_boost_struct_view_create_init(self):
        return []

    def generate_boost_struct_view_create_field(self):
        stype = 'VK_STRUCTURE_TYPE_' + (
            boost_camel_to_lower(self._gen_struct.boost_type_name).upper())
        return [f'{self.vk_name} = VkStructureType {stype},']


class ParamVkHandleBase(ParamBase):

    @property
    def _boost_unqual_type(self):
        return vk_handle_type_to_boost(self.vk_unqual_type)

    def generate_boost_handle_field(self):
        return [f'_{self._boost_func_param_name} : {self.vk_unqual_type}']

    def generate_boost_handle_ctor_init_field(self):
        bname = self._boost_func_param_name
        return [f'handle._{bname} <- boost_value_to_vk({bname})']

    def get_boost_dtor_call_param(self, boost_handle_type_name):
        field = self._boost_func_param_name
        if self._boost_unqual_type == boost_handle_type_name:
            field = boost_handle_attr_name(boost_handle_type_name)
        else:
            field = '_' + field
        return [f'vk_value_to_boost(handle.{field}),']

    def generate_boost_struct_field_view_decl(self):
        bname = self._boost_struct_field_name
        vutype = self.vk_unqual_type
        if self.vk_is_dyn_array_items:
            return [f'_vk_view_{bname} : array<{vutype}>']
        return []

    def generate_boost_struct_view_create_init(self):
        bname = self._boost_struct_field_name
        if self.vk_is_dyn_array_items:
            return [
               f'boost_struct._vk_view_{bname} <- [{{',
               f'    for item in boost_struct.{bname} ;',
               f'    item |> boost_value_to_vk()}}]',
            ]
        return []

    def generate_boost_struct_view_create_field(self):
        bname = self._boost_struct_field_name
        vname = self.vk_name
        if self.vk_is_dyn_array_items:
            return [f'{vname} = array_addr_unsafe('
                f'boost_struct._vk_view_{bname}),']
        return super(ParamVkHandleBase, self
            ).generate_boost_struct_view_create_field()

    def generate_boost_struct_view_destroy(self):
        bname = self._boost_struct_field_name
        if self.vk_is_dyn_array_items:
            return [f'delete boost_struct._vk_view_{bname}']
        return []


class ParamVkHandle(ParamVkHandleBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        c_type = c_param.type
        if (c_type.unqual_name.startswith('Vk')
        and c_type.unqual_name.endswith('_T')
        and c_type.is_pointer):
            return cls(c_param=c_param, **kwargs)

    @property
    def _vk_is_pointer(self):
        return False

    @property
    def vk_unqual_type(self):
        ct = self._c_unqual_type
        assert_ends_with(ct, '_T')
        return ct[:-2]


class ParamVkHandlePtr(ParamVkHandleBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        c_type = c_param.type
        generator = c_param._generator
        if (f'{c_type.unqual_name}_T' in generator.opaque_structs
        and c_type.is_pointer):
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return self._c_unqual_type


class ParamVkStruct(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        c_type = c_param.type
        if (c_type.is_struct and c_type.unqual_name.startswith('Vk')):
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return self._c_unqual_type

    @property
    def _boost_unqual_type(self):
        return vk_struct_type_to_boost(self.vk_unqual_type)

    @property
    def boost_func_return_value(self):
        bname = self._boost_func_param_name
        if self._vk_is_pointer and not self.vk_is_dyn_array_items:
            return f'<- vk_value_to_boost(vk_{bname})'
        return super(ParamVkStruct, self).boost_func_return_value

    def generate_boost_func_param_decl(self):
        if self.vk_is_dyn_array_count or self._is_boost_func_output:
            return []
        bname = self._boost_func_param_name
        btype = self._boost_func_param_type
        return [f'var {bname} : {btype} = [[ {btype} ]];']

    def generate_boost_func_temp_vars_init(self):
        bname = self._boost_func_param_name
        if not self._is_boost_func_output:
            if self.vk_is_dyn_array_items:
                return [
                    f'var vk_{bname} <- [{{ for item in {bname} ;',
                    f'    item |> vk_view_create_unsafe() }}]',
                    f'defer() <|',
                    f'    for item in {bname}',
                    f'        item |> vk_view_destroy()',
                    f'    delete vk_{bname}',
                ]
            elif self._vk_is_pointer:
                return [
                    f'var vk_{bname} <- {bname} |> vk_view_create_unsafe()',
                    f'defer() <| ${{ {bname} |> vk_view_destroy(); }}',
                ]
        return super(ParamVkStruct, self).generate_boost_func_temp_vars_init()

    def generate_boost_struct_field_view_decl(self):
        bname = self._boost_struct_field_name
        vutype = self.vk_unqual_type
        if self.vk_is_dyn_array_items:
            return [f'_vk_view_{bname} : array<{vutype}>']
        if self._vk_is_pointer:
            return [f'_vk_view_{bname} : {vutype} ?']
        return [f'_vk_view_p_{bname} : {vutype} ?']

    def generate_boost_struct_view_create_init(self):
        bname = self._boost_struct_field_name
        vutype = self.vk_unqual_type
        if self.vk_is_dyn_array_items:
            return [
               f'boost_struct._vk_view_{bname} <- [{{',
               f'    for item in boost_struct.{bname} ;',
               f'    item |> vk_view_create_unsafe()}}]',
            ]
        if self._vk_is_pointer:
            return [
               f'if boost_struct.{bname} != null',
               f'    boost_struct._vk_view_{bname} = new {vutype}',
               f'    *(boost_struct._vk_view_{bname}) <- (',
               f'        *(boost_struct.{bname}) |> '
                                f'vk_view_create_unsafe())',
            ]
        return [
           f'boost_struct._vk_view_p_{bname} = new {vutype}',
           f'*(boost_struct._vk_view_p_{bname}) <- (',
           f'    boost_struct.{bname} |> vk_view_create_unsafe())',
        ]

    def generate_boost_struct_view_create_field(self):
        bname = self._boost_struct_field_name
        vname = self.vk_name
        if self.vk_is_dyn_array_items:
            return [f'{vname} = array_addr_unsafe('
                f'boost_struct._vk_view_{bname}),']
        if self._vk_is_pointer:
            return [f'{vname} = boost_struct._vk_view_{bname},']
        return [f'{vname} = *(boost_struct._vk_view_p_{bname}),']

    def generate_boost_struct_view_destroy(self):
        bname = self._boost_struct_field_name
        if self.vk_is_dyn_array_items:
            return [
               f'for item in boost_struct.{bname}',
               f'    item |> vk_view_destroy()',
               f'delete boost_struct._vk_view_{bname}',
            ]
        if self._vk_is_pointer:
            return [
               f'if boost_struct.{bname} != null',
               f'    *(boost_struct.{bname}) |> vk_view_destroy()',
               f'    unsafe',
               f'        delete boost_struct._vk_view_{bname}',
            ]
        return [
           f'boost_struct.{bname} |> vk_view_destroy()',
           f'unsafe',
           f'    delete boost_struct._vk_view_p_{bname}',
        ]

    def generate_boost_struct_v2b_field(self):
        bname = self._boost_struct_field_name
        vname = self.vk_name
        if (not self.vk_is_dyn_array_items and not self.vk_is_dyn_array_count
        and not self._vk_is_pointer):
            return [f'{bname} <- vk_value_to_boost(vk_struct.{vname}),']
        return super(ParamVkStruct, self).generate_boost_struct_v2b_field()


class ParamVkEnum(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        c_type = c_param.type
        if c_type.is_enum and c_type.unqual_name.startswith('Vk'):
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return self._c_unqual_type


class ParamFixedString(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        c_type = c_param.type
        if c_type.unqual_name == 'char' and c_type.is_fixed_array:
            return cls(c_param=c_param, **kwargs)

    @property
    def _vk_is_fixed_array(self):
        return False

    @property
    def vk_unqual_type(self):
        return 'string'


class ParamString(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if c_param.type.name == 'const char *':
            return cls(c_param=c_param, **kwargs)

    @property
    def _vk_is_pointer(self):
        return False

    @property
    def vk_unqual_type(self):
        return 'string'

    @property
    def _boost_base_name(self):
        name = vk_param_name_to_boost(self.vk_name)
        if name.startswith('p_'):
            name = name[2:]
        return name


class ParamStringPtr(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if c_param.type.name == 'const char *const *':
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return 'string'

    @property
    def _boost_base_name(self):
        name = vk_param_name_to_boost(self.vk_name)
        if name.startswith('pp_'):
            name = name[1:]
        return name


class ParamFloat(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if c_param.type.unqual_name == 'float':
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return 'float'


class ParamInt32(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if c_param.type.unqual_name == 'int':
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return 'int'


class ParamUInt8(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if c_param.type.unqual_name == 'uint8_t':
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return 'uint8'


class ParamUInt32(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if c_param.type.unqual_name in [
            'unsigned int', 'uint32_t',
        ]:
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return 'uint'


class ParamUInt64(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if c_param.type.unqual_name in [
            'unsigned long long', 'unsigned long',
        ]:
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return 'uint64'


class ParamVkBool32(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if c_param.type.unqual_name == 'VkBool32':
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return 'uint'


class ParamVoidPtr(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if c_param.type.name == 'const void *':
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return 'void'


class ParamUnknown(ParamBase):

    @classmethod
    def maybe_create(cls, **kwargs):
        return cls(**kwargs)

    @property
    def _c_unqual_type(self):
        raise self.__unknown_param_error

    @property
    def vk_unqual_type(self):
        raise self.__unknown_param_error

    @property
    def _vk_type(self):
        raise self.__unknown_param_error

    @property
    def __unknown_param_error(self):
        return VulkanBoostError(f'Unknown param "{self._c_param.name}" '
            f'of type "{self._c_param.type.name}".')


def boost_camel_to_lower(camel):
    result = ''
    for force_sep_after in ['2D', '3D', '4D']:
        camel = camel.replace(force_sep_after, force_sep_after + '_')
    state = None
    for c in camel:
        if c.islower():
            state = 'lower'
        if c.isupper() and state == 'lower':
            state = 'upper'
            if result and result[-1] != '_':
                result += '_'
        if c.isdigit() and state == 'lower':
            state = 'digit'
            if result and result[-1] != '_':
                result += '_'
        result += c.lower()
    while result[-1] == '_':
        result = result[:-1]
    return result

def returns_vk_result(func):
    return get_c_func_return_type(func.type) == 'VkResult'

def get_c_func_return_type(func_type):
    return re.match(r'^([^(]+) \(.*', func_type).group(1).strip()

def deref_das_type(type_name):
    assert_ends_with(type_name, '?')
    return type_name[:-1].strip()

def deref_boost_ptr_name(name):
    assert_starts_with(name, 'p_')
    return name[2:]

def vk_struct_type_to_boost(vk_type):
    assert_starts_with(vk_type, 'Vk')
    return vk_type[2:]

def vk_handle_type_to_boost(vk_type):
    return vk_struct_type_to_boost(vk_type)

def vk_handle_type_to_vk_dtor(vk_type):
    assert_starts_with(vk_type, 'Vk')
    handle = vk_type[2:]
    return f'vkDestroy{handle}'

def vk_handle_type_to_vk_ctor(vk_type):
    assert_starts_with(vk_type, 'Vk')
    handle = vk_type[2:]
    return f'vkCreate{handle}'

def boost_handle_attr_name(boost_handle_type_name):
    return boost_camel_to_lower(boost_handle_type_name)

def vk_param_name_to_boost(vk_name):
    return boost_camel_to_lower(vk_name)

def vk_func_name_to_boost(vk_name):
    assert_starts_with(vk_name, 'vk')
    return boost_camel_to_lower(vk_name[2:])

def boost_ptr_type_to_array(type_):
    return f'array<{deref_das_type(type_)}>'

def boost_ptr_name_to_array(name):
    return name[2:] if name.startswith('p_') else name

def remove_last_char(lines, char):
    if lines[-1].endswith(char):
        lines[-1] = lines[-1][:-1]
