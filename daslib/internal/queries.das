options indenting = 4
options no_aot = true

require daslib/defer
require daslib/safe_addr
require generated
require vulkan


struct TimestampQueryPool
    queries : array<TimestampQuery>
    _timestamp_period : double
    _query_pool : QueryPool
    _device : Device


struct TimestampQuery
    ticks : uint64
    available : bool
    _index : uint
    _query_pool : QueryPool


[private]
struct TimestampQueryResult
    ticks : uint64
    available : uint64


def diff_ns(t0 : TimestampQuery; t1: TimestampQuery) : double
    return double(t1.ticks - t0.ticks) * t0._query_pool._period


def create_timestamp_query_pool(
    phys_dev : PhysicalDevice;
    device : Device;
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
    pool._period = double(props.limits.timestamp_period)

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
        query.ticks = datum.ticks
        query.available = datum.available != uint64(0)


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
