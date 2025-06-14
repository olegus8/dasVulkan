# Arguments passed in by -D:
#   TOOL         absolute path to the executable
#   OUT          file to capture stdout
#   ARGS         remaining tool arguments (semicolon-separated list)
#
# Example:
#   cmake -DTOOL=glslangValidator -DOUT=x.txt -DARGS="--reflect;shader.spv" -P RunAndCapture.cmake

execute_process(
    COMMAND ${TOOL} ${ARGS}
    OUTPUT_FILE "${OUT}"
    RESULT_VARIABLE _ec
    ERROR_VARIABLE _err
    COMMAND_ECHO STDOUT
)

if(_ec AND NOT _ec EQUAL 0)
    message(FATAL_ERROR
        "\"${TOOL}\" failed (exit ${_ec})\n${_err}")
endif()
