#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "custom_video.hpp"
#include "command.hpp"
#include "console/console.hpp"
#include "directx.hpp"
#include "scheduler.hpp"
#include <utils/hook.hpp>
#include <utils/nt.hpp>
#include <utils/video.hpp>
#include <condition_variable>

namespace custom_video
{
	namespace
	{
		constexpr auto selection_dvar = "iwz_custom_video_file";
		constexpr auto lobby_movie = "zombies_lobby_candy_comp";
		std::mutex mutex;
		std::condition_variable wake;
		std::thread worker;
		std::atomic_bool exiting{};
		std::atomic_uint64_t generation{};
		std::atomic_bool lobby_cinematic{};
		std::atomic_bool lobby_requested{};
		game::dvar_t* selection{};
		std::vector<file> files;
		std::string requested_file;
		bool request_failed{};
		std::string playback_status{"Original lobby movie"};
		std::shared_ptr<utils::video::frame> latest_frame;
		std::uint64_t frame_generation{};
		std::mutex gpu_mutex;
		std::array<game::GfxImage, 3> images{};
		ID3D11Device* image_device{};
		std::shared_ptr<utils::video::frame> uploaded_frame;
		std::uint64_t uploaded_generation{};
		utils::hook::detour bind_hook;
		utils::hook::detour release_hook;
		utils::hook::detour frontend_movie_hook;

		std::filesystem::path mod_folder()
		{
			return std::filesystem::path(utils::nt::library().get_folder()) / "iw7-mod";
		}
		std::string utf8(const std::filesystem::path& path)
		{
			const auto text = path.u8string();
			return {reinterpret_cast<const char*>(text.data()), text.size()};
		}
		std::filesystem::path video_path(const std::string& id)
		{
			return mod_folder() / "custom_videos" / std::filesystem::path(std::u8string(id.begin(), id.end()));
		}
		std::string selected_locked()
		{
			return selection && selection->current.string ? selection->current.string : "";
		}
		void request_locked(const std::string& id, const char* reason)
		{
			requested_file = id;
			request_failed = false;
			++generation;
			latest_frame.reset();
			playback_status = id.empty() ? "Original lobby movie" : "Loading " + id;
			wake.notify_all();
			console::info("[IWZ][CustomVideo] request file='%s' generation=%llu reason='%s'\n",
				id.c_str(), static_cast<unsigned long long>(generation.load()), reason);
		}
		void failed(std::uint64_t token, const std::string& message)
		{
			std::lock_guard lock(mutex);
			if (token != generation) return;
			latest_frame.reset();
			++generation; // Cancel decoding as well as rendering after a GPU failure.
			request_failed = true;
			playback_status = "Unable to play: " + message + ". Using original movie.";
			console::error("[IWZ][CustomVideo] file='%s' error='%s'; stock movie restored\n",
				requested_file.c_str(), message.c_str());
			wake.notify_all();
		}

		void decode_worker()
		{
			std::uint64_t handled{};
			while (!exiting)
			{
				std::string id;
				std::uint64_t token;
				{
					std::unique_lock lock(mutex);
					wake.wait(lock, [&] { return exiting || generation != handled; });
					if (exiting) return;
					token = handled = generation;
					id = requested_file;
					if (id.empty() || request_failed) continue;
				}
				const auto cancelled = [token] { return exiting || token != generation; };
				try
				{
					const auto name = std::filesystem::path(std::u8string(id.begin(), id.end()));
					if (name.has_parent_path() || name == "." || name == "..")
						throw std::runtime_error("Select a file from the custom_videos folder");
					utils::video::decoder decoder(video_path(id), mod_folder() / "video", cancelled);
					bool first = true;
					while (!cancelled())
					{
						auto start = std::chrono::steady_clock::now();
						double end_time{};
						bool have_frame{};
						while (!cancelled())
						{
							auto frame = std::make_shared<utils::video::frame>();
							if (!decoder.read(*frame)) break;
							if (!have_frame) start = std::chrono::steady_clock::now();
							have_frame = true;
							end_time = frame->seconds + frame->duration;
							const auto due = start + std::chrono::duration<double>(frame->seconds);
							std::unique_lock lock(mutex);
							if (wake.wait_until(lock, due, cancelled)) break;
							latest_frame = std::move(frame);
							frame_generation = token;
							if (first)
							{
								first = false;
								playback_status = "Playing " + id + " (silent, looping)";
								console::info("[IWZ][CustomVideo] decoding file='%s' canvas=%dx%d audio=off\n",
									id.c_str(), utils::video::width, utils::video::height);
							}
						}
						if (cancelled()) break;
						if (!have_frame) throw std::runtime_error("No video frames were decoded");
						{
							std::unique_lock lock(mutex);
							if (wake.wait_until(lock, start + std::chrono::duration<double>(end_time), cancelled)) break;
						}
						decoder.rewind();
					}
				}
				catch (const std::exception& error)
				{
					if (!cancelled()) failed(token, error.what());
				}
			}
		}

