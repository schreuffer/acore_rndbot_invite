// Native dependencies are fakes. The directory implementation itself is included unchanged.
#include "../src/RandomBotDirectory.h"
#include <atomic>
#include <cassert>
#include <chrono>
#include <cctype>
#include <deque>
#include <iostream>
#include <map>
#include <mutex>
#include <sstream>
#include <utility>

using uint32 = uint32_t;
struct ObjectGuid
{
    uint32 value = 0;
    ObjectGuid(uint32 id = 0) : value(id) { }
    uint32 GetCounter() const { return value; }
    bool operator<(ObjectGuid const& other) const { return value < other.value; }
};
constexpr int CHAT_MSG_WHISPER = 7;
constexpr int TEAM_ALLIANCE = 0;
constexpr int LOCALE_enUS = 0;
constexpr int CONFIG_ALLOW_TWO_SIDE_INTERACTION_GROUP = 1;
constexpr int PLAYERBOT_SECURITY_INVITE = 2;
enum DenyReason
{
    PLAYERBOT_DENY_NONE, PLAYERBOT_DENY_LOW_LEVEL, PLAYERBOT_DENY_GEARSCORE,
    PLAYERBOT_DENY_OPPOSING, PLAYERBOT_DENY_BG
};
struct Session
{
    uint32 GetAccountId() const { return account; }
    int GetSessionDbcLocale() const { return 0; }
    uint32 account = 1;
};
struct Group
{
    bool IsFull() const { return full; }
    bool IsLeader(ObjectGuid) const { return leader; }
    bool IsAssistant(ObjectGuid) const { return false; }
    bool full = false;
    bool leader = true;
};
struct Player;
struct Security
{
    int LevelFor(Player*, DenyReason* reason) { *reason = deny; return level; }
    int level = PLAYERBOT_SECURITY_INVITE;
    DenyReason deny = PLAYERBOT_DENY_NONE;
};
struct PlayerbotAI
{
    Security* GetSecurity() { return &security; }
    Security security;
};
struct Player
{
    Session* GetSession() { return &session; }
    ObjectGuid GetGUID() const { return guid; }
    bool IsInWorld() const { return online; }
    bool InBattleground() const { return bg; }
    bool IsBeingTeleported() const { return false; }
    Group* GetGroup() { return group; }
    Group* GetGroupInvite() { return pending; }
    int GetTeamId() const { return team; }
    bool IsGameMaster() const { return false; }
    std::string GetName() const { return name; }
    uint32 GetLevel() const { return level; }
    uint32 getClass() const { return playerClass; }
    uint32 getRace() const { return 1; }
    uint32 GetZoneId() const { return 12; }
    Session session;
    ObjectGuid guid = 1;
    std::string name = "Requester";
    uint32 level = 60;
    uint32 playerClass = 5;
    int team = 0;
    bool online = true;
    bool bg = false;
    bool controlled = false;
    Group* group = nullptr;
    Group* pending = nullptr;
    PlayerbotAI ai;
};
// Production GUID is strongly typed. Supply the single accessor used by the implementation below.
struct Config
{
    template<class T> T GetOption(char const*, T) { return enabled; }
    bool enabled = true;
} config;
auto* sConfigMgr = &config;
struct World { bool getBoolConfig(int) { return false; } } world;
auto* sWorld = &world;
struct RandomManager { bool IsRandomBot(Player* bot) { return bot->guid.value > 1; } } sRandomPlayerbotMgr;
struct AreaTableEntry { char const* area_name[1] = {"Elwynn Forest"}; } area;
struct AreaStore { AreaTableEntry* LookupEntry(uint32) { return &area; } } sAreaTableStore;
struct WorldScript
{
    explicit WorldScript(char const*) { }
    virtual ~WorldScript() = default;
    virtual void OnAfterConfigLoad(bool) { }
    virtual void OnUpdate(uint32) { }
};
namespace ObjectAccessor
{
std::map<ObjectGuid, Player*> players;
auto const& GetPlayers() { return players; }
Player* FindPlayer(ObjectGuid guid)
{
    auto it = players.find(guid);
    return it == players.end() || !it->second->online ? nullptr : it->second;
}
}
PlayerbotAI* GetBotAI(Player* bot) { return &bot->ai; }
bool IsBotMasteredByRequester(Player*, Player* bot) { return bot->controlled; }
std::string ToLower(std::string value)
{
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) { return std::tolower(c); });
    return value;
}
// Communication adapters: strict ASCII inputs in these tests; integration uses the existing bridge helpers.
bool IsValidRequestToken(std::string const& value) { return !value.empty() && value.size() <= 64; }
std::string GetSafeErrorToken(std::vector<std::string> const& fields, std::size_t index)
{
    return index < fields.size() && IsValidRequestToken(fields[index]) ? fields[index] : "";
}
bool TryParseUint32Field(std::string const& value, uint32 min, uint32 max, uint32& out)
{
    if (value.empty() || value.find_first_not_of("0123456789") != std::string::npos || value.size() > 10)
        return false;
    auto number = std::stoull(value);
    if (number < min || number > max)
        return false;
    out = number;
    return true;
}
bool TryUrlDecodeField(std::string const& value, std::string& out, std::size_t max, bool empty)
{
    out = value;
    return value.size() <= max && (empty || !value.empty()) && value.find('%') == std::string::npos;
}
std::string UrlEncodeField(std::string const& value) { return value; }
std::vector<std::pair<std::string, std::string>> packets;
bool IsAddonPacketWithinBudget(std::string const& op, std::string const& value)
{
    return 5 + op.size() + 1 + value.size() <= 255;
}
void SendAddonPacket(Player*, int type, std::string const& op, std::string const& value)
{
    assert(type == CHAT_MSG_WHISPER);
    assert(IsAddonPacketWithinBudget(op, value));
    packets.emplace_back(op, value);
}
bool SendProtocolError(Player* p, int type, std::string const&, std::string const&, std::string const&, std::string const& reason)
{
    SendAddonPacket(p, type, "ERR", reason);
    return true;
}
#include "../src/RandomBotDirectory.inc"

