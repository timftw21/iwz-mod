#include <std_include.hpp>
#include "loader/loader.hpp"
#include "loader/component_loader.hpp"
#include "game/game.hpp"

#include "component/console/console.hpp"

#include <utils/flags.hpp>
#include <utils/string.hpp>
#include <utils/io.hpp>

DECLSPEC_NORETURN void WINAPI exit_hook(const int code)
{
	component_loader::pre_destroy();
	exit(code);
}

namespace
{
	struct affinity_mapping
	{
		std::vector<DWORD_PTR> logical_order;
		std::vector<DWORD_PTR> physical_first_order;
		size_t physical_core_count{};
		bool heterogeneous{};
	};

	struct processor_core
	{
		DWORD_PTR mask{};
		BYTE efficiency_class{};
	};

	DWORD_PTR take_lowest_processor(DWORD_PTR& mask)
	{
		const auto processor = mask & (~mask + 1);
		mask &= ~processor;
		return processor;
	}

	affinity_mapping build_affinity_mapping()
	{
		affinity_mapping result{};

		DWORD_PTR process_mask{};
		DWORD_PTR system_mask{};
		if (!GetProcessAffinityMask(GetCurrentProcess(), &process_mask, &system_mask) || !process_mask)
		{
			console::warn("[IWZ][CPU] physical-first affinity unavailable: GetProcessAffinityMask failed (%lu)\n",
				GetLastError());
			return result;
		}

		auto remaining_process_mask = process_mask;
		while (remaining_process_mask)
		{
			result.logical_order.emplace_back(take_lowest_processor(remaining_process_mask));
		}

		WORD process_group{};
		GROUP_AFFINITY current_affinity{};
		if (GetThreadGroupAffinity(GetCurrentThread(), &current_affinity))
		{
			process_group = current_affinity.Group;
		}

		DWORD buffer_size{};
		GetLogicalProcessorInformationEx(RelationProcessorCore, nullptr, &buffer_size);
		if (GetLastError() != ERROR_INSUFFICIENT_BUFFER || !buffer_size)
		{
			console::warn("[IWZ][CPU] physical-first affinity unavailable: topology size query failed (%lu)\n",
				GetLastError());
			return result;
		}

		std::vector<unsigned char> buffer(buffer_size);
		if (!GetLogicalProcessorInformationEx(RelationProcessorCore,
			reinterpret_cast<PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX>(buffer.data()), &buffer_size))
		{
			console::warn("[IWZ][CPU] physical-first affinity unavailable: topology query failed (%lu)\n",
				GetLastError());
			return result;
		}

		std::vector<processor_core> cores;
		for (size_t offset = 0; offset < buffer_size;)
		{
			const auto* info = reinterpret_cast<const SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX*>(
				buffer.data() + offset);
			if (!info->Size || offset + info->Size > buffer_size)
			{
				break;
			}

			if (info->Relationship == RelationProcessorCore)
			{
				for (WORD index = 0; index < info->Processor.GroupCount; ++index)
				{
					const auto& group_mask = info->Processor.GroupMask[index];
					if (group_mask.Group == process_group)
					{
						const auto core_mask = static_cast<DWORD_PTR>(group_mask.Mask) & process_mask;
						if (core_mask)
						{
							cores.emplace_back(processor_core{core_mask, info->Processor.EfficiencyClass});
						}
					}
				}
			}

			offset += info->Size;
		}

		std::ranges::sort(cores, [](const processor_core& left, const processor_core& right)
		{
			if (left.efficiency_class != right.efficiency_class)
			{
				return left.efficiency_class > right.efficiency_class;
			}

			return (left.mask & (~left.mask + 1)) < (right.mask & (~right.mask + 1));
		});

		result.physical_core_count = cores.size();
		if (!cores.empty())
		{
			const auto first_efficiency_class = cores.front().efficiency_class;
			result.heterogeneous = std::ranges::any_of(cores, [first_efficiency_class](const processor_core& core)
			{
				return core.efficiency_class != first_efficiency_class;
			});
		}

		while (!cores.empty())
		{
			auto found_processor = false;
			for (auto& core : cores)
			{
				if (core.mask)
				{
					result.physical_first_order.emplace_back(take_lowest_processor(core.mask));
					found_processor = true;
				}
			}

			if (!found_processor)
			{
				break;
			}
		}

		if (result.physical_first_order.size() != result.logical_order.size())
		{
			console::warn("[IWZ][CPU] physical-first affinity unavailable: topology covered %zu of %zu logical processors\n",
				result.physical_first_order.size(), result.logical_order.size());
			result.physical_first_order.clear();
			return result;
		}

		console::info("[IWZ][CPU] affinity policy=physical-first physicalCores=%zu logicalProcessors=%zu "
			"heterogeneous=%u remap=%s\n", result.physical_core_count, result.logical_order.size(),
			result.heterogeneous ? 1u : 0u,
			result.physical_first_order == result.logical_order ? "not-required" : "enabled");
		return result;
	}

