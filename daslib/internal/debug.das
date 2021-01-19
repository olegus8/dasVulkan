options indenting = 4
options no_aot = true

require daslib/defer
require daslib/safe_addr
require generated
require vulkan


struct DebugUtilsMessenger
    VkDebugUtilsMessengerEXT messenger
    DebugMsgContext_DasHandle _debug_ctx
    _instance : Instance
    _needs_delete : bool

def boost_value_to_vk(b : DebugUtilsMessenger) : VkDebugUtilsMessenerEXT
    return b.messenger

def boost_value_to_vk(b : DebugUtilsMessenger ?) : VkDebugUtilsMessengerEXT ?
    return b?.messenger

def vk_value_to_boost(v : VkDebugUtilsMessengerEXT) : DebugUtilsMessenger
    return [[ DebugUtilsMessenver messenger=v ]]

def create_debug_utils_messenger(
    instance : Instance;
    var create_info : DebugUtilsMessengerCreateInfoEXT;
    callback : lambda<(
        msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
        msg_type : uint;
        data : DebugUtilsMessengerCallbackDataEXT
    ): uint>;
    var result : VkResult? = [[VkResult?]]
)
    var vk_callback  <- @ <| [[<- callback]] (
        msg_severity : VkDebugUtilsMessageSeverityFlagBitsEXT;
        msg_type : uint;
        data : VkDebugUtilsMessengerCallbackDataEXT
    ) : uint
        return callback(
            msg_severity,
            msg_type,
            <- vk_value_to_boost(data)
        )

    var messenger <- [[DebugUtilsMessenger
        _instance = instance |> weak_copy,
        _needs_delete = true
    ]]

    var vk_create_info <- create_info |> vk_view_create_unsafe()
    defer() <| { create_info |> vk_view_destroy(); }

    var result_ = VkResult VK_SUCCESS

    result ?? result_ = vkCreateDebugUtilsMessengerEx(
        boost_value_to_vk(instance),
        vk_create_info,
        null,
        <- vk_callback,
        safe_addr(messenger.messenger),
        safe_addr(messenger._debug_ctx)
    )
    assert(result_ == VkResult VK_SUCCESS)

    return <- messenger


def finalize(var handle : DebugUtilsMessengerCreateInfoEXT & explicit)
    if handle._needs_delete
        vkDestroyDebugUtilsMessengerEx(
            boost_value_to_vk(handle._instance),
            
        pass
    memzero(handle)

/*
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

    let props <- phys_dev |> get_physical_device_properties
    let period = double(props.limits.timestamp_period)

    pool.queries |> reserve <| query_count
    for i in range(query_count)
        pool.queries |> emplace <| [[TimestampQuery
            _index = uint(i),
            _query_pool = weak_copy(pool._query_pool),
            period = period
        ]]

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
*/

