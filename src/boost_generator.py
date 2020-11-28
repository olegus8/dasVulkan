from das_shared.object_base import LoggingObject


class BoostGenerator(LoggingObject):

    def __init__(self, context):
        self.__context = context

    def generate(self):
        self.__context.write_to_file(fpath='../daslib/internal/hello.das',
            content='hello new world')