int main()
{
    Player requester;
    ObjectAccessor::players.emplace(requester.guid, &requester);
    std::vector<Player> bots(2500);
    for (uint32 i = 0; i < bots.size(); ++i)
    {
        auto& bot = bots[i];
        bot.guid = i + 2;
        bot.name = "Bot" + std::to_string(10000 + i);
        bot.level = i % 80 + 1;
        bot.playerClass = i % 2 ? 5 : 1;
        ObjectAccessor::players.emplace(bot.guid, &bot);
    }
    RandomBotDirectoryWorldScript script;
    script.OnAfterConfigLoad(false);
    auto request = std::vector<std::string>{"RANDOMBOT_DIRECTORY", "one", "", "0", "1", "80", "0", "0", "0", "0", "NAME", "0", "ANY"};
    auto run = [&](std::string token)
    {
        request[1] = token;
        packets.clear();
        gRandomBotDirectoryRates.clear();
        QueueRandomBotDirectory(&requester, request);
        script.OnUpdate(500);
    };
    run("first");
    assert(packets.size() == 27);
    assert(packets.front().second == "first~0~2500~25~ONLINE_ONLY");
    assert(packets.back().first == "RBD_END");
    assert(packets[1].second.find("Bot10000") != std::string::npos);
    auto firstEntry = packets[1].second;
    request[9] = "1";
    run("second");
    assert(packets.front().second == "second~1~2500~25~ONLINE_ONLY");
    assert(packets[1].second.find("Bot10025") != std::string::npos);
    request[9] = "0";
    request[3] = "5";
    request[4] = "55";
    request[5] = "60";
    request[10] = "LEVEL";
    run("priests");
    assert(packets.size() > 2);
    for (std::size_t i = 1; i + 1 < packets.size(); ++i)
        assert(packets[i].second.find("~5~56~") != std::string::npos ||
            packets[i].second.find("~5~58~") != std::string::npos ||
            packets[i].second.find("~5~60~") != std::string::npos);
    request[2] = "absent";
    run("empty");
    assert(packets.size() == 2 && packets.front().second == "empty~0~0~0~ONLINE_ONLY");
    request[2] = "";
    request[7] = "2";
    run("offline");
    assert(packets.size() == 2 && packets.front().second == "offline~0~0~0~ONLINE_ONLY");
    request[7] = "0";
    run("rate");
    packets.clear();
    QueueRandomBotDirectory(&requester, request);
    assert(packets.back().second == "TOKEN_USED");
    request[1] = "newtoken";
    QueueRandomBotDirectory(&requester, request);
    assert(packets.back().second == "RATE_LIMIT");
    request[4] = "999999999999999999999";
    run("invalid");
    assert(packets.size() == 1 && packets.back().second == "BAD_FILTER");
    request[4] = "55";
    request.push_back("extra");
    run("extra");
    assert(packets.back().second == "BAD_FIELD_COUNT");
    request.pop_back();
    request[2] = std::string(49, 'a');
    run("oversized");
    assert(packets.back().second == "BAD_FILTER");
    request[2] = "";
    gRandomBotDirectoryEnabled = false;
    run("disabled");
    assert(packets.back().second == "DISABLED");
    gRandomBotDirectoryEnabled = true;
    Player& target = bots[0];
    assert(RandomBotInviteReason(&requester, &target) == "OK");
    Group group;
    target.group = &group;
    assert(RandomBotInviteReason(&requester, &target) == "OTHER_GROUP");
    requester.group = &group;
    assert(RandomBotInviteReason(&requester, &target) == "IN_YOUR_GROUP");
    target.group = nullptr;
    group.full = true;
    assert(RandomBotInviteReason(&requester, &target) == "GROUP_FULL");
    group.full = false;
    group.leader = false;
    assert(RandomBotInviteReason(&requester, &target) == "NOT_LEADER");
    requester.group = nullptr;
    target.team = 1;
    assert(RandomBotInviteReason(&requester, &target) == "WRONG_FACTION");
    target.team = 0;
    target.ai.security.level = 1;
    assert(RandomBotInviteReason(&requester, &target) == "PERMISSION_DENIED");
    target.ai.security.deny = PLAYERBOT_DENY_LOW_LEVEL;
    assert(RandomBotInviteReason(&requester, &target) == "LOW_LEVEL");
    target.bg = true;
    assert(RandomBotInviteReason(&requester, &target) == "BATTLEGROUND");
    target.bg = false;
    target.online = false;
    request[3] = "0"; request[4] = "1"; request[5] = "80";
    run("onlinecount");
    assert(packets.front().second == "onlinecount~0~2499~25~ONLINE_ONLY");
    // Cancelled/disconnected request cannot send a response into a later session/account.
    packets.clear(); gRandomBotDirectoryRates.clear(); request[1] = "logout";
    QueueRandomBotDirectory(&requester, request);
    requester.session.account = 2;
    script.OnUpdate(500);
    assert(packets.empty());
    requester.session.account = 1;
    // Bound queue memory and globally limit directory work, even across many requesters.
    gRandomBotDirectoryRates.clear(); packets.clear();
    std::vector<Player> requesters(17);
    for (uint32 i = 0; i < requesters.size(); ++i)
    {
        requesters[i].guid = 9000 + i;
        ObjectAccessor::players.emplace(requesters[i].guid, &requesters[i]);
        request[1] = "queue" + std::to_string(i);
        QueueRandomBotDirectory(&requesters[i], request);
    }
    assert(gRandomBotDirectoryQueue.size() == 16 && packets.back().second == "BUSY");
    script.OnUpdate(499);
    assert(gRandomBotDirectoryQueue.size() == 16);
    script.OnUpdate(1);
    assert(gRandomBotDirectoryQueue.size() == 15);
    gRandomBotDirectoryQueue.clear();
    for (auto const& player : requesters) ObjectAccessor::players.erase(player.guid);
    std::vector<RandomBotDirectory::Row> rows;
    for (auto const& bot : bots)
    {
        RandomBotDirectory::Row row;
        row.guid = bot.guid.value; row.name = bot.name; row.key = ToLower(bot.name);
        row.playerClass = bot.playerClass; row.level = bot.level; row.faction = bot.team + 1;
        row.reason = bot.guid.value % 3 ? "OK" : "OTHER_GROUP";
        rows.push_back(row);
    }
    RandomBotDirectory::Query query;
    for (std::string sort : {"NAME", "LEVEL", "CLASS"})
    {
        query.sort = sort; query.descending = false;
        auto asc = RandomBotDirectory::Select(rows, query);
        query.descending = true;
        auto desc = RandomBotDirectory::Select(rows, query);
        for (std::size_t i = 0; i < asc.size(); ++i)
            assert(asc[i].guid == desc[desc.size() - i - 1].guid);
    }
    query.invite = 1;
    auto eligible = RandomBotDirectory::Select(rows, query);
    for (auto const& row : eligible) assert(row.reason == "OK");
    query.invite = 2; query.faction = 1; query.name = "bot100";
    auto filtered = RandomBotDirectory::Select(rows, query);
    for (auto const& row : filtered) assert(row.reason != "OK" && row.faction == 1 && row.key.find(query.name) != std::string::npos);
    auto start = std::chrono::steady_clock::now();
    for (int i = 0; i < 100; ++i)
    {
        query = {}; query.sort = i % 2 ? "CLASS" : "LEVEL";
        assert(RandomBotDirectory::Select(rows, query).size() == 2500);
    }
    auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
    std::cout << "PASS: server directory/pagination/filters/sorts/preflight/validation/rate/replay/disconnect; 100 x 2500 select+sort: " << ms << " ms\n";
}