		// R_Cinematic_SetMaterialTextures (0x140DD46F0) supplies these three
		// code images and the UV constant to the real theater material. Keep the
		// native cinematic alive as an immediate fallback while our decoder opens.
		auto movie_images() { return reinterpret_cast<game::GfxImage**>(0x14AFED040); }
		void release_images_locked()
		{
			// Also called on an early client shutdown, before the game is unpacked.
			if (std::none_of(images.begin(), images.end(), [](const auto& image) { return image.texture.map != nullptr; })) return;
			auto** slots = movie_images();
			const int order[] = {0, 2, 1}; // Engine order: Y, Cr, Cb. FFmpeg: Y, U, V.
			for (int i = 0; i < 3; ++i)
			{
				if (slots[i] == &images[order[i]])
					slots[i] = reinterpret_cast<game::GfxImage*>(0x1483D49F0 + i * sizeof(game::GfxImage));
			}
			for (auto& image : images)
			{
				if (image.texture.shaderView) image.texture.shaderView->Release();
				if (image.texture.map) image.texture.map->Release();
				image = {};
			}
			image_device = nullptr;
			uploaded_frame.reset();
			uploaded_generation = 0;
		}
		void check_gpu(HRESULT result, const char* operation)
		{
			if (FAILED(result)) throw std::runtime_error(std::string(operation) + " (D3D error " +
				std::to_string(static_cast<unsigned long>(result)) + ")");
		}
		void upload(const std::shared_ptr<utils::video::frame>& frame)
		{
			if (image_device != dx::device) release_images_locked();
			const int offsets[] = {0, utils::video::width * utils::video::height, utils::video::width * utils::video::height * 5 / 4};
			for (int i = 0; i < 3; ++i)
			{
				auto& image = images[i];
				const auto w = utils::video::width >> (i ? 1 : 0);
				const auto h = utils::video::height >> (i ? 1 : 0);
				if (!image.texture.map)
				{
					D3D11_TEXTURE2D_DESC desc{};
					desc.Width = w; desc.Height = h; desc.MipLevels = 1; desc.ArraySize = 1;
					desc.Format = DXGI_FORMAT_R8_UNORM;
					desc.SampleDesc.Count = 1;
					desc.Usage = D3D11_USAGE_DYNAMIC;
					desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
					desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
					check_gpu(dx::device->CreateTexture2D(&desc, nullptr, &image.texture.map), "Creating movie texture");
					check_gpu(dx::device->CreateShaderResourceView(image.texture.map, nullptr, &image.texture.shaderView), "Creating movie view");
					image.texture.shaderViewAlternate = image.texture.shaderView;
					image.imageFormat = desc.Format;
					image.mapType = game::MAPTYPE_2D;
					image.category = game::IMG_CATEGORY_RAW;
					image.width = static_cast<unsigned short>(w);
					image.height = static_cast<unsigned short>(h);
					image.depth = image.numElements = image.levelCount = 1;
					image.name = "*iwz_lobby_video";
				}
				D3D11_MAPPED_SUBRESOURCE mapped{};
				check_gpu(dx::deviceContext->Map(image.texture.map, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped), "Uploading movie frame");
				for (int y = 0; y < h; ++y)
					std::memcpy(static_cast<unsigned char*>(mapped.pData) + y * mapped.RowPitch,
						frame->pixels.data() + offsets[i] + y * w, w);
				dx::deviceContext->Unmap(image.texture.map, 0);
			}
			image_device = dx::device;
			uploaded_frame = frame;
		}

