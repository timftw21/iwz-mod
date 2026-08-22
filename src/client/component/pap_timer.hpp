#pragma once

#include "game/game.hpp"

namespace pap_timer
{
	const char* get_zone_name();
	bool requires_housing(const char* zone_name);
	void on_asset_loaded(game::XAssetType type, game::XAssetHeader header, const char* source_zone);
}
