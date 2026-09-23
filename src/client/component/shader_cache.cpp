#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "game/game.hpp"
#include "console/console.hpp"
#include "game_module.hpp"
#include "shader_cache.hpp"
#include <utils/hook.hpp>
#include <algorithm>
#include <bit>
#include <condition_variable>
#include <deque>
#include <list>
#include <memory>
#include <unordered_map>
#include <unordered_set>

namespace shader_cache
{
	namespace
	{
		std::wstring client_path;
		std::wstring client_command_line;

		constexpr std::size_t max_shader_size = 4 * 1024 * 1024;
		constexpr std::size_t max_archive_size = 64 * 1024 * 1024;
		constexpr std::uint32_t max_archive_records = 8192;
		constexpr char archive_magic[8] = {'I', 'W', 'Z', 'D', 'X', 'B', 'C', '1'};

		enum class stage : std::uint32_t { vertex, geometry, pixel, hull, domain, compute };
		enum class work : std::uint8_t { queued, building, ready, failed };

		using create_shader = HRESULT(STDMETHODCALLTYPE*)(ID3D11Device*, const void*, SIZE_T,
			ID3D11ClassLinkage*, void**);
		std::array<utils::hook::detour, 6> shader_hooks;
		const std::array<unsigned, 6> shader_slots{12, 13, 15, 16, 17, 18};
		std::array<void*, 6> hook_targets{};
		std::mutex device_mutex;
		std::mutex setup_mutex;

		std::uint64_t shader_hash(stage kind, const void* data, std::size_t size)
		{
			std::uint64_t value = 14695981039346656037ull;
			const auto* bytes = static_cast<const std::uint8_t*>(data);
			for (auto i = 0u; i < sizeof(kind); ++i) { value ^= (static_cast<std::uint32_t>(kind) >> (i * 8)) & 255; value *= 1099511628211ull; }
			for (std::size_t i = 0; i < size; ++i) { value ^= bytes[i]; value *= 1099511628211ull; }
			return value;
		}

		struct shader_entry
		{
			stage kind;
			std::uint64_t hash;
			std::vector<std::uint8_t> bytes;
			IUnknown* object = nullptr;
			work status = work::queued;
			bool persisted = false;
			bool discarded = false;
			std::list<std::shared_ptr<shader_entry>>::iterator age;
		};

		struct archive_record
		{
			std::uint32_t kind;
			std::uint32_t length;
			std::uint64_t checksum;
		};
		static_assert(sizeof(archive_record) == 16);
		struct release_list : std::vector<IUnknown*>
		{
			~release_list() { for (auto* object : *this) object->Release(); }
		};
		struct release_object
		{
			void operator()(IUnknown* object) const { if (object) object->Release(); }
		};

		class device_cache
		{
			ID3D11Device* device_;
			std::filesystem::path path_;
			std::size_t byte_limit_;
			std::size_t object_limit_;
			std::size_t bytes_ = 0;
			std::size_t objects_ = 0;
			std::size_t write_bytes_ = 0;
			std::mutex mutex_;
			std::mutex stop_mutex_;
			std::condition_variable cv_;
			std::unordered_multimap<std::uint64_t, std::shared_ptr<shader_entry>> entries_;
			std::list<std::shared_ptr<shader_entry>> ages_;
			std::deque<std::shared_ptr<shader_entry>> preload_;
			std::deque<std::shared_ptr<shader_entry>> writes_;
			std::unordered_set<std::uint64_t> persisted_hashes_;
			std::vector<std::thread> workers_;
			std::atomic<unsigned> running_workers_{0};
			std::thread archive_thread_;
			std::chrono::steady_clock::time_point started_ = std::chrono::steady_clock::now();
			std::atomic<std::uint64_t> reuse_{0}, misses_{0}, loaded_{0}, created_{0}, replayed_{0}, failures_{0}, evictions_{0};
			unsigned foreground_ = 0;
			unsigned active_calls_ = 0;
			bool stopping_ = false;
			bool joined_ = false;
			bool archive_done_ = false;
			std::chrono::steady_clock::time_point replay_deadline_{};
			bool archive_valid_ = false;
			std::uintmax_t archive_length_ = 0;
			std::uint32_t archive_count_ = 0;

			std::shared_ptr<shader_entry> find_locked(stage kind, const void* data, std::size_t size, std::uint64_t hash)
			{
				const auto [begin, end] = entries_.equal_range(hash);
				for (auto it = begin; it != end; ++it)
				{
					auto& item = it->second;
					if (!item->discarded && item->kind == kind && item->bytes.size() == size &&
						std::memcmp(item->bytes.data(), data, size) == 0) return item;
				}
				return {};
			}