	DWORD_PTR get_physical_first_affinity(const DWORD_PTR requested_mask)
	{
		static const auto stock_affinity = utils::flags::has_flag("stock_cpu_affinity");
		if (stock_affinity)
		{
			static const auto logged = []
			{
				console::info("[IWZ][CPU] affinity policy=stock reason=command-line-opt-out\n");
				return true;
			}();
			(void)logged;
			return requested_mask;
		}

		static const auto mapping = build_affinity_mapping();
		if (!requested_mask || mapping.physical_first_order.empty())
		{
			return requested_mask;
		}

		const auto requested = std::ranges::find(mapping.logical_order, requested_mask);
		if (requested == mapping.logical_order.end())
		{
			return requested_mask;
		}

		const auto index = static_cast<size_t>(std::distance(mapping.logical_order.begin(), requested));
		const auto remapped_mask = mapping.physical_first_order[index];
		if (remapped_mask != requested_mask)
		{
			static std::mutex log_mutex;
			static std::unordered_set<DWORD_PTR> logged_masks;
			std::lock_guard lock(log_mutex);
			if (logged_masks.emplace(requested_mask).second)
			{
				console::info("[IWZ][CPU] affinity logicalIndex=%zu requested=0x%llX applied=0x%llX\n", index,
					static_cast<unsigned long long>(requested_mask),
					static_cast<unsigned long long>(remapped_mask));
			}
		}

		return remapped_mask;
	}
}

DWORD_PTR WINAPI set_thread_affinity_mask(HANDLE hThread, DWORD_PTR dwThreadAffinityMask)
{
	component_loader::post_unpack();
	MH_ApplyQueued();

	return SetThreadAffinityMask(hThread, get_physical_first_affinity(dwThreadAffinityMask));
}

FARPROC load_binary(uint64_t* base_address)
{
	loader loader;
	utils::nt::library self;

	loader.set_import_resolver([self](const std::string& library, const std::string& function) -> void*
	{
		if (library == "steam_api64.dll"
			&& function != "SteamAPI_Shutdown")
		{
			return self.get_proc<FARPROC>(function);
		}
		else if (function == "ExitProcess")
		{
			return exit_hook;
		}
		else if (function == "SetThreadAffinityMask")
		{
			return set_thread_affinity_mask;
		}

		return component_loader::load_import(library, function);
	});

	std::string binary = "iw7_ship.exe";

	std::string data;
	if (!utils::io::read_file(binary, &data))
	{
		throw std::runtime_error(utils::string::va(
			"Failed to read game binary (%s)!\nPlease copy the iw7-mod.exe into your Call of Duty: Infinite Warfare installation folder and run it from there.",
			binary.data()));
	}

#ifdef INJECT_HOST_AS_LIB
	return loader.load_library(binary, base_address);
#else
	*base_address = 0x140000000;
	return loader.load(self, data); // not working
#endif
}

void remove_crash_file()
{
	utils::io::remove_file("__iw7_ship");
}

