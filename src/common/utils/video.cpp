#include "video.hpp"

#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <Windows.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <limits>
#include <stdexcept>
#include <string>

#pragma warning(push, 0)
extern "C"
{
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/display.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}
#pragma warning(pop)

namespace utils::video
{
	namespace
	{
		// No hard DLL imports: a missing decoder must never prevent game startup.
		struct api
		{
			std::vector<std::shared_ptr<void>> modules;
			template <typename T> T symbol(const char* name)
			{
				for (const auto& module : modules)
				{
					if (const auto address = GetProcAddress(static_cast<HMODULE>(module.get()), name))
						return reinterpret_cast<T>(address);
				}
				throw std::runtime_error(std::string("Incompatible video decoder: ") + name);
			}
#define VIDEO_FUNCTION(name) decltype(&::name) name = symbol<decltype(&::name)>(#name)
			// Loaded before the function pointer initializers below execute.
			int load(const std::filesystem::path& folder)
			{
				for (const auto* name : {L"avutil-60.dll", L"swresample-6.dll", L"avcodec-62.dll",
					L"avformat-62.dll", L"swscale-9.dll"})
				{
					const auto path = std::filesystem::absolute(folder / name);
					const auto module = LoadLibraryExW(path.c_str(), nullptr,
						LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
					if (!module) throw std::runtime_error("Video decoder unavailable; reinstall iw7-mod/video (Windows error " +
						std::to_string(GetLastError()) + ")");
					modules.emplace_back(module, [](void* handle) { FreeLibrary(static_cast<HMODULE>(handle)); });
				}
				return 0;
			}
			explicit api(const std::filesystem::path& folder) : loaded(load(folder)) {}
			int loaded;
			VIDEO_FUNCTION(avformat_alloc_context);
			VIDEO_FUNCTION(avformat_open_input);
			VIDEO_FUNCTION(avformat_find_stream_info);
			VIDEO_FUNCTION(avformat_close_input);
			VIDEO_FUNCTION(av_find_best_stream);
			VIDEO_FUNCTION(av_read_frame);
			VIDEO_FUNCTION(av_guess_sample_aspect_ratio);
			VIDEO_FUNCTION(avcodec_alloc_context3);
			VIDEO_FUNCTION(avcodec_parameters_to_context);
			VIDEO_FUNCTION(avcodec_open2);
			VIDEO_FUNCTION(avcodec_free_context);
			VIDEO_FUNCTION(avcodec_send_packet);
			VIDEO_FUNCTION(avcodec_receive_frame);
			VIDEO_FUNCTION(av_packet_alloc);
			VIDEO_FUNCTION(av_packet_free);
			VIDEO_FUNCTION(av_packet_unref);
			VIDEO_FUNCTION(av_packet_side_data_get);
			VIDEO_FUNCTION(av_frame_alloc);
			VIDEO_FUNCTION(av_frame_free);
			VIDEO_FUNCTION(av_frame_unref);
			VIDEO_FUNCTION(av_frame_get_buffer);
			VIDEO_FUNCTION(av_display_rotation_get);
			VIDEO_FUNCTION(av_dict_set);
			VIDEO_FUNCTION(av_dict_free);
			VIDEO_FUNCTION(av_strerror);
			VIDEO_FUNCTION(sws_getCachedContext);
			VIDEO_FUNCTION(sws_freeContext);
			VIDEO_FUNCTION(sws_getCoefficients);
			VIDEO_FUNCTION(sws_setColorspaceDetails);
			VIDEO_FUNCTION(sws_scale);
#undef VIDEO_FUNCTION
			void check(int result, const char* operation)
			{
				if (result >= 0) return;
				char error[AV_ERROR_MAX_STRING_SIZE]{};
				av_strerror(result, error, sizeof(error));
				throw std::runtime_error(std::string(operation) + ": " + error);
			}
		};

		double ratio(AVRational value)
		{
			return value.num > 0 && value.den > 0 ? static_cast<double>(value.num) / value.den : 0.0;
		}
	}

	struct decoder::impl
	{
		api ff;
		std::function<bool()> cancelled;
		std::filesystem::path source_file;
		AVFormatContext* format{};
		AVCodecContext* codec{};
		AVPacket* packet{};
		AVFrame* decoded{};
		AVFrame* scaled{};
		SwsContext* scaler{};
		int stream_index{};
		int rotation{};
		bool draining{};
		double origin{std::numeric_limits<double>::quiet_NaN()};
		double next_time{};
		double last_time{-1.0};
		double interval{1.0 / 30.0};

		impl(const std::filesystem::path& runtime, std::function<bool()> stop)
			: ff(runtime), cancelled(std::move(stop)) {}
		~impl() { close(); }
		void close()
		{
			ff.sws_freeContext(scaler);
			scaler = nullptr;
			ff.av_frame_free(&scaled);
			ff.av_frame_free(&decoded);
			ff.av_packet_free(&packet);
			ff.avcodec_free_context(&codec);
			ff.avformat_close_input(&format);
			rotation = 0;
			draining = false;
			origin = std::numeric_limits<double>::quiet_NaN();
			next_time = 0;
			last_time = -1.0;
			interval = 1.0 / 30.0;
		}