			void touch_locked(const std::shared_ptr<shader_entry>& item)
			{
				ages_.splice(ages_.begin(), ages_, item->age);
			}

			void trim_locked(release_list& releases, std::size_t extra,
				const shader_entry* protected_item = nullptr)
			{
				while ((bytes_ + extra > byte_limit_ || objects_ > object_limit_ || entries_.size() >= max_archive_records) && !ages_.empty())
				{
					auto it = std::prev(ages_.end());
					while (it != ages_.begin() && ((*it)->status == work::building || it->get() == protected_item)) --it;
					if ((*it)->status == work::building || it->get() == protected_item) break;
					auto item = *it;
					if (item->object) releases.push_back(item->object);
					item->discarded = true;
					if (item->status == work::queued)
						preload_.erase(std::remove(preload_.begin(), preload_.end(), item), preload_.end());
					bytes_ -= item->bytes.size();
					if (item->object) { item->object = nullptr; --objects_; }
					const auto [begin, end] = entries_.equal_range(item->hash);
					for (auto map = begin; map != end; ++map) if (map->second == item) { entries_.erase(map); break; }
					ages_.erase(it);
					++evictions_;
				}
			}

			std::shared_ptr<shader_entry> insert_locked(stage kind, const void* data, std::size_t size,
				std::uint64_t hash, bool persisted, release_list& releases)
			{
				trim_locked(releases, size);
				if (bytes_ + size > byte_limit_ || entries_.size() >= max_archive_records) return {};
				auto item = std::make_shared<shader_entry>();
				item->kind = kind;
				item->hash = hash;
				item->bytes.assign(static_cast<const std::uint8_t*>(data), static_cast<const std::uint8_t*>(data) + size);
				item->persisted = persisted;
				ages_.push_front(item);
				item->age = ages_.begin();
				try { entries_.emplace(hash, item); }
				catch (...) { ages_.pop_front(); throw; }
				bytes_ += size;
				return item;
			}

			void fail_build(const std::shared_ptr<shader_entry>& item)
			{
				IUnknown* orphan = nullptr;
				{
					std::lock_guard lock(mutex_);
					item->status = work::failed;
					if (item->object) { orphan = std::exchange(item->object, nullptr); --objects_; }
					++failures_;
					cv_.notify_all();
				}
				if (orphan) orphan->Release();
			}

			HRESULT build(const std::shared_ptr<shader_entry>& item, void** output, bool replay)
			{
				void* created = nullptr;
				const auto original = reinterpret_cast<create_shader>(shader_hooks[static_cast<unsigned>(item->kind)].get<void>());
				const auto result = original(device_, item->bytes.data(), item->bytes.size(), nullptr, &created);
				std::unique_ptr<IUnknown, release_object> created_guard(static_cast<IUnknown*>(created));
				release_list releases;
				{
					std::lock_guard lock(mutex_);
					if (SUCCEEDED(result) && created && !item->discarded && !stopping_)
					{
						item->object = static_cast<IUnknown*>(created);
						item->object->AddRef();
						++objects_;
						trim_locked(releases, 0, item.get());
						if (objects_ <= object_limit_)
						{
							item->status = work::ready;
							++created_;
							if (replay) ++replayed_;
						}
						else
						{
							releases.push_back(item->object); item->object = nullptr; --objects_;
							item->status = work::failed;
						}
					}
					else { item->status = work::failed; if (FAILED(result)) ++failures_; }
					if (SUCCEEDED(result) && created && !item->persisted && !stopping_ &&
						write_bytes_ + item->bytes.size() <= 8 * 1024 * 1024 && writes_.size() < 512)
					{
						try { writes_.push_back(item); write_bytes_ += item->bytes.size(); }
						catch (const std::bad_alloc&) { ++failures_; }
					}
					cv_.notify_all();
				}
				if (output) *output = created_guard.release();
				return result;
			}

			void worker()
			{
				for (;;)
				{
					std::shared_ptr<shader_entry> item;
					{
						std::unique_lock lock(mutex_);
						cv_.wait_for(lock, std::chrono::milliseconds(50), [this] { return stopping_ || (archive_done_ && !foreground_ && !preload_.empty()); });
						if (stopping_) break;
						if (archive_done_ && preload_.empty()) break;
						if (archive_done_ && std::chrono::steady_clock::now() >= replay_deadline_)
						{
							preload_.clear();
							break;
						}
						if (!archive_done_) continue;
						if (foreground_ || preload_.empty()) continue;
						item = std::move(preload_.front());
						preload_.pop_front();
						if (item->discarded || item->status != work::queued) continue;
						item->status = work::building;
					}
					void* object = nullptr;
					try { build(item, &object, true); }
					catch (const std::exception& e)
					{
						fail_build(item);
						console::error("[IWZ][ShaderCache] replay shader failed: %s\n", e.what());
					}
					if (object) static_cast<IUnknown*>(object)->Release();
				}
			}

