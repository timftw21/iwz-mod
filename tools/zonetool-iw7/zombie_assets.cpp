// IW7 stock-asset repacking extensions for x64-zt (GPL-3.0).
#include "std_include.hpp"
#include "zombie_assets.hpp"

namespace zonetool::iw7
{
    namespace
    {
        template<class T> T* copy_array(zone_memory* mem, const T* source, const unsigned int count)
        {
            if (!source) return nullptr;
            if (count > 65535) throw std::runtime_error("Invalid animation array count");
            auto* copy = mem->allocate<T>(count);
            if (count) std::memcpy(copy, source, sizeof(T) * count);
            return copy;
        }

        std::string text(scr_string_t value)
        {
            if (!value) return {};
            const auto* name = SL_ConvertToString(value);
            if (!name) throw std::runtime_error("Invalid animation script string");
            return name;
        }

        template<class T> void write_array(zone_buffer* buf, T* source, T** destination,
            const unsigned int count, const unsigned int alignment = 3)
        {
            if (!source) return;
            buf->align(alignment);
            buf->write(source, count);
            buf->clear_pointer(destination);
        }

        ordered_json string_array(const scr_string_t* values, const unsigned int count)
        {
            if (!values) return nullptr;
            auto result = ordered_json::array();
            for (unsigned int i = 0; i < count; ++i) result.push_back(text(values[i]));
            return result;
        }

        void save_json(const std::string& path, const ordered_json& data)
        {
            auto file = filesystem::file(path);
            file.open("wb");
            file.write(data.dump(2));
            file.close();
        }
    }

    void iwz_anim_class::remember(scr_string_t& value)
    {
        strings_.emplace_back(&value, text(value));
    }

    void iwz_anim_class::init(const std::string& name, zone_memory* mem)
    {
        name_ = name;
        if (referenced())
        {
            asset_ = mem->allocate<AnimationClass>();
            asset_->className = mem->duplicate_string(name);
            return;
        }
        // Clone every owned array before prepare remaps script strings. The donor stays intact.
        const auto* source = reinterpret_cast<AnimationClass*>(db_find_x_asset_header_safe(ASSET_TYPE_ANIMCLASS, name).data);
        if (!source) throw std::runtime_error("Animation class donor is not loaded: " + name);
        asset_ = copy_array(mem, source, 1);
        asset_->className = mem->duplicate_string(name);
        remember(asset_->animTree);
        asset_->stateMachine = copy_array(mem, source->stateMachine, 1);
        if (auto* machine = asset_->stateMachine)
        {
            remember(machine->name);
            machine->states = copy_array(mem, machine->states, machine->stateCount);
            for (unsigned int i = 0; i < machine->stateCount; ++i)
            {
                auto& state = machine->states[i];
                const auto entries = static_cast<unsigned char>(state.entryCount);
                const auto aliases = static_cast<unsigned char>(state.aliasCount);
                remember(state.name);
                remember(state.notify);
                state.animEntries = copy_array(mem, state.animEntries, entries);
                state.animIndices = copy_array(mem, state.animIndices, entries);
                state.aliasList = copy_array(mem, state.aliasList, aliases);
                for (unsigned int j = 0; j < entries; ++j) remember(state.animEntries[j].animName);
                for (unsigned int j = 0; j < aliases; ++j)
                {
                    auto& alias = state.aliasList[j];
                    remember(alias.aliasName);
                    alias.aliasInfo = copy_array(mem, alias.aliasInfo, static_cast<unsigned char>(alias.animCount));
                }
            }
            machine->aimSets = copy_array(mem, machine->aimSets, machine->aimSetCount);
            for (unsigned int i = 0; i < machine->aimSetCount; ++i)
            {
                auto& aim = machine->aimSets[i];
                remember(aim.name);
                remember(aim.rootName);
                aim.animName = copy_array(mem, aim.animName, aim.animCount);
                aim.animIndices = copy_array(mem, aim.animIndices, aim.animCount);
                aim.aimNodeIndices = copy_array(mem, aim.aimNodeIndices, aim.animCount);
                for (int j = 0; j < aim.animCount; ++j) remember(aim.animName[j]);
            }
        }
        for (auto** values : {&asset_->soundNotes, &asset_->soundNames, &asset_->soundOptions})
        {
            *values = copy_array(mem, *values, asset_->soundCount);
            if (*values) for (unsigned int i = 0; i < asset_->soundCount; ++i) remember((*values)[i]);
        }
        for (auto** values : {&asset_->effectNotes, &asset_->effectTags})
        {
            *values = copy_array(mem, *values, asset_->effectCount);
            if (*values) for (unsigned int i = 0; i < asset_->effectCount; ++i) remember((*values)[i]);
        }
        asset_->effectDefs = copy_array(mem, asset_->effectDefs, asset_->effectCount);
        ZONETOOL_INFO("[IWZ][ZombieAssets] cloned animclass=%s tree=%s scriptStrings=%zu", name.c_str(), text(asset_->animTree).c_str(), strings_.size());
    }

