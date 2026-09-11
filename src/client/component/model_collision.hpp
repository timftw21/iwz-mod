#pragma once

namespace database { struct XModel; }

namespace model_collision
{
	const char* source_name(const char* name);
	database::XModel* resolve(const char* name, database::XModel* source);
	void on_model_loaded(const database::XModel* model);
}
