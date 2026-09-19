#pragma once

#include <array>
#include <cstdint>
#include <cstring>
#include <istream>

namespace shader_cache
{
	struct progress_record
	{
		char name[64]{};
		std::uint64_t timestamp{};
	};
	static_assert(sizeof(progress_record) == 72);
	using progress_records = std::array<progress_record, 128>;

	// Stock format: 'upsd', followed by length/name (including NUL)/timestamp
	// records until EOF. Validate into a temporary buffer before exposing records.
	inline bool read_progress(std::istream& stream, progress_records& output)
	{
		std::uint32_t magic{};
		if (!stream.read(reinterpret_cast<char*>(&magic), sizeof(magic)) || magic != 0x64737075) return false;
		progress_records records{};
		std::size_t count{};
		while (stream.peek() != std::char_traits<char>::eof())
		{
			std::uint32_t length{};
			if (count == records.size() || !stream.read(reinterpret_cast<char*>(&length), sizeof(length)) ||
				length < 2 || length > sizeof(progress_record::name)) return false;
			auto& record = records[count++];
			if (!stream.read(record.name, length) || record.name[length - 1] != '\0' ||
				std::memchr(record.name, '\0', length - 1) ||
				!stream.read(reinterpret_cast<char*>(&record.timestamp), sizeof(record.timestamp))) return false;
		}
		if (stream.bad() || count == 0) return false;
		output = records;
		return true;
	}
}