			void finish_worker()
			{
				if (running_workers_.fetch_sub(1) == 1)
				{
					std::size_t queued;
					bool cancelled;
					{
						std::lock_guard lock(mutex_);
						queued = preload_.size(); cancelled = stopping_;
					}
					console::info("[IWZ][ShaderCache] replay finished loaded=%llu replayed=%llu queued=%zu cancelled=%d elapsedMs=%llu\n",
						static_cast<unsigned long long>(loaded_.load()), static_cast<unsigned long long>(replayed_.load()),
						queued, cancelled,
						static_cast<unsigned long long>(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - started_).count()));
				}
			}

			void load_archive()
			{
				std::ifstream file(path_, std::ios::binary);
				if (!file) { archive_valid_ = true; return; }
				std::error_code error;
				const auto size = std::filesystem::file_size(path_, error);
				if (error) return;
				auto reset_bad_archive = [&]
				{
					file.close();
					std::filesystem::remove(path_, error);
					archive_valid_ = !error;
					console::warn("[IWZ][ShaderCache] invalid archive header/size reset=%d path='%s'\n",
						!error, path_.string().c_str());
				};
				if (size > max_archive_size || size < sizeof(archive_magic)) { reset_bad_archive(); return; }
				char magic[sizeof(archive_magic)]{};
				if (!file.read(magic, sizeof(magic)) || std::memcmp(magic, archive_magic, sizeof(magic)))
				{ reset_bad_archive(); return; }
				std::uintmax_t valid_end = sizeof(magic);
				bool malformed = false, cancelled = false;
				std::uint32_t count = 0;
				while (valid_end < size && count < max_archive_records)
				{
					archive_record record{};
					if (!file.read(reinterpret_cast<char*>(&record), sizeof(record)) || record.kind > 5 ||
						record.length < 4 || record.length > max_shader_size ||
						valid_end + sizeof(record) + record.length > size) { malformed = true; break; }
					std::vector<std::uint8_t> bytes(record.length);
					if (!file.read(reinterpret_cast<char*>(bytes.data()), bytes.size()) ||
						shader_hash(static_cast<stage>(record.kind), bytes.data(), bytes.size()) != record.checksum) { malformed = true; break; }
					valid_end += sizeof(record) + bytes.size();
					++count;
					persisted_hashes_.insert(record.checksum);
					release_list releases;
					{
						std::lock_guard lock(mutex_);
						if (stopping_) { cancelled = true; break; }
						if (!find_locked(static_cast<stage>(record.kind), bytes.data(), bytes.size(), record.checksum))
						{
							auto item = insert_locked(static_cast<stage>(record.kind), bytes.data(), bytes.size(), record.checksum, true, releases);
							if (item) { preload_.push_back(item); ++loaded_; cv_.notify_one(); }
						}
					}
				}
				if (cancelled) return;
				archive_length_ = valid_end;
				archive_count_ = count;
				archive_valid_ = true;
				if (malformed)
				{
					file.close();
					std::filesystem::resize_file(path_, valid_end, error);
					console::warn("[IWZ][ShaderCache] archive invalid tail offset=%llu repaired=%d\n",
						static_cast<unsigned long long>(valid_end), !error);
					if (error) archive_valid_ = false;
				}
				console::info("[IWZ][ShaderCache] archive loaded=%llu bytes=%llu path='%s'\n",
					static_cast<unsigned long long>(loaded_.load()), static_cast<unsigned long long>(archive_length_), path_.string().c_str());
			}

