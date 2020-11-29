from das_shared.object_base import LoggingObject


class BoostGenerator(LoggingObject):

    def __init__(self, context):
        self.__context = context
        self.__modules = []
        self.__add_devices_module()

    def generate(self):
        for module in self.__modules:
            module.generate()

    def __add_devices_module(self):
        module = self.__add_module(name='device')

    def __add_module(self, **kwargs):
        module = GeneratedModule(context=self.__context, **kwargs)
        self.__modules.append(module)
        return module


class GeneratedModule(LoggingObject):

    def __init__(self, name, context):
        self.__name = name
        self.__context = context

    def generate(self):
        self.__context.write_to_file(
            fpath=f'../daslib/internal/{self.__name}.das',
            content='\n'.join(self.__make_content() + ['']))

    def __make_content(self):
        return [
            'options indenting = 4',
            'options no_aot = true',
            '',
            #TODO: remove once generation is fully working
            'require internal/device_manual public',
        ]
