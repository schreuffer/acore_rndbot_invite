// Included inside the bridge namespace: reuse strict fields, framing and error helpers.
// Only value data crosses from chat handlers to the world-thread request processor.
std::atomic<bool> gRandomBotDirectoryEnabled{false};
std::mutex gRandomBotDirectoryMutex;
struct RandomBotDirectoryRequest
{
    ObjectGuid requester;
    uint32 account = 0;
    std::string token;
    RandomBotDirectory::Query query;
};
struct RandomBotDirectoryRate
{
    std::chrono::steady_clock::time_point last;
    std::deque<std::pair<std::string, std::chrono::steady_clock::time_point>> tokens;
};
std::deque<RandomBotDirectoryRequest> gRandomBotDirectoryQueue;
std::map<ObjectGuid, RandomBotDirectoryRate> gRandomBotDirectoryRates;

bool QueueRandomBotDirectory(Player* player, std::vector<std::string> const& fields)
{
    std::string const token = GetSafeErrorToken(fields, 1);
    auto fail = [&](std::string const& reason)
    {
        // Directory data is private even when the request arrived on PARTY/RAID.
        return SendProtocolError(player, CHAT_MSG_WHISPER, "GET", "RANDOMBOT_DIRECTORY", token, reason);
    };
    if (!gRandomBotDirectoryEnabled.load())
        return fail("DISABLED");
    if (fields.size() != 13)
        return fail("BAD_FIELD_COUNT");
    if (!IsValidRequestToken(fields[1]))
        return fail("BAD_TOKEN");
    RandomBotDirectory::Query query;
    uint32 descending = 0;
    if (!TryUrlDecodeField(fields[2], query.name, 48, true) ||
        !TryParseUint32Field(fields[3], 0, 11, query.playerClass) || query.playerClass == 10 ||
        !TryParseUint32Field(fields[4], 1, 80, query.minLevel) ||
        !TryParseUint32Field(fields[5], query.minLevel, 80, query.maxLevel) ||
        !TryParseUint32Field(fields[6], 0, 2, query.faction) ||
        !TryParseUint32Field(fields[7], 0, 2, query.status) ||
        !TryParseUint32Field(fields[8], 0, 2, query.invite) ||
        !TryParseUint32Field(fields[9], 0, 100000, query.page) ||
        (fields[10] != "NAME" && fields[10] != "LEVEL" && fields[10] != "CLASS") ||
        !TryParseUint32Field(fields[11], 0, 1, descending) || fields[12] != "ANY")
        return fail("BAD_FILTER");
    if (!player || !player->GetSession() || !player->IsInWorld())
        return fail("NO_SESSION");
    query.name = ToLower(query.name);
    query.sort = fields[10];
    query.descending = descending != 0;
    std::string rejection;
    {
        std::lock_guard<std::mutex> guard(gRandomBotDirectoryMutex);
        auto const now = std::chrono::steady_clock::now();
        for (auto it = gRandomBotDirectoryRates.begin(); it != gRandomBotDirectoryRates.end();)
        {
            if (now - it->second.last >= std::chrono::seconds(60))
                it = gRandomBotDirectoryRates.erase(it);
            else
                ++it;
        }
        auto it = gRandomBotDirectoryRates.find(player->GetGUID());
        if (it == gRandomBotDirectoryRates.end() && gRandomBotDirectoryRates.size() >= 512)
            rejection = "BUSY";
        else
        {
            auto& rate = gRandomBotDirectoryRates[player->GetGUID()];
            while (!rate.tokens.empty() && now - rate.tokens.front().second >= std::chrono::seconds(60))
                rate.tokens.pop_front();
            bool const replay = std::any_of(rate.tokens.begin(), rate.tokens.end(), [&](auto const& entry)
            {
                return entry.first == token;
            });
            if (replay)
                rejection = "TOKEN_USED";
            else if (now - rate.last < std::chrono::seconds(3))
                rejection = "RATE_LIMIT";
            else if (gRandomBotDirectoryQueue.size() >= 16)
                rejection = "BUSY";
            else
            {
                rate.last = now;
                rate.tokens.emplace_back(token, now);
                gRandomBotDirectoryQueue.push_back(
                    {player->GetGUID(), player->GetSession()->GetAccountId(), token, query});
            }
        }
    }
    return rejection.empty() ? true : fail(rejection);
}

std::string RandomBotInviteReason(Player* requester, Player* bot)
{
    if (bot->InBattleground() || requester->InBattleground())
        return "BATTLEGROUND";
    if (bot->IsBeingTeleported())
        return "BUSY";
    if (bot->GetGroup())
        return bot->GetGroup() == requester->GetGroup() ? "IN_YOUR_GROUP" : "OTHER_GROUP";
    if (bot->GetGroupInvite())
        return "PENDING_INVITE";
    Group* group = requester->GetGroup();
    if (!group)
        group = requester->GetGroupInvite();
    if (group && group->IsFull())
        return "GROUP_FULL";
    if (group && !group->IsLeader(requester->GetGUID()) && !group->IsAssistant(requester->GetGUID()))
        return "NOT_LEADER";
    if (!requester->IsGameMaster() && !sWorld->getBoolConfig(CONFIG_ALLOW_TWO_SIDE_INTERACTION_GROUP) &&
        requester->GetTeamId() != bot->GetTeamId())
        return "WRONG_FACTION";
    PlayerbotAI* ai = GetBotAI(bot);
    if (!ai || !ai->GetSecurity())
        return "PERMISSION_DENIED";
    DenyReason deny = PLAYERBOT_DENY_NONE;
    if (ai->GetSecurity()->LevelFor(requester, &deny) < PLAYERBOT_SECURITY_INVITE)
    {
        switch (deny)
        {
            case PLAYERBOT_DENY_LOW_LEVEL: return "LOW_LEVEL";
            case PLAYERBOT_DENY_GEARSCORE: return "GEARSCORE";
            case PLAYERBOT_DENY_OPPOSING: return "WRONG_FACTION";
            case PLAYERBOT_DENY_BG: return "BG_QUEUE";
            default: return "PERMISSION_DENIED";
        }
    }
    return "OK"; // Preflight only: InviteUnit invokes all native core/hooks/accept checks again.
}

