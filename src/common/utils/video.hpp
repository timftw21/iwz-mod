#pragma once

#include <filesystem>
#include <functional>
#include <memory>
#include <vector>
#include <cstdint>

namespace utils::video
{
	// The theater's native movie is 16:9. Fit all sources into this canvas so
	// the engine's cinematic material keeps its original geometry and UVs.
	constexpr int width = 1280;
	constexpr int height = 720;
	struct frame
	{
		std::vector<std::uint8_t> pixels; // Full-range BT.601 Y, U, V (4:2:0).
		double seconds{};
		double duration{};
	};

	class decoder
	{
	public:
		decoder(const std::filesystem::path& file, const std::filesystem::path& runtime,
			std::function<bool()> cancelled);
		~decoder();
		decoder(const decoder&) = delete;
		decoder& operator=(const decoder&) = delete;
		bool read(frame& output);
		void rewind();

	private:
		struct impl;
		std::unique_ptr<impl> impl_;
	};
}