		bool bind_custom_movie()
		{
			// This is the actual playing name, not a queued request. Never replace
			// startup movies, map intros, or a movie preview in another menu.
			const auto in_lobby = !exiting && lobby_requested && game::Com_FrontEnd_IsInFrontEnd() &&
				std::strcmp(reinterpret_cast<const char*>(0x1483D4330), lobby_movie) == 0;
			if (lobby_cinematic.exchange(in_lobby) != in_lobby)
				console::info("[IWZ][CustomVideo] cinematic boundary active=%d movie='%s'\n",
					in_lobby ? 1 : 0, reinterpret_cast<const char*>(0x1483D4330));
			if (!in_lobby || !dx::device || !dx::deviceContext) return false;
			std::shared_ptr<utils::video::frame> frame;
			std::uint64_t token;
			{
				std::lock_guard lock(mutex);
				frame = latest_frame;
				token = frame_generation;
			}
			if (!frame || token != generation) return false;
			try
			{
				// The engine shares its immediate context between rendering and
				// cinematic updates. Use the same mutex as its native frame upload.
				const auto context_mutex = *reinterpret_cast<HANDLE*>(0x148B1BC98);
				const auto acquired = WaitForSingleObject(context_mutex, INFINITE);
				if (acquired != WAIT_OBJECT_0 && acquired != WAIT_ABANDONED)
					throw std::runtime_error("Acquiring movie graphics context (Windows error " + std::to_string(GetLastError()) + ")");
				const auto unlock = gsl::finally([&] { ReleaseMutex(context_mutex); });
				std::lock_guard lock(gpu_mutex);
				if (token != generation) return false;
				if (frame != uploaded_frame || image_device != dx::device) upload(frame);
				auto** slots = movie_images();
				slots[0] = &images[0]; slots[1] = &images[2]; slots[2] = &images[1];
				slots[3] = *reinterpret_cast<game::GfxImage**>(0x148B2D5A0); // Opaque white alpha.
				auto* uv = reinterpret_cast<float*>(0x148B9D74C);
				uv[0] = uv[1] = 1.0f; uv[2] = uv[3] = 0.0f;
				if (uploaded_generation != token)
				{
					uploaded_generation = token;
					console::info("[IWZ][CustomVideo] theater textures bound generation=%llu device=%p; native binding suspended\n",
						static_cast<unsigned long long>(token), dx::device);
				}
				return true;
			}
			catch (const std::exception& error) { failed(token, error.what()); }
			return false;
		}
		void bind_movie(int frame_index)
		{
			// Choose one source per update. Publishing the stock images first lets
			// the renderer see them while we wait for the context or upload a frame.
			// The native decoder still runs; its binder (including native frame-use
			// tracking) is needed only when its images will actually be displayed.
			if (!bind_custom_movie()) bind_hook.invoke<void>(frame_index);
		}
		void release_movie_images()
		{
			release_hook.invoke<void>();
			std::lock_guard lock(gpu_mutex);
			release_images_locked();
		}
		void frontend_movie(const char* name, bool loop, int time)
		{
			// frontendscenecameracinematic("") is the GSC lobby-exit boundary.
			// Observe it even if the renderer stops requesting cinematic textures.
			const auto wanted = name && std::strcmp(name, lobby_movie) == 0;
			if (lobby_requested.exchange(wanted) != wanted)
				console::info("[IWZ][CustomVideo] frontend screen requested=%d movie='%s'\n", wanted ? 1 : 0, name ? name : "");
			frontend_movie_hook.invoke<void>(name, loop, time);
		}
		void watcher()
		{
			std::lock_guard lock(mutex);
			if (exiting) return;
			const bool active = lobby_requested && lobby_cinematic && game::Com_FrontEnd_IsInFrontEnd();
			const auto wanted = active ? selected_locked() : "";
			if (wanted != requested_file) request_locked(wanted, active ? "lobby selection" : "left lobby cinematic");
		}
	}

