# Arguments passed in by -D:
#   TOOL         absolute path to the executable
#   OUT          file to capture stdout
#   ARGS         remaining tool arguments (semicolon-separated list)
#
# Example:
#   cmake -DTOOL=glslangValidator -DOUT=x.txt -DARGS="--reflect;shader.spv" -P RunAndCapture.cmake

execute_process(
    COMMAND "${TOOL}" ${ARGS}
    OUTPUT_FILE "${OUT}"
    RESULT_VARIABLE _ec
)

if(_ec)
    message(FATAL_ERROR
            "`${TOOL} ${ARGS}` failed with exit code ${_ec}")
endif()
