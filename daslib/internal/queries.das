options indenting = 4
options no_aot = true

require daslib/defer
require daslib/safe_addr
require generated
require vulkan


struct TimestampQueryPool
    queries : array<TimestampQuery>
    _query_pool : QueryPool
    _device : Device
    _timestamp_valid_bits : uint
    _timestamp_period : float


struct TimestampQuery
    ns : uint64
    available : bool
    _index : uint
    _query_pool : QueryPool


[private]
struct TimestampQueryResult
    value : uint64
    available : uint64


def create_timestamp_query_pool(
    phys_dev : PhysicalDevice;
    device : Device;
    queue_family : uint;
    query_count : int
) : TimestampQueryPool
    var pool <- [[ TimestampQueryPool
        _device <- weak_copy(device),
        _query_pool <- device |> create_query_pool([[QueryPoolCreateInfo
            query_type = VkQueryType VK_QUERY_TYPE_TIMESTAMP,
            query_count = uint(query_count)
        ]])
    ]]
    pool.queries |> reserve <| query_count
    for i in range(query_count)
        pool.queries |> emplace <| [[TimestampQuery
            _index = uint(i),
            _query_pool = weak_copy(pool._query_pool)
        ]]

    let props <- phys_dev |> get_physical_device_properties
    var qprops <- phys_dev |> get_physical_device_queue_family_properties
    defer() <| { delete qprops; }
    pool._timestamp_valid_bits = qprops[queue_family].timestamp_valid_bits
    pool._timestamp_period = props.limits.timestamp_period

    return <- pool


def cmd_reset(
    command_buffer : CommandBuffer;
    pool : TimestampQueryPool
)
    command_buffer |> cmd_reset_query_pool(
        pool._query_pool, 0u, uint(pool.queries |> length()))


def update(var pool : TimestampQueryPool)
    var data : array<TimestampQueryResult>
    defer() <| { delete data; }
    data |> resize <| length(pool.queries)

    var pdata : void ?
    unsafe
        pdata = addr(data[0])

    assert(intptr(pdata) % uint64(8) == uint64(0))

    let result = vkGetQueryPoolResults(
        pool._device.device,
        pool._query_pool.query_pool,
        0u,
        uint(pool.queries |> length()),
        uint64(typeinfo(sizeof type<TimestampQueryResult>)*length(data)),
        pdata,
        uint64(typeinfo(sizeof type<TimestampQueryResult>)),
        uint(VkQueryResultFlagBits VK_QUERY_RESULT_64_BIT) |
        uint(VkQueryResultFlagBits VK_QUERY_RESULT_WITH_AVAILABILITY_BIT)
    )
    assert(result == VkResult VK_SUCCESS || result == VkResult VK_NOT_READY)
    for datum, query in data, pool.queries
        query.available = datum.available != uint64(0)
    print("{data}\n")


def cmd_write(
    command_buffer : CommandBuffer;
    query : TimestampQuery;
    pipeline_stage : VkPipelineStageFlagBits
)
    vkCmdWriteTimestamp(
        boost_value_to_vk(command_buffer),
        boost_value_to_vk(pipeline_stage),
        boost_value_to_vk(query._query_pool),
        boost_value_to_vk(query._index)
    )
