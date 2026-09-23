#pragma once

#include <array>
#include <bitset>
#include <cstddef>
#include <cstdint>

namespace shader_preload
{
	// The native warm-draw queue uses 64-bit combination keys and retains at most
	// 32768 of them. A half-full table avoids moving the sorted array on every miss.
	class combination_cache
	{
	public:
		static constexpr std::size_t limit = 32768;

		void clear()
		{
			occupied_.reset();
			size_ = 0;
		}

		bool contains_or_insert(std::uint64_t key)
		{
			auto hash = key;
			hash = (hash ^ (hash >> 30)) * 0xbf58476d1ce4e5b9ULL;
			hash = (hash ^ (hash >> 27)) * 0x94d049bb133111ebULL;
			hash ^= hash >> 31;
			auto slot = static_cast<std::size_t>(hash) & (capacity - 1);
			while (occupied_[slot])
			{
				if (keys_[slot] == key) return true;
				slot = (slot + 1) & (capacity - 1);
			}
			if (size_ < limit)
			{
				keys_[slot] = key;
				occupied_.set(slot);
				++size_;
			}
			return false;
		}

		std::size_t size() const { return size_; }

	private:
		static constexpr std::size_t capacity = limit * 2;
		std::array<std::uint64_t, capacity> keys_{};
		std::bitset<capacity> occupied_{};
		std::size_t size_{};
	};
}