    void iwz_anim_class::prepare(zone_buffer* buf, zone_memory*)
    {
        for (auto& [value, name] : strings_) *value = static_cast<scr_string_t>(buf->write_scriptstring(name.empty() ? nullptr : name.c_str()));
    }

    void iwz_anim_class::load_depending(zone_base* zone)
    {
        if (referenced()) return;
        if (asset_->scriptable) zone->add_asset_of_type(ASSET_TYPE_SCRIPTABLE, asset_->scriptable->name);
        if (asset_->animTree) zone->add_asset_of_type(ASSET_TYPE_RAWFILE, "animtrees/" + text(asset_->animTree));
        if (asset_->effectDefs) for (unsigned int i = 0; i < asset_->effectCount; ++i)
        {
            const auto& fx = asset_->effectDefs[i];
            if (fx.u.data) zone->add_asset_of_type(fx.type == FX_COMBINED_VFX ? ASSET_TYPE_VFX : ASSET_TYPE_FX, fx.u.fx->name);
        }
        // State entries refer to animation-tree node names; the ATR's actual clip assets
        // are added by the bundle manifest. They need not match XAnimParts asset names.
    }

    void iwz_anim_class::write(zone_base* zone, zone_buffer* buf)
    {
        auto* data = asset_;
        auto* dest = buf->write(data);
        buf->push_stream(XFILE_BLOCK_VIRTUAL);
        dest->className = buf->write_str(name_);
        if (auto* machine = data->stateMachine)
        {
            buf->align(7);
            auto* out = buf->write(machine);
            if (machine->states)
            {
                buf->align(7);
                auto* states = buf->write(machine->states, machine->stateCount);
                for (unsigned int i = 0; i < machine->stateCount; ++i)
                {
                    auto& state = machine->states[i];
                    const auto entries = static_cast<unsigned char>(state.entryCount);
                    write_array(buf, state.animEntries, &states[i].animEntries, entries);
                    buf->push_stream(XFILE_BLOCK_RUNTIME);
                    write_array(buf, state.animIndices, &states[i].animIndices, entries, 7);
                    buf->pop_stream();
                    if (state.aliasList)
                    {
                        buf->align(7);
                        const auto count = static_cast<unsigned char>(state.aliasCount);
                        auto* aliases = buf->write(state.aliasList, count);
                        for (unsigned int j = 0; j < count; ++j)
                            write_array(buf, state.aliasList[j].aliasInfo, &aliases[j].aliasInfo,
                                static_cast<unsigned char>(state.aliasList[j].animCount));
                        buf->clear_pointer(&states[i].aliasList);
                    }
                }
                buf->clear_pointer(&out->states);
            }
            if (machine->aimSets)
            {
                buf->align(7);
                auto* aims = buf->write(machine->aimSets, machine->aimSetCount);
                for (unsigned int i = 0; i < machine->aimSetCount; ++i)
                {
                    auto& aim = machine->aimSets[i];
                    write_array(buf, aim.animName, &aims[i].animName, aim.animCount);
                    buf->push_stream(XFILE_BLOCK_RUNTIME);
                    write_array(buf, aim.animIndices, &aims[i].animIndices, aim.animCount, 7);
                    write_array(buf, aim.aimNodeIndices, &aims[i].aimNodeIndices, aim.animCount, 7);
                    buf->pop_stream();
                }
                buf->clear_pointer(&out->aimSets);
            }
            buf->clear_pointer(&dest->stateMachine);
        }
        if (data->scriptable) dest->scriptable = reinterpret_cast<ScriptableDef*>(zone->get_asset_pointer(ASSET_TYPE_SCRIPTABLE, data->scriptable->name));
        write_array(buf, data->soundNotes, &dest->soundNotes, data->soundCount);
        write_array(buf, data->soundNames, &dest->soundNames, data->soundCount);
        write_array(buf, data->soundOptions, &dest->soundOptions, data->soundCount);
        write_array(buf, data->effectNotes, &dest->effectNotes, data->effectCount);
        if (data->effectDefs)
        {
            buf->align(7);
            auto* effects = buf->write(data->effectDefs, data->effectCount);
            for (unsigned int i = 0; i < data->effectCount; ++i)
                if (data->effectDefs[i].u.data)
                    effects[i].u.data = zone->get_asset_pointer(data->effectDefs[i].type == FX_COMBINED_VFX ? ASSET_TYPE_VFX : ASSET_TYPE_FX, data->effectDefs[i].u.fx->name);
            buf->clear_pointer(&dest->effectDefs);
        }
        write_array(buf, data->effectTags, &dest->effectTags, data->effectCount);
        buf->pop_stream();
    }

