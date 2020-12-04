from das_shared.object_base import LoggingObject
from das_shared.op_sys import full_path, write_to_file
from das_shared.assertions import assert_starts_with, assert_ends_with
from os import path
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
        self.__gen_query_array_funcs = []

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

    def add_gen_query_array_func(self, **kwargs):
        func = GenQueryArrayFunc(generator=self, **kwargs)
        self.__gen_query_array_funcs.append(func)
        return func

    def get_func_params(self, c_func):
        return map(self.get_param_from_node, c_func.params)

    def get_struct_fields(self, c_struct):
        return map(self.get_param_from_node, c_struct.fields)

    def get_param(self, c_name, c_type):
        for param_class in [
            ParamVkHandle,
            ParamVkHandlePtr,
            ParamVkStruct,
            ParamVkStructPtr,
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
            ParamUnknown,
        ]:
            param = param_class.maybe_create(
                c_param=C_Param(c_name=c_name, c_type=c_type,
                    generator=self))
            if param:
                return param

    def get_param_from_node(self, c_node):
        return self.get_param(c_node.name, c_node.type)

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
                self.__gen_query_funcs,
                self.__gen_query_array_funcs,
                self.__gen_structs,
                self.__gen_handles,
            ] for item in items for line in item.generate()
        ] 

    def __preamble(self):
        fpath = path.join(path.dirname(__file__), 'boost_preamble.das')
        with open(fpath, 'r') as f:
            return f.read()


class GenQueryFunc(object):

    def __init__(self, generator, func, p_output):
        self.__generator = generator
        self.__vk_func_name = func
        self.__p_output = p_output

    @property
    def __boost_func_name(self):
        return vk_func_name_to_boost(self.__vk_func_name)

    @property
    def __params(self):
        return self.__generator.get_func_params(self.__c_func)

    @property
    def __output_param(self):
        for param in self.__params:
            if param.vk_name == self.__p_output:
                return param

    @property
    def __c_func(self):
        return self.__generator.functions[self.__vk_func_name]

    @property
    def __returns_vk_result(self):
        return returns_vk_result(self.__c_func)

    def generate(self):
        lines = []
        lines += [
            '',
           f'def {self.__boost_func_name}('
        ]
        for param in self.__params:
            if param.vk_name == self.__p_output:
                continue
            bname = param.boost_name
            btype = param.boost_type
            lines.append(f'    {bname} : {btype} = [[ {btype} ]];')
        if self.__returns_vk_result:
            lines.append(f'    var result : VkResult? = [[VkResult?]];')
        remove_last_char(lines, ';')

        boost_type_deref = deref_das_type(self.__output_param.boost_type)
        vk_type_deref = deref_das_type(self.__output_param.vk_type)
        lines += [
           f') : {boost_type_deref}',
           f'    var vk_output : {vk_type_deref}',
        ]

        if self.__returns_vk_result:
            lines.append(f'    var result_ = VkResult VK_SUCCESS')
        maybe_capture_result = ('result ?? result_ = '
            if self.__returns_vk_result else '')
        lines += [
           f'    {maybe_capture_result}{self.__vk_func_name}(',
        ]

        for param in self.__params:
            if param.vk_name == self.__p_output:
                vk_value = 'safe_addr(vk_output)'
            else:
                vk_value = param.boost_value_to_vk(param.boost_name)
            lines.append(f'        {vk_value},')
        remove_last_char(lines, ',')

        lines += [
           f'    )',
        ]
        if self.__returns_vk_result:
            lines.append('    assert(result_ == VkResult VK_SUCCESS)')
        
        ret_op = '<- ' if self.__output_param.is_struct else ''
        lines += [
           f'    return {ret_op}vk_value_to_boost(vk_output)',
        ]
        return lines