			void archive_loop()
			{
				load_archive();
				{
					std::lock_guard lock(mutex_);
					if (stopping_) return;
					archive_done_ = true;
					replay_deadline_ = std::chrono::steady_clock::now() + std::chrono::seconds(10);
					cv_.notify_all();
				}
				std::error_code error;
				std::filesystem::create_directories(path_.parent_path(), error);
				if (error) archive_valid_ = false;
				std::ofstream file;
				if (archive_valid_)
				{
					file.open(path_, std::ios::binary | std::ios::app);
					if (file && archive_length_ == 0) { file.write(archive_magic, sizeof(archive_magic)); archive_length_ = sizeof(archive_magic); }
				}
				auto next_log = std::chrono::steady_clock::now() + std::chrono::seconds(5);
				std::uint64_t last_activity = 0;
				std::size_t pending_bytes = 0, pending_records = 0;
				bool write_error_logged = false;
				auto report_write_error = [&]
				{
					if (!write_error_logged)
					{
						write_error_logged = true;
						++failures_;
						console::error("[IWZ][ShaderCache] archive write failed path='%s'\n", path_.string().c_str());
					}
				};
				for (;;)
				{
					std::shared_ptr<shader_entry> item;
					{
						std::unique_lock lock(mutex_);
						cv_.wait_for(lock, std::chrono::seconds(5), [this] { return stopping_ || !writes_.empty(); });
						if (stopping_ && writes_.empty()) break;
						if (!writes_.empty()) { item = std::move(writes_.front()); writes_.pop_front(); write_bytes_ -= item->bytes.size(); }
					}
					if (item && file && !persisted_hashes_.contains(item->hash) &&
						archive_count_ < max_archive_records &&
						archive_length_ + sizeof(archive_record) + item->bytes.size() <= max_archive_size)
					{
						const archive_record record{static_cast<std::uint32_t>(item->kind), static_cast<std::uint32_t>(item->bytes.size()), item->hash};
						file.write(reinterpret_cast<const char*>(&record), sizeof(record));
						file.write(reinterpret_cast<const char*>(item->bytes.data()), item->bytes.size());
						if (file)
						{
							archive_length_ += sizeof(record) + item->bytes.size(); ++archive_count_;
							persisted_hashes_.insert(item->hash);
							pending_bytes += sizeof(record) + item->bytes.size(); ++pending_records;
						}
						else report_write_error();
					}
					if (file && pending_records && (!item || pending_records >= 64 || pending_bytes >= 256 * 1024))
					{
						file.flush();
						if (!file) report_write_error();
						pending_bytes = pending_records = 0;
					}
					const auto activity = loaded_.load() + created_.load() + reuse_.load() + misses_.load() + failures_.load();
					if (activity != last_activity && std::chrono::steady_clock::now() >= next_log)
					{
						last_activity = activity;
						next_log = std::chrono::steady_clock::now() + std::chrono::seconds(5);
						std::size_t object_count, byte_count;
						{
							std::lock_guard lock(mutex_);
							object_count = objects_; byte_count = bytes_;
						}
						console::info("[IWZ][ShaderCache] hits=%llu misses=%llu archive=%llu created=%llu failed=%llu evicted=%llu resident=%zu/%zu bytes=%zu/%zu elapsedMs=%llu\n",
							static_cast<unsigned long long>(reuse_.load()), static_cast<unsigned long long>(misses_.load()),
							static_cast<unsigned long long>(loaded_.load()), static_cast<unsigned long long>(created_.load()),
							static_cast<unsigned long long>(failures_.load()), static_cast<unsigned long long>(evictions_.load()),
							object_count, object_limit_, byte_count, byte_limit_,
							static_cast<unsigned long long>(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - started_).count()));
					}
				}
				if (file && pending_records) { file.flush(); if (!file) report_write_error(); }
			}

		public:
			ID3D11Device* device() const { return device_; }
			void enter_call()
			{
				std::lock_guard lock(mutex_);
				++active_calls_;
			}

			void leave_call()
			{
				std::lock_guard lock(mutex_);
				--active_calls_;
				cv_.notify_all();
			}

			void wait_for_calls()
			{
				std::unique_lock lock(mutex_);
				cv_.wait(lock, [this] { return active_calls_ == 0; });
			}

			device_cache(ID3D11Device* device, std::filesystem::path path, unsigned workers,
				std::size_t byte_limit, std::size_t object_limit)
				: device_(device), path_(std::move(path)), byte_limit_(byte_limit), object_limit_(object_limit)
			{
				device_->AddRef();
				running_workers_ = workers;
				try
				{
					for (unsigned i = 0; i < workers; ++i) workers_.emplace_back([this]
					{
						try { worker(); }
						catch (const std::exception& e) { console::error("[IWZ][ShaderCache] replay worker failed: %s\n", e.what()); }
						finish_worker();
					});
						archive_thread_ = std::thread([this]
						{
							try { archive_loop(); }
							catch (const std::exception& e)
							{
								{
									std::lock_guard lock(mutex_);
									archive_done_ = true; replay_deadline_ = std::chrono::steady_clock::now();
									preload_.clear(); cv_.notify_all();
								}
								console::error("[IWZ][ShaderCache] archive worker failed: %s\n", e.what());
							}
					});
					console::info("[IWZ][ShaderCache] device=%p workers=%u maxObjects=%zu maxBytes=%zu archive='%s'\n",
						device_, workers, object_limit_, byte_limit_, path_.string().c_str());
				}
				catch (...)
				{
					stop();
					device_->Release(); device_ = nullptr;
					throw;
				}
			}