    void iwz_anim_class::dump(AnimationClass* asset)
    {
        ordered_json doc = {{"name", asset->className}, {"controller", asset->animCtrl}, {"animTree", text(asset->animTree)},
            {"scriptable", asset->scriptable ? asset->scriptable->name : ""},
            {"soundNotes", string_array(asset->soundNotes, asset->soundCount)},
            {"soundNames", string_array(asset->soundNames, asset->soundCount)},
            {"soundOptions", string_array(asset->soundOptions, asset->soundCount)},
            {"effectNotes", string_array(asset->effectNotes, asset->effectCount)},
            {"effectTags", string_array(asset->effectTags, asset->effectCount)}};
        doc["effects"] = ordered_json::array();
        if (asset->effectDefs) for (unsigned int i = 0; i < asset->effectCount; ++i)
        {
            const auto& fx = asset->effectDefs[i];
            doc["effects"].push_back({{"type", fx.type}, {"name", fx.u.data ? fx.u.fx->name : ""}});
        }
        doc["stateMachine"] = nullptr;
        if (const auto* sm = asset->stateMachine)
        {
            ordered_json machine = {{"name", text(sm->name)}, {"states", ordered_json::array()}, {"aimSets", ordered_json::array()}};
            for (unsigned int i = 0; i < sm->stateCount; ++i)
            {
                const auto& s = sm->states[i];
                ordered_json state = {{"name", text(s.name)}, {"notify", text(s.notify)},
                    {"blendTime", s.blendTime}, {"blendOutTime", s.blendOutTime}, {"flags", static_cast<unsigned char>(s.flags)},
                    {"aimSetIndex", s.aimSetIndex}, {"entries", ordered_json::array()}, {"aliases", ordered_json::array()},
                    {"runtimeIndices", s.animIndices != nullptr}};
                for (unsigned int j = 0; j < static_cast<unsigned char>(s.entryCount); ++j)
                    state["entries"].push_back({{"animation", text(s.animEntries[j].animName)}, {"aimSetIndex", s.animEntries[j].aimSetIndex}});
                for (unsigned int j = 0; j < static_cast<unsigned char>(s.aliasCount); ++j)
                {
                    const auto& a = s.aliasList[j];
                    ordered_json alias = {{"name", text(a.aliasName)}, {"entries", ordered_json::array()}};
                    for (unsigned int k = 0; k < static_cast<unsigned char>(a.animCount); ++k)
                        alias["entries"].push_back({{"index", static_cast<unsigned char>(a.aliasInfo[k].animIndex)}, {"weight", a.aliasInfo[k].animWeight}});
                    state["aliases"].push_back(alias);
                }
                machine["states"].push_back(state);
            }
            for (unsigned int i = 0; i < sm->aimSetCount; ++i)
            {
                const auto& a = sm->aimSets[i];
                machine["aimSets"].push_back({{"name", text(a.name)}, {"root", text(a.rootName)},
                    {"animations", string_array(a.animName, a.animCount)},
                    {"runtimeIndices", a.animIndices != nullptr}, {"runtimeAimIndices", a.aimNodeIndices != nullptr}});
            }
            doc["stateMachine"] = machine;
        }
        save_json("animclass/"s + asset->className + ".json", doc);
    }

    void iwz_behavior_tree::init(const std::string& name, zone_memory* mem)
    {
        name_ = name;
        if (referenced()) asset_ = mem->allocate<BehaviorTree>();
        else
        {
            auto* source = reinterpret_cast<BehaviorTree*>(db_find_x_asset_header_safe(ASSET_TYPE_BEHAVIOR_TREE, name).data);
            if (!source) throw std::runtime_error("Behavior tree donor is not loaded: " + name);
            asset_ = copy_array(mem, source, 1);
            asset_->nodes = copy_array(mem, source->nodes, source->nodeCount);
        }
        asset_->name = mem->duplicate_string(name);
        ZONETOOL_INFO("[IWZ][ZombieAssets] cloned behaviorTree=%s nodes=%u", name.c_str(), asset_->nodeCount);
    }

    void iwz_behavior_tree::write(zone_base*, zone_buffer* buf)
    {
        auto* dest = buf->write(asset_);
        buf->push_stream(XFILE_BLOCK_VIRTUAL);
        dest->name = buf->write_str(name_);
        if (asset_->nodes)
        {
            buf->align(7);
            auto* nodes = buf->write(asset_->nodes, asset_->nodeCount);
            for (unsigned int i = 0; i < asset_->nodeCount; ++i)
                if (asset_->nodes[i].name) nodes[i].name = buf->write_str(asset_->nodes[i].name);
            buf->clear_pointer(&dest->nodes);
        }
        buf->pop_stream();
    }

    void iwz_behavior_tree::dump(BehaviorTree* asset)
    {
        ordered_json doc = {{"name", asset->name}, {"nodes", ordered_json::array()}};
        for (unsigned int i = 0; i < asset->nodeCount; ++i)
        {
            std::vector<unsigned char> payload(std::begin(asset->nodes[i].__pad0), std::end(asset->nodes[i].__pad0));
            doc["nodes"].push_back({{"name", asset->nodes[i].name ? asset->nodes[i].name : ""}, {"payload", payload}});
        }
        save_json("behaviortree/"s + asset->name + ".json", doc);
    }
}