class GenQueryArrayFunc(object):

    def __init__(self, generator, func, p_count, p_items):
        self.__generator = generator
        self.__vk_func_name = func
        self.__p_count = p_count
        self.__p_items = p_items

    @property
    def __boost_func_name(self):
        return vk_func_name_to_boost(self.__vk_func_name)

    @property
    def __params(self):
        return self.__generator.get_func_params(self.__c_func)

    @property
    def __items_param(self):
        for param in self.__params:
            if param.vk_name == self.__p_items:
                return param

    @property
    def __count_param(self):
        for param in self.__params:
            if param.vk_name == self.__p_count:
                return param

    @property
    def __c_func(self):
        return self.__generator.functions[self.__vk_func_name]

    @property
    def __returns_vk_result(self):
        return returns_vk_result(self.__c_func)

    def generate(self):
        lines = []
        lines += [
            '',
           f'def {self.__boost_func_name}('
        ]
        for param in self.__params:
            if param.vk_name in [self.__p_items, self.__p_count]:
                continue
            bname = param.boost_name
            btype = param.boost_type
            lines.append(f'    {bname} : {btype} = [[ {btype} ]];')
        if self.__returns_vk_result:
            lines.append(f'    var result : VkResult? = [[VkResult?]];')
        remove_last_char(lines, ';')

        boost_type_deref = deref_das_type(self.__items_param.boost_type)
        vk_type_deref = deref_das_type(self.__items_param.vk_type)
        lines += [
           f') : array<{boost_type_deref}>',
           f'    var count : uint',
        ]

        maybe_capture_result = ('result ?? result_ = '
            if self.__returns_vk_result else '')

        if self.__returns_vk_result:
            lines.append(f'    var result_ = VkResult VK_SUCCESS')
        lines += [
           f'    {maybe_capture_result}{self.__vk_func_name}(',
        ]

        for param in self.__params:
            if param.vk_name == self.__p_items:
                vk_value = 'null'
            elif param.vk_name == self.__p_count:
                vk_value = 'safe_addr(count)'
            else:
                vk_value = param.boost_value_to_vk(param.boost_name)
            lines.append(f'        {vk_value},')
        remove_last_char(lines, ',')

        lines += [
           f'    )',
        ]
        if self.__returns_vk_result:
            lines += [
                '',
                '    assert(result_ == VkResult VK_SUCCESS)',
                '    if result ?? result_ != VkResult VK_SUCCESS',
               f'        return <- [[array<{boost_type_deref}>]]',
            ]
        lines += [
            '',
           f'    var vk_items : array<{vk_type_deref}>',
            '    defer() <| ${ delete vk_items; }',
            '    vk_items |> resize(int(count))',
            '    vk_items |> lock_data() <| $(vk_p_items, count_)',
           f'        {maybe_capture_result}{self.__vk_func_name}(',
        ]

        for param in self.__params:
            if param.vk_name == self.__p_items:
                vk_value = 'vk_p_items'
            elif param.vk_name == self.__p_count:
                vk_value = 'safe_addr(count)'
            else:
                vk_value = param.boost_value_to_vk(param.boost_name)
            lines.append(f'            {vk_value},')
        remove_last_char(lines, ',')

        lines += [
           f'        )',
        ]
        if self.__returns_vk_result:
            lines.append('        assert(result_ == VkResult VK_SUCCESS)')
        lines += [
            '',
            '    return <- [{for item in vk_items ; vk_value_to_boost(item)}]',
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
    def __c_struct(self):
        return self.__generator.structs[self.__vk_type_name]

    @property
    def __fields(self):
        return self.__generator.get_struct_fields(self.__c_struct)

    @property
    def __boost_type_name(self):
        return vk_struct_type_to_boost(self.__vk_type_name)

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
            boost_camel_to_lower(self.__boost_type_name).upper())

    def __get_array(self, vk_items_name):
        for array in self.__arrays:
            if vk_items_name == array.vk_items_name:
                return array

    def generate(self):
        lines = []
        lines += [
            '',
            '//',
           f'// {self.__boost_type_name}',
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
           f'struct {self.__boost_type_name}',
        ]
        for field in self.__fields:
            if self.__is_array_count(field.vk_name):
                continue
            if field.vk_name in ['sType', 'pNext']:
                continue
            boost_name = field.boost_name
            boost_type = field.boost_type
            if self.__is_array_items(field.vk_name):
                boost_name = boost_ptr_name_to_array(boost_name)
                boost_type = boost_ptr_type_to_array(boost_type)
            lines += [f'    {boost_name} : {boost_type}']
        return lines

    def __generate_vk_to_boost(self):
        lines = []
        lines += [
            '',
           f'def vk_value_to_boost(vk_struct : {self.__vk_type_name}) '
                f': {self.__boost_type_name}',
           f'    return <- [[{self.__boost_type_name}'
        ]
        for field in self.__fields:
            if field.vk_name in ['sType', 'pNext']:
                continue
            assign_op = field.vk_to_boost_assign_op
            boost_name = field.boost_name
            boost_value = field.vk_value_to_boost(
                f'vk_struct.{field.vk_name}')
            lines += [f'        {boost_name} {assign_op} {boost_value},']
        remove_last_char(lines, ',')
        lines += [
            '    ]]'
        ]
        return lines

    def __generate_boost_to_vk(self):
        bstype = self.__boost_type_name
        vstype = self.__vk_type_name
        lines = []
        lines += [
            '',
            '[unsafe]',
           f'def vk_view_create(boost_struct : {bstype}) : {vstype}',
            '    assert(!boost_struct._vk_view_active)',
            '    boost_struct._vk_view_active = true',
            '',
           f'    var vk_struct : [[ {vstype} ]]',
        ]
        for field in self.__fields:
            bname, vname = field.boost_name, field.vk_name
            btype, vtype = field.boost_type, field.vk_type
            if vname in ['pNext']:
                continue
            elif vname == 'sType':
                stype = self.__vk_structure_type
                lines += [
                   f'    vk_struct.sType = VkStructureType {stype}'
                ]
            elif self.__is_array_count(vname):
                lines += [
                   f'    vk_struct.{vname} = '
                       f'uint(boost_struct.{bname} |> length())'
                ]
            elif self.__is_array_items(vname):
                biname = boost_ptr_name_to_array(field.boost_name)
                if field.needs_view:
                    lines += [
                       f'    boost_struct._vk_view_{biname} <- '
                           f'[{{for item in boost_struct.{biname} ; '
                               f'item |> vk_view_create()}}]',
                        '    unsafe',
                       f'        vk_struct.{vname} = array_addr('
                                    f'boost_struct._vk_view_{biname})',
                    ]
                else:
                    lines += [
                        '    unsafe',
                       f'        vk_struct.{vname} = array_addr('
                                    f'boost_struct.{biname})',
                    ]
            elif field.is_pointer:
                pass
            else:
                vk_value = field.boost_value_to_vk(f'boost_struct.{bname}')
            lines.append(f'    vk_struct.{field.vk_name} = {vk_value}')

        lines += [
            '',
            'def with_view(',
           f'    boost_struct : {btype};',
           f'    b : block<(vk_struct : {vtype})>',
            ') {',
        ]

        depth = 0
        for field in self.__fields:
            if field.vk_name in ['sType', 'pNext']:
                continue
            if self.__is_array_count(field.vk_name):
                continue
            elif self.__is_array_items(field.vk_name):
                depth += 1
                ar = self.__get_array(field.vk_name)
                items_name = boost_ptr_name_to_array(field.boost_name)
                count_name = vk_param_name_to_boost(ar.vk_count_name)
                lines += [
                   f'    boost_struct.{items_name} |> lock_data() <| $(',
                   f'        vk_p_{items_name}, vk_{count_name}',
                    '    ) {',
                ]
            elif field.needs_vk_view:
                depth += 1
                boost_name = field.boost_name
                lines += [
                   f'    boost_struct.{boost_name} |> with_p_view() <| $(',
                   f'        vk_{boost_name} : {field.vk_view_type}',
                    '    ) {',
                ]

        lines += [
           f'    let vk_struct <- [[ {self.__vk_type_name}',
        ]

        for field in self.__fields:
            if field.vk_name in ['pNext']:
                continue
            elif field.vk_name == 'sType':
                vk_value = f'VkStructureType {self.__vk_structure_type}'
            elif self.__is_array_count(field.vk_name):
                vk_value = f'uint(vk_{field.boost_name})'
            elif self.__is_array_items(field.vk_name):
                items_name = boost_ptr_name_to_array(field.boost_name)
                vk_value = f'vk_p_{items_name}' 
            elif field.needs_vk_view:
                vk_value = f'vk_{field.boost_name}'
            else:
                vk_value = field.boost_value_to_vk(
                    f'boost_struct.{field.boost_name}')
            lines.append(f'        {field.vk_name} = {vk_value},')
        remove_last_char(lines, ',')
        lines += [
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
        self.__vk_handle_type_name = handle
        self.__vk_enumerator_name = enumerator
        self.__vk_ctor_name = ctor
        self.__vk_dtor_name = dtor
        self.__vk_p_count = p_count
        self.__vk_p_handles = p_handles
        self.__vk_p_create_info = p_create_info

    @property
    def __c_enumerator(self):
        return self.__generator.functions[self.__vk_enumerator_name]

    @property
    def __c_ctor(self):
        return self.__generator.functions[self.__vk_ctor_name]

    @property
    def __c_dtor(self):
        return self.__generator.functions[self.__vk_dtor_name]

    @property
    def __vk_enumerator_params(self):
        return self.__generator.get_func_params(self.__c_enumerator)

    @property
    def __vk_ctor_params(self):
        return self.__generator.get_func_params(self.__c_ctor)

    @property
    def __vk_dtor_params(self):
        return self.__generator.get_func_params(self.__c_dtor)

    @property
    def __is_batched(self):
        return self.__vk_p_count is not None

    @property
    def __boost_handle_type_name(self):
        return vk_handle_type_to_boost(self.__vk_handle_type_name)

    @property
    def __boost_handle_attr(self):
        return boost_handle_attr_name(self.__boost_handle_type_name)

    @property
    def __boost_handle_batch_type_name(self):
        return self.__boost_handle_type_name + 'Batch'

    @property
    def __boost_handle_batch_attr(self):
        return self.__boost_handle_attr + '_batch'

    @property
    def __boost_enumerator_name(self):
        return vk_func_name_to_boost(self.__vk_enumerator_name)

    @property
    def __boost_ctor_name(self):
        return vk_func_name_to_boost(self.__vk_ctor_name)

    @property
    def __boost_p_create_info(self):
        param = vk_param_name_to_boost(self.__vk_p_create_info)
        assert_starts_with(param, 'p_')
        return param[2:]

    def generate(self):
        lines = []
        lines += [
            '',
            '//',
           f'// {self.__boost_handle_type_name}',
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
        btype = self.__boost_handle_type_name
        vtype = self.__vk_handle_type_name
        attr = self.__boost_handle_attr
        return [
            '',
           f'struct {btype}',
           f'    {attr} : {vtype}',
            '',
           f'def boost_value_to_vk(b : {btype}) : {vtype}',
           f'    return b.{attr}',
        ]

    def __generate_batched_type(self):
        batch_attr = self.__boost_handle_batch_attr
        batch_type = self.__boost_handle_batch_type_name
        single_attr = self.__boost_handle_attr
        single_type = self.__boost_handle_type_name
        vk_type = self.__vk_handle_type_name
        return [
            '',
           f'struct {batch_type}',
           f'    {batch_attr} : array<{vk_type}>',
            '',
           f'def split(batch : {batch_type}) : array<{single_type}>',
           f'    return <- [{{for h in batch.{batch_attr} ;',
           f'        [[{single_type} {single_attr}=h]]}}]',
        ]

    def __generate_enumerator_batched(self):
        batch_attr = self.__boost_handle_batch_attr
        batch_type = self.__boost_handle_batch_type_name
        lines = []
        lines += [
            '',
           f'def {self.__boost_enumerator_name}(']
        for param in self.__vk_enumerator_params:
            if param.vk_name in [self.__vk_p_count, self.__vk_p_handles]:
                continue
            lines += [
               f'    {param.boost_name} : {param.boost_type};',
            ]
        lines += [
           f'    var result : VkResult? = [[VkResult?]]',
           f') : {self.__boost_handle_batch_type_name}',
            '',
           f'    var count : uint',
           f'    var result_ = VkResult VK_SUCCESS',
            '',
           f'    result ?? result_ = {self.__vk_enumerator_name}('
        ]

        for param in self.__vk_enumerator_params:
            if param.vk_name == self.__vk_p_count:
                vk_value = 'safe_addr(count)'
            elif param.vk_name == self.__vk_p_handles:
                vk_value = 'null'
            else:
                vk_value = param.boost_value_to_vk(param.boost_name)
            lines.append(f'        {vk_value},')
        remove_last_char(lines, ',')

        lines += [
            '    )',
           f'    assert(result_ == VkResult VK_SUCCESS)',
            '',
           f'    var vk_handles : array<{self.__vk_handle_type_name}>',
           f'    if result ?? result_ == VkResult VK_SUCCESS && count > 0u',
           f'        vk_handles |> resize(int(count))',
           f'        vk_handles |> lock() <| $(thandles)',
           f'            result ?? result_ = {self.__vk_enumerator_name}(',
        ]

        for param in self.__vk_enumerator_params:
            if param.vk_name == self.__vk_p_count:
                vk_value = 'safe_addr(count)'
            elif param.vk_name == self.__vk_p_handles:
                vk_value = 'addr(thandles[0])'
            else:
                vk_value = param.boost_value_to_vk(param.boost_name)
            lines.append(f'                {vk_value},')
        remove_last_char(lines, ',')

        lines += [
           f'            )',
           f'            assert(result_ == VkResult VK_SUCCESS)',
            '',
           f'    return <- [[{batch_type} {batch_attr} <- vk_handles]]',
        ]
        return lines

    def __generate_enumerator_not_batched(self):
        lines = []
        lines += [
            '',
           f'def {self.__boost_enumerator_name}_no_batch(',
        ]
        for param in self.__vk_enumerator_params:
            if param.vk_name in [self.__vk_p_count, self.__vk_p_handles]:
                continue
            lines += [
               f'    {param.boost_name} : {param.boost_type};',
            ]
        lines += [
           f'    var result : VkResult? = [[VkResult?]]',
           f'): array<{self.__boost_handle_type_name}>',
        ]
        params = []
        for param in self.__vk_enumerator_params:
            if param.vk_name in [self.__vk_p_count, self.__vk_p_handles]:
                continue
            params.append(param.boost_name)
        params_text = ', '.join(params + ['result'])
        lines += [
           f'    var handles <- {self.__boost_enumerator_name}({params_text})',
            '    defer() <| ${ delete handles; }',
           f'    return <- handles |> split()',
        ]
        return lines

    def __generate_ctor(self):
        if self.__vk_ctor_name == None:
            return []
        bh_attr = self.__boost_handle_attr
        bh_type = self.__boost_handle_type_name

        lines = []
        lines += [
            '',
           f'def {self.__boost_ctor_name}(']

        for param in self.__vk_ctor_params:
            if param.vk_name == 'pAllocator':
                continue
            elif param.vk_type == f'{self.__vk_handle_type_name} ?':
                continue
            elif param.vk_name == self.__vk_p_create_info:
                boost_name = self.__boost_p_create_info
                boost_type = deref_das_type(param.boost_type)
            else:
                boost_name = param.boost_name
                boost_type = param.boost_type
            lines += [f'    {boost_name} : {boost_type} = [[ {boost_type} ]];']

        lines += [
           f'    var result : VkResult? = [[VkResult?]]',
           f') : {bh_type}',
            '',
           f'    var {bh_attr} : {bh_type}',
           f'    {self.__boost_p_create_info} |> with_view() <| $(vk_info)',
           f'        var result_ = VkResult VK_SUCCESS',
           f'        result ?? result_ = {self.__vk_ctor_name}(',
        ]

        for param in self.__vk_ctor_params:
            if param.vk_name == self.__vk_p_create_info:
                vk_value = 'safe_addr(vk_info)'
            elif param.vk_type == f'{self.__vk_handle_type_name} ?':
                vk_value = f'safe_addr({bh_attr}.{bh_attr})'
            elif param.vk_name == 'pAllocator':
                vk_value = 'null'
            else:
                vk_value = param.boost_value_to_vk(param.boost_name)
            lines.append(f'            {vk_value},')
        remove_last_char(lines, ',')

        lines += [
           f'        )',
           f'        assert(result_ == VkResult VK_SUCCESS)',
           f'    return <- {bh_attr}',
        ]
        return lines

    def __generate_dtor(self):
        if self.__vk_dtor_name == None:
            return []
        bh_attr = self.__boost_handle_attr
        bh_type = self.__boost_handle_type_name
        lines = []
        lines += [
            '',
           f'def finalize(var {bh_attr} : {bh_type})',
           f'    {self.__vk_dtor_name}(',
        ]
        for param in self.__vk_dtor_params:
            if param.vk_name == 'pAllocator':
                vk_value = 'null'
            elif param.boost_type == bh_type:
                vk_value = param.boost_value_to_vk(bh_attr)
            else:
                raise Exception('handle extra params if needed')
            lines.append(f'        {vk_value},')
        remove_last_char(lines, ',')
        lines += [
            '    )',
           f'    memzero({bh_attr})',
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

    @property
    def c_unqual_type(self):
        return self._c_param.type.unqual_name

    @property
    def is_pointer(self):
        return self._c_param.type.is_pointer

    @property
    def is_fixed_array(self):
        return self._c_param.type.is_fixed_array

    @property
    def is_struct(self):
        return self._c_param.type.is_struct

    @property
    def vk_unqual_type(self):
        raise NotImplementedError()

    @property
    def boost_unqual_type(self):
        return self.vk_unqual_type

    @property
    def vk_type(self):
        return self.__make_qual_das_type(self.vk_unqual_type)

    @property
    def boost_type(self):
        return self.__make_qual_das_type(self.boost_unqual_type)

    @property
    def vk_name(self):
        return self._c_param.name

    @property
    def boost_name(self):
        return vk_param_name_to_boost(self.vk_name)

    @property
    def vk_to_boost_assign_op(self):
        return '='

    @property
    def boost_to_vk_assign_op(self):
        return '='

    def vk_value_to_boost(self, vk_value):
        return vk_value

    def boost_value_to_vk(self, boost_value):
        return boost_value

    @property
    def needs_vk_view(self):
        return False

    def __make_qual_das_type(self, type_name):
        t = type_name
        if self.is_pointer:
            t += ' ?'
        if self.is_fixed_array:
            t += f' [{self._c_param.type.fixed_array_size}]'
        return t


class ParamVkHandle(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        c_type = c_param.type
        if (c_type.unqual_name.startswith('Vk')
        and c_type.unqual_name.endswith('_T')
        and c_type.is_pointer):
            return cls(c_param=c_param, **kwargs)

    @property
    def is_pointer(self):
        return False

    @property
    def vk_unqual_type(self):
        ct = self.c_unqual_type
        assert_ends_with(ct, '_T')
        return ct[:-2]

    @property
    def boost_unqual_type(self):
        return vk_handle_type_to_boost(self.vk_unqual_type)

    def boost_value_to_vk(self, boost_value):
        return f'boost_value_to_vk({boost_value})'

    def vk_value_to_boost(self, vk_value):
        return None


class ParamVkHandlePtr(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        c_type = c_param.type
        generator = c_param._generator
        if (f'{c_type.unqual_name}_T' in generator.opaque_structs
        and c_type.is_pointer):
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return self.c_unqual_type

    def vk_value_to_boost(self, vk_value):
        return None

    def boost_value_to_vk(self, boost_value):
        return None


class ParamVkStruct(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        c_type = c_param.type
        if (c_type.is_struct and not c_type.is_pointer
        and c_type.unqual_name.startswith('Vk')):
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return self.c_unqual_type

    @property
    def boost_unqual_type(self):
        return vk_struct_type_to_boost(self.vk_unqual_type)

    def boost_value_to_vk(self, boost_value):
        return None

    def vk_value_to_boost(self, vk_value):
        return f'vk_value_to_boost({vk_value})'

    @property
    def vk_to_boost_assign_op(self):
        return '<-'

    @property
    def needs_vk_view(self):
        return True


class ParamVkStructPtr(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        c_type = c_param.type
        if (c_type.is_struct and c_type.is_pointer
        and c_type.unqual_name.startswith('Vk')):
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return self.c_unqual_type

    @property
    def boost_unqual_type(self):
        return vk_struct_type_to_boost(self.vk_unqual_type)

    def boost_value_to_vk(self, boost_value):
        return None

    def vk_value_to_boost(self, vk_value):
        return None

    @property
    def needs_vk_view(self):
        return True


class ParamVkEnum(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        c_type = c_param.type
        if c_type.is_enum and c_type.unqual_name.startswith('Vk'):
            return cls(c_param=c_param, **kwargs)

    @property
    def vk_unqual_type(self):
        return self.c_unqual_type


class ParamFixedString(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        c_type = c_param.type
        if c_type.unqual_name == 'char' and c_type.is_fixed_array:
            return cls(c_param=c_param, **kwargs)

    @property
    def is_fixed_array(self):
        return False

    @property
    def vk_unqual_type(self):
        #TODO: add if needed
        return None

    @property
    def boost_unqual_type(self):
        return 'string'

    def boost_value_to_vk(self, boost_value):
        return None

    def vk_value_to_boost(self, vk_value):
        return f'vk_value_to_boost({vk_value})'


class ParamString(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if c_param.type.name == 'const char *':
            return cls(c_param=c_param, **kwargs)

    @property
    def is_pointer(self):
        return False

    @property
    def vk_unqual_type(self):
        return 'string'

    @property
    def boost_name(self):
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
    def boost_name(self):
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


class ParamUnknown(ParamBase):

    @classmethod
    def maybe_create(cls, **kwargs):
        return cls(**kwargs)

    @property
    def c_unqual_type(self):
        raise self.__unknown_param_error

    @property
    def vk_unqual_type(self):
        raise self.__unknown_param_error

    @property
    def boost_unqual_type(self):
        raise self.__unknown_param_error

    @property
    def boost_type(self):
        raise self.__unknown_param_error

    @property
    def vk_type(self):
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

def vk_struct_type_to_boost(vk_type):
    assert_starts_with(vk_type, 'Vk')
    return vk_type[2:]

def vk_handle_type_to_boost(vk_type):
    return vk_struct_type_to_boost(vk_type)

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
    assert_ends_with(lines[-1], char)
    lines[-1] = lines[-1][:-1]
