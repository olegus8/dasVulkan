from das_shared.object_base import LoggingObject


class BoostGenerator(LoggingObject):

    def __init__(self, context):
        self.__context = context

    def generate(self):
        self.__context.write_to_file(
            fpath=f'../daslib/internal/generated.das',
            content='\n'.join(self.__make_content() + ['']))
        for module in self.__modules:
            module.generate()

    def __make_content(self):
        return [
            '// generated by dasVulkan',
            '',
            'options indenting = 4',
            'options no_aot = true',
        ]
