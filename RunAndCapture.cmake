# RunAndCapture.cmake  —  “no more black-box runs”
#
# -D TOOL=<exe>                absolute path to the program
# -D OUT=<file>                capture *stdout* here  (required)
# -D ARGS=<list>               semicolon-separated argument list (may be empty)
# -D ERR=<file>                optional: where to save stderr (defaults OUT+.err)

if(NOT DEFINED TOOL OR NOT DEFINED OUT)
    message(FATAL_ERROR "RunAndCapture.cmake: TOOL and OUT must be defined")
endif()

if(NOT DEFINED ERR)
    get_filename_component(_name "${OUT}" NAME_WE)
    get_filename_component(_dir  "${OUT}" DIRECTORY)
    set(ERR "${_dir}/${_name}.err.txt")
endif()

# -------------------------------------------------------------------------
# 1.  Echo the exact command line that will run, one arg per line
# -------------------------------------------------------------------------
message(STATUS "── RunAndCapture ────────────────────────────")
message(STATUS "TOOL = ${TOOL}")
message(STATUS "ARGS (${ARGS})")
message(STATUS "OUT  = ${OUT}")
message(STATUS "ERR  = ${ERR}")
message(STATUS "────────────────────────────────────────────")

# -------------------------------------------------------------------------
# 2.  Run the tool, capturing both streams
# -------------------------------------------------------------------------
execute_process(
    COMMAND        ${TOOL} ${ARGS}
    OUTPUT_FILE    "${OUT}"
    ERROR_FILE     "${ERR}"
    RESULT_VARIABLE _ec
)

# -------------------------------------------------------------------------
# 3.  Explode on failure but *show* the captured stderr first
# -------------------------------------------------------------------------
if(_ec AND NOT _ec EQUAL 0)
    file(READ "${ERR}" _errText LIMIT 4096)   # don’t spam huge logs
    message(STATUS "----- ${TOOL} stderr (first 4 KB) -----\n${_errText}\n-----")
    message(FATAL_ERROR "\"${TOOL}\" exited with code ${_ec}")
endif()