			~device_cache()
			{
				stop();
				std::list<std::shared_ptr<shader_entry>> old;
				{
					std::lock_guard lock(mutex_);
					old.splice(old.end(), ages_);
					entries_.clear(); preload_.clear(); writes_.clear();
				}
				for (auto& item : old) if (item->object) item->object->Release();
				if (device_) device_->Release();
			}

			void stop()
			{
				std::lock_guard stop_lock(stop_mutex_);
				if (joined_) return;
				{
					std::lock_guard lock(mutex_);
					stopping_ = true;
					cv_.notify_all();
				}
				for (auto& worker : workers_) if (worker.joinable()) worker.join();
				if (archive_thread_.joinable()) archive_thread_.join();
				joined_ = true;
				console::info("[IWZ][ShaderCache] stopped device cache preloadElapsedMs=%llu hits=%llu misses=%llu failed=%llu\n",
					static_cast<unsigned long long>(std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - started_).count()),
					static_cast<unsigned long long>(reuse_.load()), static_cast<unsigned long long>(misses_.load()), static_cast<unsigned long long>(failures_.load()));
			}

			HRESULT create(stage kind, const void* data, SIZE_T size, void** output)
			{
				const auto original = reinterpret_cast<create_shader>(shader_hooks[static_cast<unsigned>(kind)].get<void>());
				if (!output || !data || size < 4 || size > max_shader_size)
					return original(device_, data, size, nullptr, output);
				std::shared_ptr<shader_entry> item;
				release_list releases;
				auto finish_foreground = [this](void*)
				{
					std::lock_guard lock(mutex_);
					--foreground_; cv_.notify_all();
				};
				std::unique_ptr<void, decltype(finish_foreground)> foreground_guard(nullptr, finish_foreground);
				const auto hash = shader_hash(kind, data, size);
				{
					std::unique_lock lock(mutex_);
					if (stopping_) { lock.unlock(); return original(device_, data, size, nullptr, output); }
					++foreground_;
					foreground_guard.reset(reinterpret_cast<void*>(1));
					item = find_locked(kind, data, size, hash);
					if (item)
					{
						touch_locked(item);
						if (item->status == work::ready)
						{
							item->object->AddRef(); *output = item->object; ++reuse_;
							return S_OK;
						}
						if (item->status == work::building)
						{
							cv_.wait(lock, [&] { return stopping_ || item->status != work::building; });
							if (!stopping_ && !item->discarded && item->status == work::ready && item->object)
							{
								item->object->AddRef(); *output = item->object; ++reuse_;
								return S_OK;
							}
							item.reset();
						}
					}
					if (!item) item = insert_locked(kind, data, size, hash, false, releases);
					if (item && item->status == work::queued)
					{
						item->status = work::building;
					}
					else item.reset();
					++misses_;
				}
				try { return item ? build(item, output, false) : original(device_, data, size, nullptr, output); }
				catch (...)
				{
					if (item) fail_build(item);
					throw;
				}
			}
		};

		std::shared_ptr<device_cache> current_cache;
		ID3D11Device* pending_device = nullptr;
		struct active_cache_call
		{
			std::shared_ptr<device_cache> cache;
			~active_cache_call()
			{
				// retire_cache retains the detached cache until this call is gone.
				auto* value = cache.get();
				cache.reset();
				value->leave_call();
			}
		};

		HRESULT create_cached(stage kind, ID3D11Device* device, const void* bytes, SIZE_T size,
			ID3D11ClassLinkage* linkage, void** output)
		{
			const auto original = reinterpret_cast<create_shader>(shader_hooks[static_cast<unsigned>(kind)].get<void>());
			if (linkage || !output) return original(device, bytes, size, linkage, output);
			std::shared_ptr<device_cache> cache;
			{
				std::lock_guard lock(device_mutex);
				if (current_cache && device == current_cache->device())
				{
					cache = current_cache;
					cache->enter_call();
				}
			}
			if (!cache) return original(device, bytes, size, linkage, output);
			active_cache_call call{std::move(cache)};
			try { return call.cache->create(kind, bytes, size, output); }
			catch (const std::exception& e)
			{
				console::error("[IWZ][ShaderCache] cache request failed: %s; using driver\n", e.what());
				return original(device, bytes, size, linkage, output);
			}
		}