		void open(const std::filesystem::path& file)
		{
			source_file = file;
			format = ff.avformat_alloc_context();
			if (!format) throw std::bad_alloc();
			format->interrupt_callback = {[](void* opaque)
				{ return static_cast<impl*>(opaque)->cancelled() ? 1 : 0; }, this};
			format->probesize = 8 * 1024 * 1024;
			format->max_analyze_duration = 3 * AV_TIME_BASE;
			format->max_streams = 64;
			AVDictionary* options{};
			ff.av_dict_set(&options, "protocol_whitelist", "file", 0);
			const auto path = file.u8string();
			const auto opened = ff.avformat_open_input(&format, reinterpret_cast<const char*>(path.c_str()), nullptr, &options);
			ff.av_dict_free(&options);
			ff.check(opened, "Opening video");
			// Probing may instantiate a decoder too. Apply the same memory and
			// thread limits before it reads any frames, including oversized input.
			std::vector<AVDictionary*> probe_options(format->nb_streams, nullptr);
			for (unsigned i = 0; i < format->nb_streams; ++i)
			{
				ff.av_dict_set(&probe_options[i], "threads", "2", 0);
				ff.av_dict_set(&probe_options[i], "max_pixels", "8847360", 0);
				if (format->streams[i]->codecpar->codec_type != AVMEDIA_TYPE_VIDEO)
					format->streams[i]->discard = AVDISCARD_ALL;
			}
			const auto probed = ff.avformat_find_stream_info(format, probe_options.data());
			for (auto*& option : probe_options) ff.av_dict_free(&option);
			ff.check(probed, "Reading video information");
			const AVCodec* implementation{};
			stream_index = ff.av_find_best_stream(format, AVMEDIA_TYPE_VIDEO, -1, -1, &implementation, 0);
			ff.check(stream_index, "Finding a video track");
			auto* stream = format->streams[stream_index];
			if (stream->disposition & AV_DISPOSITION_ATTACHED_PIC)
				throw std::runtime_error("File contains a cover image, not a video track");
			for (unsigned i = 0; i < format->nb_streams; ++i)
				if (static_cast<int>(i) != stream_index) format->streams[i]->discard = AVDISCARD_ALL;
			codec = ff.avcodec_alloc_context3(implementation);
			if (!codec) throw std::bad_alloc();
			ff.check(ff.avcodec_parameters_to_context(codec, stream->codecpar), "Reading video codec");
			codec->max_pixels = 4096 * 2160;
			codec->thread_count = 2;
			ff.check(ff.avcodec_open2(codec, implementation, nullptr), "Opening video codec");
			packet = ff.av_packet_alloc();
			decoded = ff.av_frame_alloc();
			scaled = ff.av_frame_alloc();
			if (!packet || !decoded || !scaled) throw std::bad_alloc();
			const auto fps = ratio(stream->avg_frame_rate);
			if (fps > 0.0) interval = 1.0 / std::clamp(fps, 1.0, 240.0);
			const auto* matrix = ff.av_packet_side_data_get(stream->codecpar->coded_side_data,
				stream->codecpar->nb_coded_side_data, AV_PKT_DATA_DISPLAYMATRIX);
			if (matrix && matrix->size >= 9 * sizeof(std::int32_t))
			{
				const auto degrees = -ff.av_display_rotation_get(reinterpret_cast<const std::int32_t*>(matrix->data));
				if (std::isfinite(degrees)) rotation = (static_cast<int>(std::lround(degrees / 90.0)) % 4 + 4) % 4;
			}
		}

