#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include "asset_streaming.hpp"

#include "console/console.hpp"
#include "dvars.hpp"

#include "game/game.hpp"

#include <utils/flags.hpp>
#include <utils/string.hpp>

#include <array>
#include <winioctl.h>

namespace asset_streaming
{
	void bootstrap_log(const char* format, ...)
	{
		static std::mutex log_mutex;
		std::lock_guard lock(log_mutex);

		char message[1024]{};
		va_list arguments;
		va_start(arguments, format);
		const auto message_size = _vsnprintf_s(message, sizeof(message), _TRUNCATE, format, arguments);
		va_end(arguments);
		if (message_size <= 0)
		{
			return;
		}

		wchar_t executable_path[MAX_PATH]{};
		const auto path_size = GetModuleFileNameW(nullptr, executable_path, ARRAYSIZE(executable_path));
		if (!path_size || path_size >= ARRAYSIZE(executable_path))
		{
			return;
		}

		auto log_folder = std::filesystem::path(executable_path).parent_path() / "iw7-mod" / "logs";
		CreateDirectoryW(log_folder.parent_path().c_str(), nullptr);
		CreateDirectoryW(log_folder.c_str(), nullptr);

		const auto log_path = log_folder / "asset_streaming_bootstrap.log";
		const auto handle = CreateFileW(log_path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
			nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
		if (handle == INVALID_HANDLE_VALUE)
		{
			return;
		}

		SYSTEMTIME time{};
		GetLocalTime(&time);
		char line[1280]{};
		const auto line_size = _snprintf_s(line, sizeof(line), _TRUNCATE,
			"%04hu-%02hu-%02hu %02hu:%02hu:%02hu.%03hu [IWZ][AssetStreaming][Bootstrap] %s\r\n",
			time.wYear, time.wMonth, time.wDay, time.wHour, time.wMinute, time.wSecond,
			time.wMilliseconds, message);
		if (line_size > 0)
		{
			DWORD written{};
			WriteFile(handle, line, static_cast<DWORD>(line_size), &written, nullptr);
		}

		CloseHandle(handle);
	}

	namespace
	{
		enum class storage_class
		{
			unknown,
			hard_disk,
			solid_state,
		};

		struct storage_info
		{
			storage_class type{storage_class::unknown};
			std::wstring volume{L"<unknown>"};
			DWORD error{};
		};

		struct streaming_setting
		{
			const char* name;
			int value;
			int stock_value;
			int min;
			int max;
			unsigned int flags;
		};

		constexpr std::array ssd_profile{
			streaming_setting{"cl_transient_mp_yield_timeout", 1500, 3000, 0, 0x7FFFFFFF,
				game::DVAR_FLAG_SAVED},
			streaming_setting{"cl_transient_mp_yield_priority_timeout", 100, 200, 0, 0x7FFFFFFF,
				game::DVAR_FLAG_SAVED},
			streaming_setting{"cl_preload_sp_yield_timeout", 1500, 3000, 0, 0x7FFFFFFF,
				game::DVAR_FLAG_TRUE_SAVED},
			streaming_setting{"cl_preload_sp_stream_minimum_time", 2000, 6000, 0, 0x7FFFFFFF,
				game::DVAR_FLAG_TRUE_SAVED},
			streaming_setting{"cl_preload_sp_yield_minimum_time", 250, 1000, 0, 0x7FFFFFFF,
				game::DVAR_FLAG_TRUE_SAVED},
		};

		const char* get_storage_name(const storage_class type)
		{
			switch (type)
			{
			case storage_class::hard_disk:
				return "hdd";
			case storage_class::solid_state:
				return "ssd";
			default:
				return "unknown";
			}
		}

		storage_info inspect_game_storage()
		{
			storage_info result{};
			std::array<wchar_t, MAX_PATH> executable_path{};
			if (!GetModuleFileNameW(nullptr, executable_path.data(), static_cast<DWORD>(executable_path.size())))
			{
				result.error = GetLastError();
				return result;
			}

			std::array<wchar_t, MAX_PATH> volume_path{};
			if (!GetVolumePathNameW(executable_path.data(), volume_path.data(),
				static_cast<DWORD>(volume_path.size())))
			{
				result.error = GetLastError();
				return result;
			}

			result.volume = volume_path.data();
			if (result.volume.size() < 2 || result.volume[1] != L':')
			{
				result.error = ERROR_NOT_SUPPORTED;
				return result;
			}

			const std::wstring device_path = LR"(\\.\)" + result.volume.substr(0, 2);
			const auto device = CreateFileW(device_path.data(), 0, FILE_SHARE_READ | FILE_SHARE_WRITE,
				nullptr, OPEN_EXISTING, 0, nullptr);
			if (device == INVALID_HANDLE_VALUE)
			{
				result.error = GetLastError();
				return result;
			}
			const auto close_device = gsl::finally([device]()
			{
				CloseHandle(device);
			});

			STORAGE_PROPERTY_QUERY query{};
			query.PropertyId = StorageDeviceSeekPenaltyProperty;
			query.QueryType = PropertyStandardQuery;

			DEVICE_SEEK_PENALTY_DESCRIPTOR descriptor{};
			DWORD bytes_returned{};
			if (!DeviceIoControl(device, IOCTL_STORAGE_QUERY_PROPERTY, &query, sizeof(query), &descriptor,
				sizeof(descriptor), &bytes_returned, nullptr))
			{
				result.error = GetLastError();
				return result;
			}

			result.type = descriptor.IncursSeekPenalty ? storage_class::hard_disk : storage_class::solid_state;
			return result;
		}

		void register_ssd_profile()
		{
			for (const auto& setting : ssd_profile)
			{
				dvars::override::register_int(setting.name, setting.value, setting.min, setting.max, setting.flags);
			}
		}

		void register_profile_logging()
		{
			for (const auto& setting : ssd_profile)
			{
				dvars::callback::on_register(setting.name, [setting]()
				{
					const auto* dvar = game::Dvar_FindVar(setting.name);
					if (dvar)
					{
						console::info("[IWZ][AssetStreaming] dvar=%s effective=%d reset=%d stock=%d\n",
							setting.name, dvar->current.integer, dvar->reset.integer, setting.stock_value);
						bootstrap_log("dvar=%s effective=%d reset=%d stock=%d", setting.name,
							dvar->current.integer, dvar->reset.integer, setting.stock_value);
					}
				});
			}
		}

		storage_info game_storage{};
		bool ssd_profile_active{};
	}

	class component final : public component_interface
	{
	public:
		void post_start() override
		{
			if (game::environment::is_dedi())
			{
				return;
			}

			game_storage = inspect_game_storage();
			const auto volume = utils::string::convert(game_storage.volume);
			bootstrap_log("launch storage=%s volume='%s' detectionError=%lu stockStreaming=%u stockAffinity=%u",
				get_storage_name(game_storage.type), volume.data(), game_storage.error,
				utils::flags::has_flag("stock_asset_streaming") ? 1u : 0u,
				utils::flags::has_flag("stock_cpu_affinity") ? 1u : 0u);
			if (utils::flags::has_flag("stock_asset_streaming"))
			{
				console::info("[IWZ][AssetStreaming] storage=%s volume=%s profile=stock reason=command-line-opt-out\n",
					get_storage_name(game_storage.type), volume.data());
				return;
			}

			if (game_storage.type != storage_class::solid_state)
			{
				console::info("[IWZ][AssetStreaming] storage=%s volume=%s profile=stock detectionError=%lu\n",
					get_storage_name(game_storage.type), volume.data(), game_storage.error);
				return;
			}

			register_ssd_profile();
			ssd_profile_active = true;
			bootstrap_log("profile=ssd-balanced settings=%zu", ssd_profile.size());
			console::info("[IWZ][AssetStreaming] storage=ssd volume=%s profile=ssd-balanced settings=%zu\n",
				volume.data(), ssd_profile.size());
		}

		void post_unpack() override
		{
			if (ssd_profile_active)
			{
				register_profile_logging();
			}
		}
	};
}

REGISTER_COMPONENT(asset_streaming::component)