#define SHADER_STUB(name, kind, type) \
		HRESULT STDMETHODCALLTYPE name(ID3D11Device* device, const void* data, SIZE_T size, \
			ID3D11ClassLinkage* linkage, type** output) \
		{ return create_cached(stage::kind, device, data, size, linkage, reinterpret_cast<void**>(output)); }
		SHADER_STUB(vertex_stub, vertex, ID3D11VertexShader)
		SHADER_STUB(geometry_stub, geometry, ID3D11GeometryShader)
		SHADER_STUB(pixel_stub, pixel, ID3D11PixelShader)
		SHADER_STUB(hull_stub, hull, ID3D11HullShader)
		SHADER_STUB(domain_stub, domain, ID3D11DomainShader)
		SHADER_STUB(compute_stub, compute, ID3D11ComputeShader)
#undef SHADER_STUB

		unsigned physical_cores()
		{
			DWORD length = 0;
			GetLogicalProcessorInformationEx(RelationProcessorCore, nullptr, &length);
			if (!length || length > 65536) return 2;
			std::vector<std::uint8_t> buffer(length);
			if (!GetLogicalProcessorInformationEx(RelationProcessorCore,
				reinterpret_cast<PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX>(buffer.data()), &length)) return 2;
			unsigned count = 0;
			constexpr auto header_size = offsetof(SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX, Processor);
			for (DWORD offset = 0; offset + header_size <= length;)
			{
				const auto* entry = reinterpret_cast<const SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX*>(buffer.data() + offset);
				if (entry->Size < header_size || offset + entry->Size > length) break;
				if (entry->Relationship == RelationProcessorCore) ++count;
				offset += entry->Size;
			}
			return count ? count : 2;
		}

		std::filesystem::path archive_path();

		void retire_cache()
		{
			std::shared_ptr<device_cache> old;
			ID3D11Device* pending;
			{
				std::lock_guard lock(device_mutex);
				old = std::move(current_cache);
				pending = std::exchange(pending_device, nullptr);
			}
			if (old) { old->stop(); old->wait_for_calls(); }
			if (pending) pending->Release();
		}

		utils::hook::detour renderer_shutdown_hook;
		void renderer_shutdown(int full, int restart)
		{
			// A full shutdown reaches the engine's D3D object releases. Retire our
			// references first; a partial renderer restart keeps the device alive.
			if (full)
			{
				console::info("[IWZ][ShaderCache] full renderer shutdown; retiring device cache before D3D teardown\n");
				retire_cache();
			}
			renderer_shutdown_hook.invoke<void>(full, restart);
		}

		void activate_cache(ID3D11Device* device)
		{
			D3D11_FEATURE_DATA_THREADING threading{};
			const auto threading_result = device->CheckFeatureSupport(D3D11_FEATURE_THREADING, &threading, sizeof(threading));
			const auto capable = SUCCEEDED(threading_result) && threading.DriverConcurrentCreates;
			DWORD_PTR process_mask = 0, system_mask = 0;
			const auto affinity_known = GetProcessAffinityMask(GetCurrentProcess(), &process_mask, &system_mask);
			const auto logical_available = affinity_known ? static_cast<unsigned>(std::popcount(process_mask)) : 2u;
			const auto cores = std::min(physical_cores(), std::max(1u, logical_available));
			MEMORYSTATUSEX memory{sizeof(memory)};
			const auto has_memory = GlobalMemoryStatusEx(&memory);
			const auto memory_workers = !has_memory || memory.ullTotalPhys >= 16ull * 1024 * 1024 * 1024 ? 12u :
				(memory.ullTotalPhys >= 8ull * 1024 * 1024 * 1024 ? 4u : 2u);
			const auto workers = capable ? std::min({12u, memory_workers, std::max(1u, cores > 2 ? cores - 2 : 1)}) : 0u;
			const auto byte_limit = has_memory ? static_cast<std::size_t>(std::clamp<ULONGLONG>(memory.ullTotalPhys / 256,
				8ull * 1024 * 1024, 64ull * 1024 * 1024)) : 32ull * 1024 * 1024;
			const auto object_limit = std::min<std::size_t>(2048, std::max<std::size_t>(256, cores * 256));
			auto cache = std::make_shared<device_cache>(device, archive_path(), workers, byte_limit, object_limit);
			{
				std::lock_guard lock(device_mutex);
				current_cache = std::move(cache);
			}
			console::info("[IWZ][ShaderCache] driverConcurrentCreates=%d featureHR=0x%08lX availableCores=%u logicalAffinity=%u\n",
				capable, static_cast<unsigned long>(threading_result), cores, logical_available);
		}

		void activate_pending()
		{
			std::lock_guard setup_lock(setup_mutex);
			ID3D11Device* pending;
			{
				std::lock_guard lock(device_mutex);
				pending = std::exchange(pending_device, nullptr);
			}
			if (!pending) return;
			try { activate_cache(pending); }
			catch (const std::exception& e)
			{
				console::error("[IWZ][ShaderCache] deferred cache setup failed: %s\n", e.what());
			}
			pending->Release();
		}

		HRESULT WINAPI create_device(IDXGIAdapter* adapter, D3D_DRIVER_TYPE driver_type, HMODULE software,
			UINT flags, const D3D_FEATURE_LEVEL* levels, UINT level_count, UINT sdk_version,
			ID3D11Device** output, D3D_FEATURE_LEVEL* feature_level, ID3D11DeviceContext** context)
		{
			const auto result = D3D11CreateDevice(adapter, driver_type, software, flags, levels,
				level_count, sdk_version, output, feature_level, context);
			if (FAILED(result) || !output || !*output) return result;
			std::lock_guard setup_lock(setup_mutex);
			auto* device = *output;
			retire_cache();
			if (device->GetCreationFlags() & D3D11_CREATE_DEVICE_SINGLETHREADED)
			{
				console::info("[IWZ][ShaderCache] single-threaded device=%p; cache bypassed\n", device);
				return result;
			}
			try
			{
			const std::array<void*, 6> stubs{reinterpret_cast<void*>(vertex_stub), reinterpret_cast<void*>(geometry_stub),
				reinterpret_cast<void*>(pixel_stub), reinterpret_cast<void*>(hull_stub),
				reinterpret_cast<void*>(domain_stub), reinterpret_cast<void*>(compute_stub)};
			auto** vtable = *reinterpret_cast<void***>(device);
			{
				std::lock_guard lock(device_mutex);
				for (unsigned i = 0; i < shader_hooks.size(); ++i)
				{
					if (hook_targets[i] && hook_targets[i] != vtable[shader_slots[i]])
					{
						console::warn("[IWZ][ShaderCache] new device uses different shader methods; cache disabled device=%p\n", device);
						return result;
					}
				}
				try
				{
					for (unsigned i = 0; i < shader_hooks.size(); ++i)
					{
						if (!hook_targets[i])
						{
							shader_hooks[i].create(vtable[shader_slots[i]], stubs[i]);
							shader_hooks[i].enable();
							hook_targets[i] = vtable[shader_slots[i]];
						}
					}
				}
				catch (const std::exception& e)
				{
					console::error("[IWZ][ShaderCache] shader hook unavailable: %s\n", e.what());
					return result;
				}
			}
			const auto* root = *reinterpret_cast<game::dvar_t**>(0x14756DEB0);
			if (root && root->current.string && *root->current.string) activate_cache(device);
			else
			{
				std::lock_guard lock(device_mutex);
				device->AddRef();
				pending_device = device;
				console::info("[IWZ][ShaderCache] profile path unavailable at device creation; cache deferred device=%p\n", device);
			}
			}
			catch (const std::exception& e)
			{
				console::error("[IWZ][ShaderCache] device setup failed: %s; using driver\n", e.what());
			}
		return result;
		}

		std::string progress_path()
		{
			const auto* root = *reinterpret_cast<game::dvar_t**>(0x14756DEB0);
			char path[256]{};
			utils::hook::invoke<void>(0x140CDBBF0, root->current.string, "players2", "upshd.dat", path);
			return path;
		}

		std::filesystem::path archive_path()
		{
			// The device can be created before fs_basepath is registered.
			const auto* root = *reinterpret_cast<game::dvar_t**>(0x14756DEB0);
			if (root && root->current.string && *root->current.string)
				return std::filesystem::path(progress_path()).parent_path() / "dxbc.archive";
			return std::filesystem::path(client_path).parent_path() / "iw7-mod" / "players2" / "dxbc.archive";
		}

		bool load_progress(progress_record* output)
		{
			activate_pending();
			const auto path = progress_path();
			std::ifstream stream(path, std::ios::binary);
			progress_records records{};
			const auto valid = stream && read_progress(stream, records);
			if (valid) std::copy(records.begin(), records.end(), output);
			console::info("[IWZ][ShaderCache] progress path='%s' valid=%d action=%s\n", path.c_str(), valid,
				valid ? "reuse-completed-work" : "rebuild-missing-or-invalid-progress");
			return valid;
		}

		HANDLE open_progress_write(const char*)
		{
			const auto path = progress_path();
			std::error_code error;
			std::filesystem::create_directories(std::filesystem::path(path).parent_path(), error);
			if (error)
			{
				console::error("[IWZ][ShaderCache] cannot create progress directory: %s\n", error.message().c_str());
				return nullptr;
			}
			const auto handle = utils::hook::invoke<HANDLE>(0x140B82320, path.c_str());
			console::info("[IWZ][ShaderCache] saving progress path='%s' opened=%d\n", path.c_str(), handle != nullptr);
			return handle;
		}

		bool restart_caching()
		{
			// Same availability checks as the stock RestartCaching / OptionsAreAvailable.
			if (!utils::hook::invoke<bool>(0x1400BEC10))
			{
				console::warn("[IWZ][ShaderCache] restart refused: caching options unavailable\n");
				return false;
			}

			retire_cache();
			const auto dxbc_path = archive_path();
			std::error_code archive_error;
			const auto archive_removed = std::filesystem::remove(dxbc_path, archive_error);
			if (archive_error)
			{
				console::error("[IWZ][ShaderCache] cannot reset DXBC archive '%s': %s; restart cancelled\n",
					dxbc_path.string().c_str(), archive_error.message().c_str());
				return false;
			}
			// Resolve the same profile path as FS_Delete, including a custom filesystem root.
			const auto path = progress_path();
			std::error_code error;
			const auto removed = std::filesystem::remove(path, error);
			if (error)
			{
				console::error("[IWZ][ShaderCache] cannot reset progress file '%s': %s; restart cancelled\n",
					path.c_str(), error.message().c_str());
				return false;
			}
			console::info("[IWZ][ShaderCache] reset progress='%s' removed=%d DXBC='%s' removed=%d; restarting client\n",
				path.c_str(), removed, dxbc_path.string().c_str(), archive_removed);
			game::Cbuf_AddText(0, "sys_restart\n");
			return true;
		}

		bool launch_client(const char* executable, const char* arguments)
		{
			if (!executable || _stricmp(executable, "iw7_ship.exe"))
			{
				return utils::hook::invoke<bool>(0x140DA8720, executable, arguments);
			}

			auto command_line = client_command_line;
			if (arguments && *arguments)
			{
				const auto length = MultiByteToWideChar(CP_ACP, 0, arguments, -1, nullptr, 0);
				if (!length) return false;
				std::wstring extra(length, L'\0');
				MultiByteToWideChar(CP_ACP, 0, arguments, -1, extra.data(), length);
				extra.pop_back();
				command_line += L" " + extra;
			}

			STARTUPINFOW startup{};
			startup.cb = sizeof(startup);
			PROCESS_INFORMATION process{};
			// CreateProcess requires a mutable command line. Keep the user's launch flags
			// and current game directory, and bypass the stock steam://run launch entirely.
			if (!CreateProcessW(client_path.c_str(), command_line.data(), nullptr, nullptr, FALSE,
				0, nullptr, nullptr, &startup, &process))
			{
				const auto error = GetLastError();
				console::error("[IWZ][ShaderCache] client relaunch failed WindowsError=%lu\n", error);
				SetLastError(error);
				return false;
			}
			console::info("[IWZ][ShaderCache] launched client pid=%lu; original launch flags preserved\n", process.dwProcessId);
			CloseHandle(process.hThread);
			CloseHandle(process.hProcess);
			return true;
		}
	}

	class component final : public component_interface
	{
	public:
		void* load_import(const std::string& library, const std::string& function) override
		{
			if (!game::environment::is_dedi() && _stricmp(library.c_str(), "d3d11.dll") == 0 &&
				function == "D3D11CreateDevice") return create_device;
			return nullptr;
		}

		void pre_destroy() override
		{
			retire_cache();
		}

		void post_start() override
		{
			// Capture before the game-module compatibility hooks change null-module queries.
			std::wstring path(32768, L'\0');
			const auto length = GetModuleFileNameW(game_module::get_host_module(), path.data(), static_cast<DWORD>(path.size()));
			if (!length || length >= path.size()) throw std::runtime_error("Unable to resolve client executable for restart");
			path.resize(length);
			client_path = std::move(path);
			client_command_line = GetCommandLineW();
		}

		void post_unpack() override
		{
			if (game::environment::is_dedi()) return;
			renderer_shutdown_hook.create(0x140E08360, renderer_shutdown);
			utils::hook::call(0x140D34E4F, launch_client);
			utils::hook::jump(0x1400BEB60, restart_caching);
			// The stock reader/writer bypass FS_BuildOSPath and use the retail
			// players2 directory, while FS_Delete is redirected to iw7-mod/players2.
			utils::hook::jump(0x1400BE9B0, load_progress);
			utils::hook::call(0x1400BF077, open_progress_write);
			console::info("[IWZ][ShaderCache] client restart routing, unified progress path and bounded cache reader installed\n");
		}
	};
}

REGISTER_COMPONENT(shader_cache::component)
