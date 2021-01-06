options indenting = 4
options no_aot = true

require daslib/defer
require generated
require vulkan


def create_and_reset_query_pool(
    device : Device = [[ Device ]];
    var create_info : QueryPoolCreateInfo = [[ QueryPoolCreateInfo ]]
)
    var pool <- device |> create_query_pool <| create_info
    device |> reset_query_pool(pool, 0u, create_info.query_count)
    return <- pool