void enable_dpi_awareness()
{
	const utils::nt::library user32{ "user32.dll" };
	const auto set_dpi = user32
		? user32.get_proc<BOOL(WINAPI*)(DPI_AWARENESS_CONTEXT)>("SetProcessDpiAwarenessContext")
		: nullptr;
	if (set_dpi)
	{
		set_dpi(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
	}
}

void restore_parallel_dll_loading()
{
	const utils::nt::library self;
	const auto registry_path = R"(Software\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\)" + self.
		get_name();

	HKEY key = nullptr;
	auto status = RegOpenKeyExA(HKEY_LOCAL_MACHINE, registry_path.data(), 0, KEY_QUERY_VALUE, &key);
	if (status == ERROR_FILE_NOT_FOUND)
	{
		console::info("[IWZ][Startup] Windows parallel loader enabled; legacy throttle absent\n");
		return;
	}
	if (status != ERROR_SUCCESS)
	{
		console::warn("[IWZ][Startup] unable to inspect legacy MaxLoaderThreads throttle (%ld)\n", status);
		return;
	}

	DWORD value{};
	DWORD value_type{};
	DWORD value_size = sizeof(value);
	status = RegQueryValueExA(key, "MaxLoaderThreads", nullptr, &value_type,
		reinterpret_cast<BYTE*>(&value), &value_size);
	RegCloseKey(key);

	if (status == ERROR_FILE_NOT_FOUND)
	{
		console::info("[IWZ][Startup] Windows parallel loader enabled; legacy throttle absent\n");
		return;
	}
	if (status != ERROR_SUCCESS)
	{
		console::warn("[IWZ][Startup] unable to read legacy MaxLoaderThreads throttle (%ld)\n", status);
		return;
	}

	status = RegOpenKeyExA(HKEY_LOCAL_MACHINE, registry_path.data(), 0, KEY_SET_VALUE, &key);
	if (status != ERROR_SUCCESS)
	{
		console::warn("[IWZ][Startup] legacy MaxLoaderThreads throttle is still active; removal failed (%ld)\n",
			status);
		return;
	}

	status = RegDeleteValueA(key, "MaxLoaderThreads");
	RegCloseKey(key);
	if (status == ERROR_SUCCESS || status == ERROR_FILE_NOT_FOUND)
	{
		console::info("[IWZ][Startup] removed legacy MaxLoaderThreads=%lu throttle; Windows parallel loader enabled\n",
			value_type == REG_DWORD ? value : 0);
	}
	else
	{
		console::warn("[IWZ][Startup] legacy MaxLoaderThreads throttle removal failed (%ld)\n", status);
	}
}

int main()
{
	if (!game::environment::is_dedi())
		ShowWindow(GetConsoleWindow(), SW_HIDE);

	console::init();

	FARPROC entry_point;
	enable_dpi_awareness();

	restore_parallel_dll_loading();

	srand(uint32_t(time(nullptr)));
	remove_crash_file();

	{
		component_loader::sort();

		auto premature_shutdown = true;
		const auto _ = gsl::finally([&premature_shutdown]()
		{
			if (premature_shutdown)
			{
				component_loader::pre_destroy();
			}
		});

		try
		{
			if (utils::flags::has_flag("stdout"))
			{
				setvbuf(stdout, NULL, _IONBF, 0);
				setvbuf(stderr, NULL, _IONBF, 0);
			}

			if (!component_loader::post_start()) return EXIT_FAILURE;

			uint64_t base_address{};
			entry_point = load_binary(&base_address);
			if (!entry_point)
			{
				throw std::runtime_error("Unable to load binary into memory");
			}

			if (base_address != 0x140000000)
			{
				throw std::runtime_error(utils::string::va(
					"Base address was (%p) and not (%p)\nThis should not be possible!",
					base_address, 0x140000000));
			}
			game::base_address = base_address;

			if (!component_loader::post_load()) return EXIT_FAILURE;
			MH_ApplyQueued();

			premature_shutdown = false;
		}
		catch (std::exception& e)
		{
			MessageBoxA(nullptr, e.what(), "ERROR", MB_ICONERROR);
			return EXIT_FAILURE;
		}
	}

	return static_cast<int>(entry_point());
}

int WINAPI WinMain(_In_ HINSTANCE, _In_opt_ HINSTANCE, _In_ PSTR, _In_ int)
{
	return main();
}
