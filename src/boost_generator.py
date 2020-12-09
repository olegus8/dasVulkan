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
        return map(self.create_param_from_node, c_func.params)

    def create_struct_fields(self, c_struct):
        return map(self.create_param_from_node, c_struct.fields)

    def create_param(self, c_name, c_type):
        for param_class in [
            ParamVkAllocator,
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

    def __init__(self, generator, name):
        self.__generator = generator
        self.__vk_func_name = name

        self.__params = self.__generator.create_func_params(self.__c_func)

    @property
    def __boost_func_name(self):
        return vk_func_name_to_boost(self.__vk_func_name)

    @property
    def __c_func(self):
        return self.__generator.functions[self.__vk_func_name]

    @property
    def __returns_vk_result(self):
        return returns_vk_result(self.__c_func)

    def __get_param(self, vk_name):
        for param in self.__params:
            if param.vk_name == vk_name:
                return param

    def declare_array(self, count, items):
        p_count = self.__get_param(count)
        p_items = self.__get_param(items)
        p_count.set_dyn_array(count=p_count, items=p_items)
        p_items.set_dyn_array(count=p_count, items=p_items)

    def declare_output(self, name):
        for param in self.__params:
            if param.vk_name == name:
                param.set_boost_func_output()

    @property
    def __return_type(self):
        rtypes = [t for param in self.__params
            for t in param.generate_boost_func_return_types]
        if len(rtypes) > 1:
            raise Exception('TODO: add multiple outputs support if needed')
        return (rtypes or ['void'])[0]

    def generate(self):
        lines = []
        lines += [
            '',
           f'def {self.__boost_func_name}('
        ]
        for param in self.__params:
            lines += [f'    {line}'
                for line in param.generate_boost_func_param()]
        if self.__returns_vk_result:
            lines.append(f'    var result : VkResult? = [[VkResult?]];')
        remove_last_char(lines, ';')

        lines += [
           f') : {self.__return_type}',
        ]

        for param in self.__params:
            lines += [f'    {line}'
                for line in param.generate_boost_func_temp_vars_init()]

        if self.__returns_vk_result:
            lines.append(f'    var result_ = VkResult VK_SUCCESS')
        maybe_capture_result = ('result ?? result_ = '
            if self.__returns_vk_result else '')
        if lines[-1] != ['']:
            lines.append('')

        lines += [
           f'    {maybe_capture_result}{self.__vk_func_name}(',
        ]
        for param in self.__params:
            lines += [f'        {},'.format(
                param.boost_func_query_array_size_param)]
        remove_last_char(lines, ',')


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

        for param in self.__params:
            lines += [f'    {line}'
                for line in param.generate_boost_func_temp_vars_delete()]
        
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
        array = GenStructFieldArray(struct=self, **kwargs)
        self.__arrays.append(array)
        return self

    @property
    def __c_struct(self):
        return self.__generator.structs[self.__vk_type_name]

    @property
    def _fields(self):
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

    def __get_array(self, vk_name):
        for array in self.__arrays:
            if vk_name in [array.vk_items_name, array.vk_count_name]:
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
        for field in self._fields:
            if self.__is_array_count(field.vk_name):
                continue
            if field.vk_name in ['sType', 'pNext']:
                continue
            boost_name = field.boost_name
            boost_type = field.boost_type
            if self.__is_array_items(field.vk_name):
                array = self.__get_array(field.vk_name)
                boost_name = boost_ptr_name_to_array(boost_name)
                forced_item_type = array.boost_item_type_name
                if forced_item_type:
                    boost_type = f'array<{forced_item_type}>'
                else:
                    boost_type = boost_ptr_type_to_array(boost_type)
            lines += [f'    {boost_name} : {boost_type}']

        if self.__boost_to_vk:
            for field in self._fields:
                if field.vk_name in ['pNext', 'sType']:
                    continue
                bname, vname = field.boost_name, field.vk_name
                btype, vtype = field.boost_type, field.vk_type
                if self.__is_array_items(vname) and field.needs_conversion:
                    dvtype = deref_das_type(vtype)
                    biname = boost_ptr_name_to_array(field.boost_name)
                    lines += [f'    _vk_view_{biname} : array<{dvtype}>']
                elif field.is_pointer and field.needs_conversion:
                    lines += [f'    _vk_view_{bname} : {vtype}']
                elif field.is_struct and field.needs_conversion:
                    lines += [f'    _vk_view_p_{bname} : {vtype} ?']

            lines += [f'    _vk_view__active : bool']
        return lines

    def __generate_vk_to_boost(self):
        lines = []
        lines += [
            '',
           f'def vk_value_to_boost(vk_struct : {self.__vk_type_name}) '
                f': {self.__boost_type_name}',
           f'    return <- [[{self.__boost_type_name}'
        ]
        for field in self._fields:
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
        lines += self.__generate_vk_view_create()
        lines += self.__generate_vk_view_destroy()
        return lines

    def __generate_vk_view_create(self):
        bstype = self.__boost_type_name
        vstype = self.__vk_type_name
        lines = []
        lines += [
            '',
           f'def vk_view_create_unsafe(var boost_struct : {bstype}',
           f') : {vstype}',
            '',
            '    assert(!boost_struct._vk_view__active)',
            '    boost_struct._vk_view__active = true',
        ]
        for field in self._fields:
            if field.vk_name in ['pNext', 'sType']:
                continue
            bname, vname = field.boost_name, field.vk_name
            btype, vtype = field.boost_type, field.vk_type
            if self.__is_array_items(vname):
                biname = boost_ptr_name_to_array(field.boost_name)
                array = self.__get_array(vname)
                if field.needs_vk_view:
                    lines += ['']
                    lines += [
                       f'    boost_struct._vk_view_{biname} <- [{{',
                       f'        for item in boost_struct.{biname} ;',
                       f'        item |> vk_view_create_unsafe()}}]',
                    ]
                elif field.needs_conversion:
                    lines += ['']
                    lines += [
                       f'    boost_struct._vk_view_{biname} <- [{{',
                       f'        for item in boost_struct.{biname} ;',
                       f'        item |> boost_value_to_vk()}}]',
                    ]
                else:
                    lines += ['']
                    adr = f'array_addr_unsafe(boost_struct.{biname})'
                    if array.boost_item_type_name:
                        lines += [
                           f'    var vk_{bname} : {vtype}',
                            '    unsafe',
                           f'        vk_{bname} = reinterpret<{vtype}>({adr})',
                        ]
                    else:
                        lines += [
                           f'    let vk_{bname} = {adr}',
                        ]
            elif field.is_pointer and field.needs_vk_view:
                dvtype = deref_das_type(vtype)
                lines += [
                    '',
                   f'    if boost_struct.{bname} != null',
                   f'        boost_struct._vk_view_{bname} = new {dvtype}',
                   f'        *(boost_struct._vk_view_{bname}) <- (',
                   f'            *(boost_struct.{bname}) |> '
                                    f'vk_view_create_unsafe())',
                ]
            elif field.is_struct and field.needs_vk_view:
                lines += [
                    '',
                   f'    boost_struct._vk_view_p_{bname} = new {vtype}',
                   f'    *(boost_struct._vk_view_p_{bname}) <- (',
                   f'        boost_struct.{bname} |> '
                                f'vk_view_create_unsafe())',
                ]
        if lines[-1] != '':
            lines.append('')
        lines += [
           f'    return <- [[ {vstype}',
        ]
        array_counts_added = set()
        for field in self._fields:
            if field.vk_name in ['pNext']:
                continue
            bname, vname = field.boost_name, field.vk_name
            btype, vtype = field.boost_type, field.vk_type
            if vname == 'sType':
                vk_value = f'VkStructureType {self.__vk_structure_type}'
            elif self.__is_array_count(vname):
                continue
            elif self.__is_array_items(vname):
                biname = boost_ptr_name_to_array(field.boost_name)
                if field.needs_vk_view or field.needs_conversion:
                    vk_value = (
                        f'array_addr_unsafe(boost_struct._vk_view_{biname})')
                else:
                    vk_value = f'vk_{bname}'
                array = self.__get_array(vname)
                vcname = array.vk_count_name
                if (vcname and not array.optional
                and vcname not in array_counts_added):
                    array_counts_added.add(vcname)
                    vctype = array.vk_count.vk_type
                    lines.append(f'        {vcname} = '
                        f'{vctype}(boost_struct.{biname} |> length()),')
            elif field.is_pointer and field.needs_vk_view:
                vk_value = f'boost_struct._vk_view_{bname}'
            elif field.is_struct and field.needs_vk_view:
                vk_value = f'*(boost_struct._vk_view_p_{bname})'
            else:
                vk_value = field.boost_value_to_vk(f'boost_struct.{bname}')
            lines += [f'        {vname} = {vk_value},']
        remove_last_char(lines, ',')
        lines += [
           f'    ]]',
        ]
        return lines

    def __generate_vk_view_destroy(self):
        bstype = self.__boost_type_name
        vstype = self.__vk_type_name
        lines = []
        lines += [
            '',
           f'def vk_view_destroy(var boost_struct : {bstype})',
            '    assert(boost_struct._vk_view__active)',
        ]
        for field in self._fields:
            if field.vk_name in ['pNext', 'sType']:
                continue
            bname, vname = field.boost_name, field.vk_name
            btype, vtype = field.boost_type, field.vk_type
            if self.__is_array_items(vname):
                biname = boost_ptr_name_to_array(field.boost_name)
                if field.needs_vk_view:
                    lines += [
                       f'    for item in boost_struct.{biname}',
                       f'        item |> vk_view_destroy()',
                    ]
                if field.needs_conversion:
                    lines += [
                       f'    delete boost_struct._vk_view_{biname}',
                    ]
            elif field.is_pointer and field.needs_vk_view:
                lines += [
                   f'    if boost_struct.{bname} != null',
                   f'        *(boost_struct.{bname}) |> vk_view_destroy()',
                    '        unsafe',
                   f'            delete boost_struct._vk_view_{bname}',
                ]
            elif field.is_struct and field.needs_vk_view:
                lines += [
                   f'    boost_struct.{bname} |> vk_view_destroy()',
                    '    unsafe',
                   f'        delete boost_struct._vk_view_p_{bname}',
                ]
        lines += [
            '    boost_struct._vk_view__active = false',
        ]
        return lines


class GenStructFieldArray(object):

    def __init__(self, struct, items, count=None,
        force_item_type=None, optional=False,
    ):
        self.__gen_struct = struct
        self.vk_count_name = count
        self.vk_items_name = items
        self.boost_item_type_name = force_item_type
        self.optional = optional

    @property
    def vk_count(self):
        for field in self.__gen_struct._fields:
            if field.vk_name == self.vk_count_name:
                return field


class GenHandle(object):

    def __init__(self, generator, handle, dtor=None):
        self.generator = generator
        self.vk_handle_type_name = handle
        self.dtor = None if dtor is None else GenHandleDtor(
            handle=self, name=dtor)
        self.ctors = []

    def declare_ctor(self, vk_name):
        ctor = GenHandleCtor(handle=self, name=vk_name)
        self.ctors.append(ctor)
        return ctor

    @property
    def boost_handle_type_name(self):
        return vk_handle_type_to_boost(self.vk_handle_type_name)

    @property
    def boost_handle_attr(self):
        return boost_handle_attr_name(self.boost_handle_type_name)

    def generate(self):
        lines = []
        lines += [
            '',
            '//',
           f'// {self.boost_handle_type_name}',
            '//',
        ]
        lines += self.__generate_type()
        for ctor in self.ctors:
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
        for param in self.dtor.params:
            lines += [f'    {line}' for line in param.generate_handle_field()]
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


class GenHandleFunc(object):

    def __init__(self, handle, name):
        self.gen_handle = handle
        self.__arrays = []
        self.vk_name = name

    @property
    def generator(self):
        return self._gen_handle._generator

    def declare_array(self, **kwargs):
        array = GenHandleParamArray(handle=self, **kwargs)
        self.__arrays.append(array)
        return self

    @property
    def boost_name(self):
        return vk_func_name_to_boost(self.vk_name)

    @property
    def returns_vk_result(self):
        return returns_vk_result(self.__c_func)

    @property
    def __c_func(self):
        return self._generator.functions[self.vk_name]

    @property
    def __vk_params(self):
        return self._generator.get_func_params(self.__c_func)

    @property
    def params(self):
        return map(self.get_param, self.__vk_params)

    def get_param(self, vk_param):
        for param_class in [
            GenHandleFuncParamAllocator,
            GenHandleFuncParamMainHandle,
            GenHandleFuncParamStruct,
            GenHandleFuncParamArrayCounter,
            GenHandleFuncParam,
        ]:
            param = param_class.maybe_create(vk_param=vk_param, func=self)
            if param:
                return param

    def is_array_count(self, vk_name):
        for array in self.__arrays:
            if vk_name == array.vk_count_name:
                return True
        return False

    def is_array_items(self, vk_name):
        for array in self.__arrays:
            if vk_name == array.vk_items_name:
                return True
        return False

    def get_array(self, vk_name):
        for array in self.__arrays:
            if vk_name in [array.vk_items_name, array.vk_count_name]:
                return array


class GenHandleCtor(GenHandleFunc):

    @property
    def __return_type(self):
        for param in self.params:
            rtype = param.generate_ctor_return_type
            if rtype is not None:
                return rtype

    def generate(self):
        bh_attr = self.gen_handle.boost_handle_attr
        bh_type = self.gen_handle.boost_handle_type_name

        lines = []
        lines += [
            '',
           f'def {self.boost_name}(']
        for param in self.params:
            lines += [f'    {line}'
                for line in param.generate_ctor_boost_param()]
        if self.returns_vk_result:
            lines += [f'    var result : VkResult? = [[VkResult?]];']
        remove_last_char(lines, ';')
        lines += [
           f') : {self.__return_type}',
            '',
           f'    var {bh_attr} <- [[ {bh_type}',
           f'        _needs_delete = true,',
        ]
        for param in self.gen_handle.dtor.params():
            lines += [f'        {line}'
                for line in param.generate_ctor_init_field()]
        remove_last_char(lines, ',')
        lines += [
            '    ]]',
        ]
        for param in self.params:
            lines += [f'    {line}'
                for line in param.generate_ctor_temp_vars()]
        if lines[-1] != '':
            lines.append('')

        if self.returns_vk_result:
            lines += [f'    var result_ = VkResult VK_SUCCESS']
            maybe_capture_result = 'result ?? result_ = '
        else:
            maybe_capture_result = ''

        lines += [
           f'    {maybe_capture_result}{self.vk_name}(']
        lines += [f'    {param.generate_ctor_vk_param()},'
            for param in self.params]
        remove_last_char(lines, ',')
        lines += [
           f'    )',
        ]
        if self.returns_vk_result:
            lines += [
               f'    assert(result_ == VkResult VK_SUCCESS)']
        lines += [
           f'    return <- {bh_attr}']
        return lines


class GenHandleDtor(GenHandleFunc):

    def generate(self):
        bh_attr = self.gen_handle.boost_handle_attr
        bh_type = self.gen_handle.boost_handle_type_name
        lines = []
        lines += [
            '',
           f'def finalize(var {bh_attr} : {bh_type} explicit)',
           f'    if {bh_attr}._needs_delete',
           f'        {self.vk_name}(',
        ] + [
           f'            {param.generate_dtor_vk_param()},'
                            for param in self.params]
        remove_last_char(lines, ',')
        lines += [
            '        )',
           f'    memzero({bh_attr})',
        ]
        return lines


class GenHandleFuncArray(object):

    def __init__(self, func, items, count):
        self.func = func
        self.vk_count_name = count
        self.vk_items_name = items


class GenHandleFuncParam(object):

    def __init__(self, func, vk_param):
        self.vk_param = vk_param
        self.func = func

    @property
    def gen_handle(self):
        return self.func.gen_handle

    @property
    def boost_name(self):
        bname = self.vk_param.boost_name
        if self.is_array_items:
            bname = boost_ptr_name_to_array(bname)
        elif self.vk_param.is_pointer
            bname = deref_boost_ptr_name(bname)
        return bname

    @property
    def boost_type(self):
        btype = self.vk_param.boost_type
        if self.is_array_items:
            btype = f'array<{deref_das_type(btype)}>'
        elif self.vk_param.is_pointer
            btype = deref_das_type(btype)
        return btype

    @property
    def vk_name(self):
        return self.vk_param.vk_name

    @property
    def vk_type(self):
        return self.vk_param.vk_type

    @property
    def array(self):
        return self.func.get_array(self.vk_name)

    @property
    def is_array_items(self):
        return self.func.is_array_items(self.vk_name)

    def generate_ctor_boost_param(self):
        maybe_var = 'var ' if self.vk_param.needs_vk_view else ''
        return [f'{maybe_var}{self.boost_name} : {self.boost_type} = '
            f'[[ {self.boost_type} ]];']

    def generate_ctor_return_type(self):
        return None

    def generate_ctor_init_field(self):
        vk_value = self.vk_param.boost_value_to_vk(self.boost_name)
        return [f'_{self.boost_name} = {vk_value},']

    def generate_ctor_temp_vars(self):
        lines = []
        if self.vk_param.needs_view:
            assert not self.array
            bname = self.boost_name
            btype = self.boost_type
            vutype = self.vk_param.vk_unqual_type
            if self.is_array_items:
                lines += [
                    '',
                    'TODO'
                ]
            else:
                lines += [
                    '',
                   f'var vk_{bname} : {vutype}',
                   f'unsafe',
                   f'    vk_{bname} <- {bname} |> vk_view_create_unsafe()',
                   f'defer() <| ${{ {bname} |> vk_view_destroy(); }}',
                ]
        return lines

    def generate_ctor_vk_param(self):
        if self.vk_param.needs_view:
            return f'safe_addr(vk_{self.boost_name})'
        else:
            return self.vk_param.boost_value_to_vk(self.boost_name)

    def generate_dtor_vk_param(self):
        bh_attr = self.func.gen_handle.boost_handle_attr
        return f'{bh_attr}._{self.boost_name}'

    def generate_handle_field(self):
        return [f'_{self.boost_name} : {self.vk_type}']


class GenHandleFuncParamAllocator(GenHandleFuncParam):

    @classmethod
    def maybe_create(cls, func, vk_param):
        if vk_param.vk_name == 'pAllocator':
            return cls(func=func, vk_param=vk_param)

    @property
    def boost_name(self):
        return None

    @property
    def boost_type(self):
        return None

    def generate_ctor_boost_param(self):
        return []

    def generate_ctor_init_field(self):
        return []

    def generate_ctor_temp_vars(self):
        return []

    def generate_handle_field(self):
        return []

    def generate_ctor_vk_param(self):
        return 'null'

    def generate_dtor_vk_param(self):
        return 'null'


class GenHandleFuncParamArrayCounter(GenHandleFuncParam):

    @classmethod
    def maybe_create(cls, func, vk_param):
        if func.is_array_counter(vk_param.vk_name):
            return cls(func=func, vk_param=vk_param)

    @property
    def boost_name(self):
        return None

    @property
    def boost_type(self):
        return None

    def generate_ctor_boost_param(self):
        return []


class GenHandleFuncParamMainHandle(GenHandleFuncParam):

    @classmethod
    def maybe_create(cls, func, vk_param):
        if vk_param.vk_unqual_type == func.gen_handle.vk_handle_type_name:
            return cls(func=func, vk_param=vk_param)

    def generate_ctor_return_type(self):
        return self.boost_type

    def generate_ctor_boost_param(self):
        return []

    def generate_ctor_init_field(self):
        return []

    def generate_ctor_vk_param(self):
        bh_attr = self.func.gen_handle.boost_handle_attr
        bh_type = self.func.gen_handle.boost_handle_type_name
        return f'safe_addr({bh_attr}.{bh_attr})'

    def generate_dtor_vk_param(self):
        bh_attr = self.func.gen_handle.boost_handle_attr
        return self.vk_param.boost_value_to_vk(bh_attr)

    def generate_handle_field(self):
        return []


class GenHandleFuncParamStruct(GenHandleFuncParam):

    @classmethod
    def maybe_create(cls, func, vk_param):
        if vk_param.is_struct:
            return cls(func=func, vk_param=vk_param)


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
        self._vk_array_items = None
        self._vk_array_count = None
        self._is_boost_func_output = False

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
    def _vk_unqual_type(self):
        raise NotImplementedError()

    def set_dyn_array(self, count, items):
        self._vk_array_items = items
        self._vk_array_count = count

    def set_boost_func_output(self):
        self._is_boost_func_output = True

    @property
    def _vk_is_dyn_array_count(self):
        return self.vk_name == self._vk_array_count.vk_name

    @property
    def _vk_is_dyn_array_items(self):
        return self.vk_name == self._vk_array_items.vk_name

    @property
    def _vk_type(self):
        t = self.vk_unqual_type
        if self.vk_is_pointer:
            t += ' ?'
        if self.vk_is_fixed_array:
            t += f' [{self._c_param.type.fixed_array_size}]'
        return t

    @property
    def vk_name(self):
        return self._c_param.name

    @property
    def _boost_base_name(self):
        bname = vk_param_name_to_boost(self.vk_name)
        if self._vk_is_dyn_array_items:
            bname = deref_boost_ptr_name(bname)
        return bname

    @property
    def _boost_base_type(self):
        if self._vk_is_dyn_array_items:
            return f'array<{self._vk_unqual_type}>'
        else:
            return self._vk_type

    @property
    def _boost_func_param_name(self):
        bname = self._boost_base_name
        if self._vk_is_pointer and not self._vk_is_dyn_array_items:
            bname = deref_boost_ptr_name(bname)
        return bname

    @property
    def _boost_func_param_type(self):
        btype = self._boost_base_type
        if self._vk_is_pointer and not self._vk_is_dyn_array_items:
            btype = deref_das_type(btype)
        return btype

    def generate_boost_func_param(self):
        if self._vk_is_dyn_array_count or self._is_boost_func_output:
            return []
        bname = self._boost_func_param_name
        bname = self._boost_func_param_type
        return [f'{bname} : {btype} = [[ {btype} ]];']

    def generate_boost_func_return_types(self):
        rtypes = []
        if self._is_boost_func_output:
            rtypes.append(self._boost_func_param_type)
        return rtypes

    def generate_boost_func_temp_vars_init(self):
        if self._vk_is_dyn_array_count:
            return [f'var vk_{self._vk_name} : uint']
        if self._vk_is_dyn_array_items:
            bname = self._boost_func_param_name
            vtype = self._vk_unqual_type
            if self._is_boost_func_output:
                return [
                    f'var vk_{bname}__items : array<{vtype}>',
                    f'defer() <| ${{ delete vk_{bname}__items; }}',
                ]
        if self._vk_is_pointer:
            bname = self._boost_func_param_name
            vtype = self._vk_unqual_type
            if self._is_boost_func_output:
                return [f'var vk_{bname} : {vtype}']
            else:
                return [
                    f'var vk_{bname} : {vtype} = boost_value_to_vk({bname})']
        return []

    def generate_boost_func_temp_vars_delete(self):
        return []

    @property
    def boost_func_query_array_size_param(self):
        if self._vk_is_dyn_array_count:
            if self._vk_array_items._is_boost_func_output:
                return f'safe_addr(vk_{self._vk_name})'
            else:
                bname = self._boost_func_param_name
                return f'uint({bname} |> length())'
        elif self._vk_is_dyn_array_items:
            if self._is_boost_func_output:
                return f'[[ {self._vk_unqual_type} ? ]]',
            else:
                bname = self._boost_func_param_name
                return f'array_addr_unsafe({bname})',
        elif self._vk_is_pointer:
            bname = self._boost_func_param_name
            return f'safe_addr(vk_{bname})'
        #TODO
        return self._boost_func_param_name


class ParamVkAllocator(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if (c_param.name == 'pAllocator'
        and c_param.type == 'VkAllocationCallbacks *'
        ):
            return cls(c_param=c_param, **kwargs)

    @property
    def _vk_unqual_type(self):
        return self._c_unqual_type

    def generate_boost_func_param(self):
        return []

    def generate_boost_func_temp_vars_setup(self):
        return []

    def generate_boost_func_temp_vars_delete(self):
        return []

    @property
    def boost_func_query_array_size_param(self):
        return 'null'


class ParamVkHandle(ParamBase):

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
    def _vk_unqual_type(self):
        ct = self._c_unqual_type
        assert_ends_with(ct, '_T')
        return ct[:-2]


class ParamVkHandlePtr(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        c_type = c_param.type
        generator = c_param._generator
        if (f'{c_type.unqual_name}_T' in generator.opaque_structs
        and c_type.is_pointer):
            return cls(c_param=c_param, **kwargs)

    @property
    def _vk_unqual_type(self):
        return self._c_unqual_type


class ParamVkStruct(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        c_type = c_param.type
        if (c_type.is_struct and c_type.unqual_name.startswith('Vk')):
            return cls(c_param=c_param, **kwargs)

    @property
    def _vk_unqual_type(self):
        return self._c_unqual_type


class ParamVkEnum(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        c_type = c_param.type
        if c_type.is_enum and c_type.unqual_name.startswith('Vk'):
            return cls(c_param=c_param, **kwargs)

    @property
    def _vk_unqual_type(self):
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
    def _vk_unqual_type(self):
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
    def _vk_unqual_type(self):
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
    def _vk_unqual_type(self):
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
    def _vk_unqual_type(self):
        return 'float'


class ParamInt32(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if c_param.type.unqual_name == 'int':
            return cls(c_param=c_param, **kwargs)

    @property
    def _vk_unqual_type(self):
        return 'int'


class ParamUInt8(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if c_param.type.unqual_name == 'uint8_t':
            return cls(c_param=c_param, **kwargs)

    @property
    def _vk_unqual_type(self):
        return 'uint8'


class ParamUInt32(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if c_param.type.unqual_name in [
            'unsigned int', 'uint32_t',
        ]:
            return cls(c_param=c_param, **kwargs)

    @property
    def _vk_unqual_type(self):
        return 'uint'


class ParamUInt64(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if c_param.type.unqual_name in [
            'unsigned long long', 'unsigned long',
        ]:
            return cls(c_param=c_param, **kwargs)

    @property
    def _vk_unqual_type(self):
        return 'uint64'


class ParamVkBool32(ParamBase):

    @classmethod
    def maybe_create(cls, c_param, **kwargs):
        if c_param.type.unqual_name == 'VkBool32':
            return cls(c_param=c_param, **kwargs)

    @property
    def _vk_unqual_type(self):
        return 'uint'


class ParamUnknown(ParamBase):

    @classmethod
    def maybe_create(cls, **kwargs):
        return cls(**kwargs)

    @property
    def _c_unqual_type(self):
        raise self.__unknown_param_error

    @property
    def _vk_unqual_type(self):
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
