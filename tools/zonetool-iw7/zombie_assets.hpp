// IW7 stock-asset repacking extensions for x64-zt (GPL-3.0).
#pragma once
#include "../zonetool.hpp"

namespace zonetool::iw7
{
    class iwz_anim_class final : public asset_interface
    {
        std::string name_;
        AnimationClass* asset_ = nullptr;
        std::vector<std::pair<scr_string_t*, std::string>> strings_;
        void remember(scr_string_t& value);
    public:
        void init(const std::string& name, zone_memory* mem) override;
        void prepare(zone_buffer* buf, zone_memory* mem) override;
        void load_depending(zone_base* zone) override;
        void* pointer() override { return asset_; }
        bool referenced() override { return name_.starts_with(","); }
        std::string name() override { return name_; }
        std::int32_t type() override { return ASSET_TYPE_ANIMCLASS; }
        void write(zone_base* zone, zone_buffer* buf) override;
        static void dump(AnimationClass* asset);
    };

    class iwz_behavior_tree final : public asset_interface
    {
        std::string name_;
        BehaviorTree* asset_ = nullptr;
    public:
        void init(const std::string& name, zone_memory* mem) override;
        void prepare(zone_buffer*, zone_memory*) override {}
        void load_depending(zone_base*) override {}
        void* pointer() override { return asset_; }
        bool referenced() override { return name_.starts_with(","); }
        std::string name() override { return name_; }
        std::int32_t type() override { return ASSET_TYPE_BEHAVIOR_TREE; }
        void write(zone_base* zone, zone_buffer* buf) override;
        static void dump(BehaviorTree* asset);
    };
}
