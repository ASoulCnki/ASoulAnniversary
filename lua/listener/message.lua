local requests = require("resty.requests")
local utils = require("listener.utils")
local constant = require("listener.constant")
local ngx = require("ngx")

local csrf = constant.csrf
local selfUserID = constant.selfID
local domain = "https://api.vc.bilibili.com/session_svr/v1/session_svr"
local filter = utils.table_filter
local map = utils.table_map
local decode_json = utils.decode_json

local api_session_list = {
    SYN = domain .. "/new_sessions?begin_ts=%s&build=0&mobi_app=web",
    ACK = domain .. "/ack_sessions?begin_ts=%s&build=0&mobi_app=web"
}

local auth_headers = {
    ["Cookie"] = constant.cookie,
    ["User-Agent"] = constant.user_agent,
    ["Origin"] = "https://message.bilibili.com/",
    ["Referer"] = "https://message.bilibili.com/"
}

local function get(url)
    return requests.get(url, {
        headers = auth_headers
    })
end

local function ack_session(session)
    local ACK = domain .. '/update_ack'
    requests.post(ACK, {
        headers = auth_headers,
        body = {
            talker_id = session.talker_id,
            session_type = 1,
            ack_seqno = session.ack_seqno + session.unread_count,
            build = 0,
            mobi_app = 'web',
            csrf_token = csrf,
            csrf = csrf
        }
    })
end

local function message_list()

    local function filter_map_session_list(session_list)
        local lower = string.lower

        session_list = filter(session_list, function(v)
            return v.unread_count > 0
        end)

        session_list = map(session_list, function(v)
            ack_session(v)
            return {
                uid = v.talker_id,
                content = lower(decode_json(v.last_msg.content).content or v.last_msg.content),
                msg_type = v.last_msg.msg_type
            }
        end)

        session_list = filter(session_list, function(v)
            return v.uid ~= selfUserID
        end)

        return session_list
    end

    ngx.update_time()
    -- 直接取当前时间戳可能会错过之前的消息，这里减去5s是因为爬取周期是5s
    local begin_ts = ngx.now() * 1000 - 5000

    local syn, ack = api_session_list.SYN, api_session_list.ACK
    local res, _ = get(string.format(syn, begin_ts))

    get(string.format(ack, begin_ts))

    local data = res and decode_json(res:body())

    data = data and filter_map_session_list(data.data.session_list)

    return data or {}
end

local _M = {
    message_list = message_list
}

return _M