		void convert(frame& output)
		{
			if (decoded->width <= 0 || decoded->height <= 0 ||
				static_cast<std::int64_t>(decoded->width) * decoded->height > codec->max_pixels)
				throw std::runtime_error("Video exceeds the 4K input limit");
			const auto sar = ratio(ff.av_guess_sample_aspect_ratio(format, format->streams[stream_index], decoded));
			const auto aspect = static_cast<double>(decoded->width) / decoded->height * (sar > 0 ? sar : 1.0);
			const auto visible_aspect = rotation % 2 ? 1.0 / aspect : aspect;
			const int fitted_width = std::clamp(static_cast<int>(std::min(static_cast<double>(width), height * visible_aspect)) & ~1, 2, width);
			const int fitted_height = std::clamp(static_cast<int>(std::min(static_cast<double>(height), width / visible_aspect)) & ~1, 2, height);
			const int scaled_width = rotation % 2 ? fitted_height : fitted_width;
			const int scaled_height = rotation % 2 ? fitted_width : fitted_height;
			if (scaled->width != scaled_width || scaled->height != scaled_height)
			{
				ff.av_frame_unref(scaled);
				scaled->format = AV_PIX_FMT_YUV420P;
				scaled->width = scaled_width;
				scaled->height = scaled_height;
				ff.check(ff.av_frame_get_buffer(scaled, 32), "Allocating video frame");
			}
			scaler = ff.sws_getCachedContext(scaler, decoded->width, decoded->height,
				static_cast<AVPixelFormat>(decoded->format), scaled_width, scaled_height, AV_PIX_FMT_YUV420P,
				SWS_BILINEAR, nullptr, nullptr, nullptr);
			if (!scaler) throw std::runtime_error("Unsupported video pixel format");
			int space = SWS_CS_ITU601;
			if (decoded->colorspace == AVCOL_SPC_BT709) space = SWS_CS_ITU709;
			else if (decoded->colorspace == AVCOL_SPC_BT2020_NCL || decoded->colorspace == AVCOL_SPC_BT2020_CL)
				space = SWS_CS_BT2020;
			const bool full_range = decoded->color_range == AVCOL_RANGE_JPEG ||
				decoded->format == AV_PIX_FMT_YUVJ420P || decoded->format == AV_PIX_FMT_YUVJ422P || decoded->format == AV_PIX_FMT_YUVJ444P;
			ff.check(ff.sws_setColorspaceDetails(scaler, ff.sws_getCoefficients(space), full_range ? 1 : 0,
				ff.sws_getCoefficients(SWS_CS_ITU601), 1, 0, 1 << 16, 1 << 16), "Converting video colors");
			ff.check(ff.sws_scale(scaler, decoded->data, decoded->linesize, 0, decoded->height,
				scaled->data, scaled->linesize), "Scaling video");
			output.pixels.resize(width * height * 3 / 2);
			std::fill_n(output.pixels.data(), width * height, std::uint8_t{0});
			std::fill(output.pixels.begin() + width * height, output.pixels.end(), std::uint8_t{128});
			const int offsets[] = {0, width * height, width * height * 5 / 4};
			for (int plane = 0; plane < 3; ++plane)
			{
				const int shift = plane == 0 ? 0 : 1;
				const int w = scaled_width >> shift, h = scaled_height >> shift, pitch = width >> shift;
				const int left = ((width - fitted_width) / 2 & ~1) >> shift;
				const int top = ((height - fitted_height) / 2 & ~1) >> shift;
				auto* destination = output.pixels.data() + offsets[plane] + top * pitch + left;
				for (int y = 0; y < h; ++y)
				{
					const auto* source = scaled->data[plane] + y * scaled->linesize[plane];
					if (!rotation) { std::memcpy(destination + y * pitch, source, w); continue; }
					for (int x = 0; x < w; ++x)
					{
						if (rotation == 1) destination[x * pitch + h - 1 - y] = source[x];
						else if (rotation == 2) destination[(h - 1 - y) * pitch + w - 1 - x] = source[x];
						else destination[(w - 1 - x) * pitch + y] = source[x];
					}
				}
			}
			const auto time_base = ratio(format->streams[stream_index]->time_base);
			double time = next_time;
			if (decoded->best_effort_timestamp != AV_NOPTS_VALUE && time_base > 0)
			{
				const auto pts = decoded->best_effort_timestamp * time_base;
				if (!std::isfinite(origin)) origin = pts;
				time = std::max(last_time + 0.000001, pts - origin);
			}
			output.seconds = time;
			output.duration = decoded->duration > 0 && time_base > 0 ? decoded->duration * time_base : interval;
			last_time = time;
			next_time = time + output.duration;
		}

		bool read(frame& output)
		{
			while (!cancelled())
			{
				const auto received = ff.avcodec_receive_frame(codec, decoded);
				if (received == 0)
				{
					convert(output);
					ff.av_frame_unref(decoded);
					return true;
				}
				if (received == AVERROR_EOF) return false;
				if (received != AVERROR(EAGAIN)) ff.check(received, "Decoding video");
				if (draining) return false;
				int read_result;
				do
				{
					ff.av_packet_unref(packet);
					if (cancelled()) return false;
					read_result = ff.av_read_frame(format, packet);
				} while (read_result >= 0 && packet->stream_index != stream_index);
				if (read_result == AVERROR_EOF)
				{
					draining = true;
					ff.check(ff.avcodec_send_packet(codec, nullptr), "Finishing video");
				}
				else
				{
					ff.check(read_result, "Reading video frame");
					const auto sent = ff.avcodec_send_packet(codec, packet);
					ff.av_packet_unref(packet);
					ff.check(sent, "Decoding video packet");
				}
			}
			return false;
		}
	};

	decoder::decoder(const std::filesystem::path& file, const std::filesystem::path& runtime,
		std::function<bool()> cancelled) : impl_(std::make_unique<impl>(runtime, std::move(cancelled)))
	{
		impl_->open(file);
	}
	decoder::~decoder() = default;
	bool decoder::read(frame& output) { return impl_->read(output); }
	void decoder::rewind()
	{
		auto& state = *impl_;
		// MPEG program/transport streams can seek past their initial I-frame
		// even with a backward seek to start_time. Reopen the demuxer to replay
		// the complete first GOP for every container; keep the DLLs loaded.
		state.close();
		state.open(state.source_file);
	}
}
