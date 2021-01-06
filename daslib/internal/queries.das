options indenting = 4
options no_aot = true

require daslib/defer
require generated
require vulkan


struct TimestampQueryPool
    query_count : uint
    _query_pool : QueryPool


def create_timestamp_query_pool(device : Device; query_count : uint
) : TimestampQueryPool
    return <- [[ TimestampQueryPool
        query_count = query_count,
        _query_pool <- sis.device |> create_query_pool([[QueryPoolCreateInfo
            query_type = VkQueryType VK_QUERY_TYPE_TIMESTAMP,
            query_count = query_count
        ]])
    ]]
