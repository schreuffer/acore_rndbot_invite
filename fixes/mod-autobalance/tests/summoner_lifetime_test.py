#!/usr/bin/env python3
"""Exercise the actual clone-check function with a despawned summoner under ASan/UBSan.
Native adapters are fakes; run with --baseline to reproduce the old dangling-pointer failure.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
path = 'src/ABAllCreatureScript.cpp'
source = (subprocess.check_output(['git', '-C', str(root), 'show', '1d707cb:' + path], text=True)
          if '--baseline' in sys.argv else (root / path).read_text())
function = source[source.index('bool AutoBalance_AllCreatureScript::_isSummonCloneOfSummoner('):]
harness = r'''
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <iostream>
#include <string>
#include <unordered_map>
#include <vector>
#define LOG_DEBUG(...) ((void)0)
using int8 = int8_t;
struct Creature;
struct AutoBalanceCreatureInfo
{
    unsigned summonerGuid = 0;
    Creature* summoner = nullptr; // Present only to compile/reproduce the old implementation.
    int selectedLevel = 60;
};
struct Data
{
    AutoBalanceCreatureInfo info;
    template<class T> T* GetDefault(char const*) { return &info; }
};
struct Creature
{
    bool IsSummon() const { return summoned; }
    unsigned GetEntry() const { return entry; }
    int GetLevel() const { return 60; }
    unsigned GetMaxHealth() const { return health; }
    unsigned GetCreatureType() const { return type; }
    std::string const& GetName() const { return name; }
    unsigned GetDisplayId() const { return display; }
    Data CustomData;
    bool summoned = true;
    unsigned entry = 10, health = 100, type = 1, display = 5;
    std::string name = "Clone";
};
namespace ObjectAccessor
{
    std::unordered_map<unsigned, Creature*> creatures;
    Creature* GetCreature(Creature const&, unsigned guid)
    {
        auto it = creatures.find(guid);
        return it == creatures.end() ? nullptr : it->second;
    }
}
std::vector<unsigned> creatureIDsThatAreNotClones = {99};
struct AutoBalance_AllCreatureScript
{
    bool _isSummonCloneOfSummoner(Creature* summon);
};
'''
harness += function
harness += r'''
int main()
{
    AutoBalance_AllCreatureScript script;
    Creature soul;
    assert(!script._isSummonCloneOfSummoner(nullptr));
    assert(!script._isSummonCloneOfSummoner(&soul));
    auto* owner = new Creature;
    soul.CustomData.info.summonerGuid = 42;
    soul.CustomData.info.summoner = owner;
    ObjectAccessor::creatures[42] = owner;
    assert(script._isSummonCloneOfSummoner(&soul));
    soul.entry = 99;
    assert(!script._isSummonCloneOfSummoner(&soul));
    soul.entry = 11; soul.health = 1; soul.type = 2; soul.name = "Different"; soul.display = 8;
    assert(!script._isSummonCloneOfSummoner(&soul));
    soul.summoned = false;
    assert(!script._isSummonCloneOfSummoner(&soul));
    soul.summoned = true;
    // The summoned soul outlives its original creature and later changes entry.
    ObjectAccessor::creatures.erase(42);
    delete owner;
    soul.entry = 11136;
    assert(!script._isSummonCloneOfSummoner(&soul));
    std::cout << "PASS: missing/live/despawned summoner, clone/nonclone and exclusion cases\n";
}
'''
with tempfile.TemporaryDirectory(prefix='autobalance-lifetime-') as directory:
    test = Path(directory) / 'test.cpp'
    test.write_text(harness)
    binary = Path(directory) / 'test'
    subprocess.run(['c++', '-std=c++20', '-g', '-O1', '-Wall', '-Wextra', '-Werror',
                    '-fsanitize=address,undefined', '-fno-omit-frame-pointer', str(test), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