void SendRandomBotDirectory(RandomBotDirectoryRequest const& request, Player* player)
{
    std::vector<RandomBotDirectory::Row> rows;
    // WorldScript::OnUpdate is after MapMgr::Update's worker wait. No Player* retained.
    for (auto const& entry : ObjectAccessor::GetPlayers())
    {
        Player* bot = entry.second;
        if (!bot || bot == player || !bot->IsInWorld() || !sRandomPlayerbotMgr.IsRandomBot(bot) || !GetBotAI(bot))
            continue;
        RandomBotDirectory::Row row;
        row.guid = bot->GetGUID().GetCounter();
        row.name = bot->GetName();
        row.key = ToLower(row.name);
        row.level = bot->GetLevel();
        row.playerClass = bot->getClass();
        row.race = bot->getRace();
        row.faction = bot->GetTeamId() == TEAM_ALLIANCE ? 1 : 2;
        if (!RandomBotDirectory::MatchesBase(row, request.query))
            continue;
        row.zone = bot->GetZoneId();
        if (AreaTableEntry const* area = sAreaTableStore.LookupEntry(row.zone))
            row.zoneName = area->area_name[LOCALE_enUS];
        row.grouped = bot->GetGroup() != nullptr;
        row.controlled = IsBotMasteredByRequester(player, bot);
        row.reason = RandomBotInviteReason(player, bot);
        rows.push_back(std::move(row));
    }
    rows = RandomBotDirectory::Select(std::move(rows), request.query);
    std::size_t const first = std::min(rows.size(), request.query.page * RandomBotDirectory::PageSize);
    std::size_t const count = std::min(RandomBotDirectory::PageSize, rows.size() - first);
    std::vector<std::string> packets;
    for (std::size_t i = first; i < first + count; ++i)
    {
        auto const& row = rows[i];
        std::ostringstream out;
        out << request.token << '~' << row.guid << '~' << UrlEncodeField(row.name) << '~'
            << row.playerClass << '~' << row.level << '~' << row.race << '~' << row.faction
            << "~UNKNOWN~ONLINE~" << row.zone << '~' << row.grouped << '~' << row.controlled << '~' << row.reason;
        if (!IsAddonPacketWithinBudget("RBD_ENTRY", out.str() + '~'))
        {
            SendProtocolError(player, CHAT_MSG_WHISPER, "GET", "RANDOMBOT_DIRECTORY", request.token, "TOO_LARGE");
            return;
        }
        // Area display names may expand substantially under percent encoding.
        // Keep numeric zone truth even if the optional display label will not fit.
        std::string named = out.str() + '~' + UrlEncodeField(row.zoneName);
        if (row.zoneName.size() > 128 || !IsAddonPacketWithinBudget("RBD_ENTRY", named))
            named = out.str() + '~';
        packets.push_back(std::move(named));
    }
    std::ostringstream framing;
    framing << request.token << '~' << request.query.page << '~' << rows.size() << '~' << count << "~ONLINE_ONLY";
    SendAddonPacket(player, CHAT_MSG_WHISPER, "RBD_BEGIN", framing.str());
    for (auto const& packet : packets)
        SendAddonPacket(player, CHAT_MSG_WHISPER, "RBD_ENTRY", packet);
    SendAddonPacket(player, CHAT_MSG_WHISPER, "RBD_END", framing.str());
}

class RandomBotDirectoryWorldScript final : public WorldScript
{
public:
    RandomBotDirectoryWorldScript() : WorldScript("RandomBotDirectoryWorldScript") { }

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        gRandomBotDirectoryEnabled.store(
            sConfigMgr->GetOption<bool>("MultiBotBridge.RandomBotDirectory.Enable", false));
    }

    void OnUpdate(uint32 diff) override
    {
        // Global work/output budget: at most one page every 500 ms, no background scans.
        elapsed = std::min<uint32>(elapsed + diff, 500);
        if (elapsed < 500)
            return;
        RandomBotDirectoryRequest request;
        {
            std::lock_guard<std::mutex> guard(gRandomBotDirectoryMutex);
            if (gRandomBotDirectoryQueue.empty())
                return;
            request = std::move(gRandomBotDirectoryQueue.front());
            gRandomBotDirectoryQueue.pop_front();
        }
        elapsed = 0;
        Player* player = ObjectAccessor::FindPlayer(request.requester);
        if (!player || !player->GetSession() || player->GetSession()->GetAccountId() != request.account)
            return;
        if (!gRandomBotDirectoryEnabled.load())
        {
            SendProtocolError(player, CHAT_MSG_WHISPER, "GET", "RANDOMBOT_DIRECTORY", request.token, "DISABLED");
            return;
        }
        SendRandomBotDirectory(request, player);
    }

private:
    uint32 elapsed = 0;
};