	int rescan()
	{
		std::lock_guard lock(mutex);
		files.clear();
		std::error_code error;
		const auto directory = mod_folder() / "custom_videos";
		std::filesystem::create_directories(directory, error);
		if (!error)
		{
			for (std::filesystem::directory_iterator it(directory, error), end; !error && it != end; it.increment(error))
			{
				std::error_code file_error;
				if (!it->is_regular_file(file_error) || file_error) continue;
				auto extension = utf8(it->path().extension());
				std::transform(extension.begin(), extension.end(), extension.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
				static const std::unordered_set<std::string> supported{
					".mp4", ".m4v", ".mkv", ".webm", ".mov", ".avi", ".wmv", ".mpg", ".mpeg", ".ts", ".m2ts"};
				if (supported.contains(extension)) files.push_back({utf8(it->path().filename()), utf8(it->path().stem()), extension.substr(1)});
			}
		}
		std::sort(files.begin(), files.end(), [](const file& a, const file& b) { return a.id < b.id; });
		if (error) console::error("[IWZ][CustomVideo] scan failed: %s\n", error.message().c_str());
		console::info("[IWZ][CustomVideo] scanned folder='%s' files=%zu\n", utf8(directory).c_str(), files.size());
		return static_cast<int>(files.size());
	}
	std::vector<file> list() { std::lock_guard lock(mutex); return files; }
	std::string folder() { return utf8(mod_folder() / "custom_videos"); }
	std::string selected() { std::lock_guard lock(mutex); return selected_locked(); }
	std::string status() { std::lock_guard lock(mutex); return playback_status; }
	bool play(const std::string& id)
	{
		std::lock_guard lock(mutex);
		if (!selection || exiting || !game::Com_FrontEnd_IsInFrontEnd()) return false;
		if (std::none_of(files.begin(), files.end(), [&](const file& f) { return f.id == id; })) return false;
		game::Dvar_SetCommand(selection_dvar, id.c_str());
		if (lobby_cinematic) request_locked(id, "player selected video");
		else
		{
			playback_status = "Selected " + id + "; plays in the pre-game lobby";
			console::info("[IWZ][CustomVideo] selection saved for lobby file='%s'\n", id.c_str());
		}
		return true;
	}
	void clear()
	{
		std::lock_guard lock(mutex);
		if (selection) game::Dvar_SetCommand(selection_dvar, "");
		request_locked("", "original movie selected");
	}
	bool open_folder()
	{
		const auto directory = mod_folder() / "custom_videos";
		std::error_code error;
		std::filesystem::create_directories(directory, error);
		if (error) return false;
		const auto result = reinterpret_cast<std::intptr_t>(ShellExecuteW(nullptr, L"open", directory.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
		console::info("[IWZ][CustomVideo] open folder result=%lld\n", static_cast<long long>(result));
		return result > 32;
	}

	class component final : public component_interface
	{
	public:
		void post_unpack() override
		{
			if (game::environment::is_dedi()) return;
			bind_hook.create(0x140DD46F0, bind_movie);
			release_hook.create(0x140DD6700, release_movie_images);
			frontend_movie_hook.create(0x1400A9990, frontend_movie);
			scheduler::once([]
			{
				selection = game::Dvar_RegisterString(selection_dvar, "", game::DVAR_FLAG_SAVED, "Custom silent Zombies lobby video filename");
				rescan();
				worker = std::thread(decode_worker);
				scheduler::loop(watcher, scheduler::main, 100ms);
				command::add("customvideo", [](const command::params& params)
				{
					const std::string action = params.get(1);
					if (action == "stop") clear();
					else if (action == "folder") open_folder();
					else if (action == "rescan") rescan();
					else if (action == "play" && params.size() > 2)
					{
						if (!play(params.join(2))) console::warn("[IWZ][CustomVideo] file not found or lobby unavailable\n");
					}
					else if (action == "list") for (const auto& item : list()) console::info("  %s\n", item.id.c_str());
					console::info("[IWZ][CustomVideo] %s; selected='%s'\n", status().c_str(), selected().c_str());
				});
				console::info("[IWZ][CustomVideo] initialized; silent playback, stock fallback, selection='%s'\n", selected().c_str());
			}, scheduler::main);
		}
		void pre_destroy() override
		{
			{
				std::lock_guard lock(mutex);
				exiting = true;
				++generation;
				wake.notify_all();
			}
			if (worker.joinable()) worker.join();
			if (game::environment::is_dedi()) return;
			std::lock_guard lock(gpu_mutex);
			release_images_locked();
		}
	};
}

REGISTER_COMPONENT(custom_video::component)
