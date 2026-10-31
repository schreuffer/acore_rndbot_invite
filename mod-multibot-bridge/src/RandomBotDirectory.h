#ifndef MULTIBOT_RANDOM_BOT_DIRECTORY_H
#define MULTIBOT_RANDOM_BOT_DIRECTORY_H

#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>

namespace RandomBotDirectory
{
constexpr std::size_t PageSize = 25;

struct Row
{
    uint32_t guid = 0;
    std::string name;
    std::string key;
    uint32_t level = 0;
    uint32_t playerClass = 0;
    uint32_t race = 0;
    uint32_t faction = 0; // 1 Alliance, 2 Horde
    uint32_t zone = 0;
    std::string zoneName;
    bool grouped = false;
    bool controlled = false;
    std::string reason;
};

struct Query
{
    std::string name;
    uint32_t playerClass = 0;
    uint32_t minLevel = 1;
    uint32_t maxLevel = 80;
    uint32_t faction = 0;
    uint32_t status = 0; // 0 all available, 1 online, 2 offline (empty in V1)
    uint32_t invite = 0; // 0 all, 1 eligible, 2 ineligible
    uint32_t page = 0;
    std::string sort = "NAME";
    bool descending = false;
};

inline bool MatchesBase(Row const& row, Query const& query)
{
    return query.status != 2 && row.key.find(query.name) != std::string::npos &&
        (!query.playerClass || row.playerClass == query.playerClass) &&
        row.level >= query.minLevel && row.level <= query.maxLevel &&
        (!query.faction || row.faction == query.faction);
}

inline std::vector<Row> Select(std::vector<Row> rows, Query const& query)
{
    rows.erase(std::remove_if(rows.begin(), rows.end(), [&query](Row const& row)
    {
        return !MatchesBase(row, query) || (query.invite == 1 && row.reason != "OK") ||
            (query.invite == 2 && row.reason == "OK");
    }), rows.end());
    std::sort(rows.begin(), rows.end(), [&query](Row const& left, Row const& right)
    {
        int order = 0;
        if (query.sort == "LEVEL" && left.level != right.level)
            order = left.level < right.level ? -1 : 1;
        else if (query.sort == "CLASS" && left.playerClass != right.playerClass)
            order = left.playerClass < right.playerClass ? -1 : 1;
        else if (left.key != right.key)
            order = left.key < right.key ? -1 : 1;
        else if (left.guid != right.guid)
            order = left.guid < right.guid ? -1 : 1;
        return query.descending ? order > 0 : order < 0;
    });
    return rows;
}
}
#endif
