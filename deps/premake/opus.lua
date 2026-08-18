opus_codec = {
	opus = path.join(dependencies.basePath, "opus"),
	ogg = path.join(dependencies.basePath, "ogg"),
	opusfile = path.join(dependencies.basePath, "opusfile"),
	miniaudio = path.join(dependencies.basePath, "miniaudio"),
}

function opus_codec.import()
	links {
		"miniaudio_libopus",
		"opusfile",
		"opus",
		"ogg",
	}
	opus_codec.includes()
end

function opus_codec.includes()
	includedirs {
		opus_codec.miniaudio,
		path.join(opus_codec.opus, "include"),
		path.join(opus_codec.ogg, "include"),
		path.join(opus_codec.opusfile, "include"),
	}
end

function opus_codec.project()
	project "ogg"
		language "C"
		kind "StaticLib"
		includedirs {
			path.join(opus_codec.ogg, "include"),
		}
		files {
			path.join(opus_codec.ogg, "include/**.h"),
			path.join(opus_codec.ogg, "src/bitwise.c"),
			path.join(opus_codec.ogg, "src/framing.c"),
		}
		defines {
			"_CRT_SECURE_NO_WARNINGS",
		}
		warnings "Off"

	project "opus"
		language "C"
		kind "StaticLib"
		includedirs {
			opus_codec.opus,
			path.join(opus_codec.opus, "include"),
			path.join(opus_codec.opus, "celt"),
			path.join(opus_codec.opus, "silk"),
			path.join(opus_codec.opus, "silk/float"),
		}
		files {
			path.join(opus_codec.opus, "include/**.h"),
			path.join(opus_codec.opus, "src/**.h"),
			path.join(opus_codec.opus, "src/*.c"),
			path.join(opus_codec.opus, "celt/*.h"),
			path.join(opus_codec.opus, "celt/*.c"),
			path.join(opus_codec.opus, "silk/*.h"),
			path.join(opus_codec.opus, "silk/*.c"),
			path.join(opus_codec.opus, "silk/float/*.h"),
			path.join(opus_codec.opus, "silk/float/*.c"),
		}
		removefiles {
			path.join(opus_codec.opus, "src/opus_compare.c"),
			path.join(opus_codec.opus, "src/opus_demo.c"),
			path.join(opus_codec.opus, "src/repacketizer_demo.c"),
			path.join(opus_codec.opus, "celt/opus_custom_demo.c"),
		}
		defines {
			"OPUS_BUILD",
			"ENABLE_HARDENING",
			"DISABLE_DEBUG_FLOAT",
			"USE_ALLOCA",
			"HAVE_LRINT",
			"HAVE_LRINTF",
			"HAVE_CONFIG_H",
			"_CRT_SECURE_NO_WARNINGS",
		}
		warnings "Off"

	project "opusfile"
		language "C"
		kind "StaticLib"
		includedirs {
			path.join(opus_codec.opus, "include"),
			path.join(opus_codec.ogg, "include"),
			path.join(opus_codec.opusfile, "include"),
			path.join(opus_codec.opusfile, "src"),
		}
		files {
			path.join(opus_codec.opusfile, "include/**.h"),
			path.join(opus_codec.opusfile, "src/internal.h"),
			path.join(opus_codec.opusfile, "src/info.c"),
			path.join(opus_codec.opusfile, "src/internal.c"),
			path.join(opus_codec.opusfile, "src/opusfile.c"),
			path.join(opus_codec.opusfile, "src/stream.c"),
		}
		links {
			"opus",
			"ogg",
		}
		defines {
			"_CRT_SECURE_NO_WARNINGS",
		}
		warnings "Off"

	project "miniaudio_libopus"
		language "C"
		kind "StaticLib"
		includedirs {
			opus_codec.miniaudio,
			path.join(opus_codec.opus, "include"),
			path.join(opus_codec.ogg, "include"),
			path.join(opus_codec.opusfile, "include"),
		}
		files {
			path.join(opus_codec.miniaudio, "extras/decoders/libopus/miniaudio_libopus.h"),
			path.join(opus_codec.miniaudio, "extras/decoders/libopus/miniaudio_libopus.c"),
		}
		links {
			"opusfile",
			"opus",
			"ogg",
		}
		defines {
			"_CRT_SECURE_NO_WARNINGS",
		}
		warnings "Off"
end

table.insert(dependencies, opus_codec)
