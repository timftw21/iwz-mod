#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "console/console.hpp"
#include "game/game.hpp"

#include <utils/hook.hpp>
#include <utils/string.hpp>

constexpr auto MAX_COLOR_INDEX = 15;

namespace colors
{
	struct hsv_color
	{
		unsigned char h;
		unsigned char s;
		unsigned char v;
	};

	namespace
	{
		constexpr DWORD rgba(const unsigned int r, const unsigned int g, const unsigned int b,
			const unsigned int a = 255)
		{
			return static_cast<DWORD>(r)
				| (static_cast<DWORD>(g) << 8)
				| (static_cast<DWORD>(b) << 16)
				| (static_cast<DWORD>(a) << 24);
		}

		// The first eight entries are the values from IW's renderer color table.
		// Entries 8-12 are resolved dynamically below; 13-15 are iw7-mod extensions.
		constexpr std::array color_table{
			rgba(0, 0, 0),       // ^0 black
			rgba(255, 92, 92),   // ^1 red
			rgba(0, 255, 0),     // ^2 green
			rgba(230, 200, 25),  // ^3 yellow
			rgba(0, 0, 255),     // ^4 blue
			rgba(0, 255, 255),   // ^5 cyan
			rgba(255, 92, 255),  // ^6 magenta
			rgba(255, 255, 255), // ^7 white
			rgba(0, 0, 0),       // ^8 friendly team color
			rgba(0, 0, 0),       // ^9 enemy team color
			rgba(0, 0, 0),       // ^: rainbow
			rgba(0, 0, 0),       // ^; facebook blue
			rgba(0, 0, 0),       // ^< sky blue
			rgba(255, 173, 34),  // ^= orange
			rgba(151, 80, 221),  // ^> purple
			rgba(205, 133, 63),  // ^? brown
		};

		DWORD hsv_to_rgb(const hsv_color hsv)
		{
			DWORD rgb;

			if (hsv.s == 0)
			{
				return rgba(hsv.v, hsv.v, hsv.v);
			}

			// converting to 16 bit to prevent overflow
			const unsigned int h = hsv.h;
			const unsigned int s = hsv.s;
			const unsigned int v = hsv.v;

			const auto region = static_cast<uint8_t>(h / 43);
			const auto remainder = (h - (region * 43)) * 6;

			const auto p = static_cast<uint8_t>((v * (255 - s)) >> 8);
			const auto q = static_cast<uint8_t>(
				(v * (255 - ((s * remainder) >> 8))) >> 8);
			const auto t = static_cast<uint8_t>(
				(v * (255 - ((s * (255 - remainder)) >> 8))) >> 8);

			switch (region)
			{
			case 0:
				rgb = rgba(v, t, p);
				break;
			case 1:
				rgb = rgba(q, v, p);
				break;
			case 2:
				rgb = rgba(p, v, t);
				break;
			case 3:
				rgb = rgba(p, q, v);
				break;
			case 4:
				rgb = rgba(t, p, v);
				break;
			default:
				rgb = rgba(v, p, q);
				break;
			}

			return rgb;
		}

		int color_index(const char c)
		{
			const auto index = c - 48;
			return index < 0 || index > MAX_COLOR_INDEX ? 7 : index;
		}

		void com_clean_name_stub(const char* in, char* out, const int out_size)
		{
			// check that the name is at least 3 char without colors
			char name[32]{};

			game::I_strncpyz(out, in, std::min<int>(out_size, sizeof(name)));

			utils::string::strip(out, name, std::min<int>(out_size, sizeof(name)));
			if (std::strlen(name) < 3)
			{
				game::I_strncpyz(out, "UnnamedPlayer", std::min<int>(out_size, sizeof(name)));
			}
		}

		char* i_clean_str_stub(char* string)
		{
			utils::string::strip(string, string, static_cast<int>(strlen(string)) + 1);

			return string;
		}

		size_t get_client_name_stub(const int local_client_num, const int index, char* buf, const int size,
			const size_t unk, const size_t unk2)
		{
			// CL_GetClientName (CL_GetClientNameAndClantag?)
			const auto result = utils::hook::invoke<size_t>(0x1409BDAF0, local_client_num, index, buf, size, unk, unk2);

			utils::string::strip(buf, buf, size);

			return result;
		}

		void rb_lookup_color_stub(const char index, DWORD* color)
		{
			*color = rgba(255, 255, 255);
			
			switch (index)
			{
			case '8':
				*color = *reinterpret_cast<DWORD*>(0x148B9D284);
				break;
			case '9':
				*color = *reinterpret_cast<DWORD*>(0x148B9D288);
				break;
			case ':':
				*color = hsv_to_rgb({static_cast<uint8_t>((game::Sys_Milliseconds() / 100) % 256), 255, 255});
				break;
			case ';':
				*color = *reinterpret_cast<DWORD*>(0x148B9D290);
				break;
			case '<':
				*color = 0xFFFCFF80;
				break;
			default:
				*color = color_table[color_index(index)];
				break;
			}
		}
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_dedi())
			{
				return;
			}
			
			// allows colored name in-game
			utils::hook::jump(0x140CFA700, com_clean_name_stub, true);

			// don't apply colors to overhead names
			utils::hook::call(0x1406843FE, get_client_name_stub);

			// patch I_CleanStr
			utils::hook::jump(0x140CFACC0, i_clean_str_stub, true);
			
			// make color index higher for more colors
			utils::hook::jump(0x140CFA6F0, color_index, true);
			utils::hook::set<uint8_t>(0x140E4F64B, MAX_COLOR_INDEX);

			// force new colors
			utils::hook::jump(0x140E570E0, rb_lookup_color_stub, true);

			// prevent name mismatch check
			utils::hook::set<uint8_t>(0x140805C10, 0xC3);

			console::info("[IWZ][Colors] installed base-game text palette with extended color codes\n");
		}
	};
}

REGISTER_COMPONENT(colors::component)
