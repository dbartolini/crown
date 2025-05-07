/*
 * Copyright (c) 2012-2025 Daniele Bartolini et al.
 * SPDX-License-Identifier: MIT
 */

#include "config.h"

#if CROWN_SOUND_OPENAL
#include "core/containers/array.inl"
#include "core/filesystem/file.h"
#include "core/math/constants.h"
#include "core/math/matrix4x4.inl"
#include "core/strings/string_id.inl"
#include "core/math/vector3.inl"
#include "core/memory/temp_allocator.inl"
#include "device/log.h"
#include "resource/resource_manager.h"
#include "resource/sound_resource.h"
#include "resource/sound_ogg.h"
#include "world/audio.h"
#include "world/sound_world.h"
#include "core/time.h"
#include <AL/al.h>
#include <AL/alc.h>
#include <AL/alext.h>
#define STB_VORBIS_HEADER_ONLY
#define STB_VORBIS_NO_PULLDATA_API
#include <stb_vorbis.c>

LOG_SYSTEM(SOUND, "sound")

namespace crown
{
#if CROWN_DEBUG
static const char *al_error_to_string(ALenum error)
{
	switch (error) {
	case AL_INVALID_ENUM: return "AL_INVALID_ENUM";
	case AL_INVALID_VALUE: return "AL_INVALID_VALUE";
	case AL_INVALID_OPERATION: return "AL_INVALID_OPERATION";
	case AL_OUT_OF_MEMORY: return "AL_OUT_OF_MEMORY";
	default: return "UNKNOWN_AL_ERROR";
	}
}

	#define AL_CHECK(function)                              \
		function;                                           \
		do                                                  \
		{                                                   \
			ALenum error;                                   \
			CE_ASSERT((error = alGetError()) == AL_NO_ERROR \
				, "alGetError: %s"                          \
				, al_error_to_string(error)                 \
				);                                          \
		} while (0)
#else
	#define AL_CHECK(function) function
#endif // if CROWN_DEBUG

/// Global audio-related functions
namespace audio_globals
{
	static ALCdevice *s_al_device;
	static ALCcontext *s_al_context;

	void init()
	{
		s_al_device = alcOpenDevice(NULL);
		CE_ASSERT(s_al_device, "alcOpenDevice: error");

		s_al_context = alcCreateContext(s_al_device, NULL);
		CE_ASSERT(s_al_context, "alcCreateContext: error");

		AL_CHECK(alcMakeContextCurrent(s_al_context));

#if CROWN_DEBUG && !CROWN_DEVELOPMENT
		logi(SOUND, "OpenAL Vendor   : %s", alGetString(AL_VENDOR));
		logi(SOUND, "OpenAL Version  : %s", alGetString(AL_VERSION));
		logi(SOUND, "OpenAL Renderer : %s", alGetString(AL_RENDERER));
#endif

		AL_CHECK(alDistanceModel(AL_LINEAR_DISTANCE_CLAMPED));
		AL_CHECK(alDopplerFactor(1.0f));
	}

	void shutdown()
	{
		alcDestroyContext(s_al_context);
		alcCloseDevice(s_al_device);
	}

} // namespace audio_globals

struct SoundInstance
{
	SoundInstanceId _id;

	const SoundResource *_resource;
	StringId64 _name;
	bool _loop;
	f32 _volume;

	ALuint _buffer[4];
	ALuint _source;
	ALenum _format;

	enum { BLOCK_MS = 200 }; ///< Size of each buffer in milliseconds.
	u32 _block_samples; ///< Number of samples in each block per channel.
	u32 _block_size;    ///< Size of each block of samples in bytes.

	File *_stream;        ///< Streaming data source.
	void *_stream_mem;    ///< Total memory to allow streaming.
	u8 *_stream_data;     ///< Current block of encoded streaming data.
	f32 *_stream_decoded; ///< Current block of decoded audio samples.
	u32 _stream_pos;      ///< Size of encoded data.

	// Vorbis-specific.
	stb_vorbis_alloc *_vorbis_alloc;
	unsigned char *_vorbis_headers;
	stb_vorbis *_vorbis;

	void create(const SoundResource *sr, File *stream, bool loop, f32 volume, f32 range, const Vector3 &pos)
	{
		_resource = sr;
		_stream = stream;
		_loop = loop;

		_stream_mem = NULL;
		_vorbis = NULL;

		// Create source.
		AL_CHECK(alGenSources(1, &_source));
		CE_ASSERT(alIsSource(_source), "alGenSources: error");

		AL_CHECK(alSourcef(_source, AL_REFERENCE_DISTANCE, 0.01f));
		AL_CHECK(alSourcef(_source, AL_MAX_DISTANCE, range));
		AL_CHECK(alSourcef(_source, AL_PITCH, 1.0f));
		AL_CHECK(alSourcei(_source, AL_LOOPING, (loop ? AL_TRUE : AL_FALSE)));
		set_volume(volume);
		set_position(pos);

		// Generate buffers.
		AL_CHECK(alGenBuffers(countof(_buffer), &_buffer[0]));
		for (u32 i = 0; i < countof(_buffer); ++i)
			CE_ASSERT(alIsBuffer(_buffer[i]), "alGenBuffers: error");

		u32 bytes_per_sample = sr->bit_depth / 8;
		_block_samples = sr->sample_rate * BLOCK_MS / 1000;
		_block_size = bytes_per_sample * _block_samples * sr->channels;

		logi(SOUND, "channels %u bits %u size %u bufsize %u", sr->channels, sr->bit_depth, sr->pcm_size, _block_size);

		switch (sr->bit_depth) {
		case  8: _format = sr->channels > 1 ? AL_FORMAT_STEREO8  : AL_FORMAT_MONO8; break;
		case 16: _format = sr->channels > 1 ? AL_FORMAT_STEREO16 : AL_FORMAT_MONO16; break;
		case 32: _format = sr->channels > 1 ? AL_FORMAT_STEREO_FLOAT32 : AL_FORMAT_MONO_FLOAT32; break;
		default: CE_FATAL("Number of bits per sample not supported."); break;
		}

		buffer_decoded_samples();
	}

	// Fill buffers with a bunch of already decoded samples.
	void buffer_decoded_samples()
	{
		const u8 *pcm_data = sound_resource::pcm_data(_resource);
		for (u32 i = 0, p = 0; i < countof(_buffer) && p != _resource->pcm_size; ++i) {
			const u32 num = min(_block_size, _resource->pcm_size - p);
			AL_CHECK(alBufferData(_buffer[i]
				, _format
				, &pcm_data[p]
				, num
				, _resource->sample_rate
				));
			AL_CHECK(alSourceQueueBuffers(_source, 1, &_buffer[i]));
			p += num;
		}
	}

	void create(ResourceManager *rm, StringId64 name, bool loop, f32 volume, f32 range, const Vector3 &pos)
	{
		const SoundResource *sr = (SoundResource *)rm->get(RESOURCE_TYPE_SOUND, name);

		File *stream = NULL;
		if (sr->stream_format != StreamFormat::NONE)
			stream = rm->open_stream(RESOURCE_TYPE_SOUND, name);

		_name = name;
		return create(sr, stream, loop, volume, range, pos);
	}

	/// Decodes a block of samples of size BLOCK_MS or less, and feeds it to AL.
	/// Returns the number of samples that have been decoded.
	u32 decode_samples(ALuint al_buffer)
	{
		if (!_stream)
			return 0;

		if (_resource->stream_format == StreamFormat::OGG) {
			const OggStreamMetadata *ogg = (OggStreamMetadata *)sound_resource::stream_metadata(_resource);
			int used;

			// Open the stream.
			if (_stream_mem == NULL) {
				const u32 stream_mem_size = 0
					+ sizeof(stb_vorbis_alloc) + alignof(stb_vorbis_alloc)
					+ ogg->alloc_buffer_size
					+ ogg->headers_size
					+ ogg->max_frame_size
					+ _block_size*2 + alignof(f32)
					;
				_stream_mem = default_allocator().allocate(stream_mem_size);

				_vorbis_alloc = (stb_vorbis_alloc *)memory::align_top(_stream_mem, alignof(stb_vorbis_alloc));
				_vorbis_alloc->alloc_buffer = (char *)&_vorbis_alloc[1];
				_vorbis_alloc->alloc_buffer_length_in_bytes = ogg->alloc_buffer_size;

				_vorbis_headers = (unsigned char *)&_vorbis_alloc[1] + ogg->alloc_buffer_size;

				_stream_data = (unsigned char *)_vorbis_headers + ogg->headers_size;
				_stream_decoded = (f32 *)memory::align_top(_stream_data + ogg->max_frame_size, alignof(f32));
				_stream_pos = 0;

				_stream->read(_vorbis_headers, ogg->headers_size);
			}

			if (_vorbis == NULL) {
				int error;
				_vorbis = stb_vorbis_open_pushdata(_vorbis_headers, ogg->headers_size, &used, &error, _vorbis_alloc);
				CE_ENSURE(error == VORBIS__no_error);
				CE_ENSURE(_vorbis != NULL);
				CE_ENSURE(used == ogg->headers_size);
			}

			// Decode samples.
			int n;
			int tot_n = 0;
			f32 *ss = _stream_decoded;

			// Try to decode at least _block_size samples.
			s64 t0 = time::now();
			while (tot_n < _block_samples) {
				float **output;
				int q = ogg->max_frame_size;

			retry:
				if (q > _stream->size() - _stream_pos)
					q = _stream->size() - _stream_pos;
				if (_stream_pos < q) {
					u32 k = _stream->position();
					u32 x = _stream->read(&_stream_data[_stream_pos], q - _stream_pos);
					logi(SOUND, "stream_pos %u pos %u x %u size %u data %02x%02x%02x%02x", k, _stream_pos, x, _stream->size(), _stream_data[0], _stream_data[1], _stream_data[2], _stream_data[3]);
					_stream_pos += x;
				}

				used = stb_vorbis_decode_frame_pushdata(_vorbis
					, _stream_data
					, _stream_pos
					, NULL
					, &output
					, &n
					);

				if (used == 0) {
					if (_stream->end_of_file()) {
						if (true || _loop) {
							_stream_pos = 0;
							_stream->seek(ogg->headers_size);
							stb_vorbis_close(_vorbis);
							_vorbis = NULL;
							logi(SOUND, "STREAM LOOP");
							break;
						}
						logi(SOUND, "STREAM ENDED");
						break; // No more data.
					}

					logi(SOUND, "NEED MORE DATA");
					goto retry;
				}

				_stream_pos = q - used;
				memmove(_stream_data, &_stream_data[used], _stream_pos);
				if (n == 0) {
					logi(SOUND, "SEEKING (q %u usee %u)", q, used);
					continue; // Seek/error recovery.
				}

				// logi(SOUND, "decoded %d", n);
				for (u32 i = 0; i < n; ++i) {
					*ss++ = output[0][i];
					*ss++ = output[1][i];
				}
				tot_n += n;
			}
			s64 t1 = time::now();

			// logi(SOUND, "block decoded %u", tot_n);
			logi(SOUND, "decoded %u p %u in %.4f", n, _stream_pos, time::seconds(t1 - t0));
			return tot_n;
		} else {
			if (_stream_mem == NULL) {
				_stream_mem = default_allocator().allocate(_block_size);
				_stream_decoded = (f32 *)_stream_mem;
			}

			if (_stream->end_of_file())
				return 0; // End-of-stream.

			// Read samples.
			u32 size = _block_size;
			if (size > _stream->size() - _block_size)
				size = _stream->size() - _block_size;

			_stream->read(_stream_decoded, size);
			return size / _block_size;
		}
	}

	void update()
	{
		ALint processed;
		AL_CHECK(alGetSourcei(_source, AL_BUFFERS_PROCESSED, &processed));

		if (processed != 0)
			logi(SOUND, "processed %d", processed);
		while (processed > 0) {
			ALuint buffer;
			AL_CHECK(alSourceUnqueueBuffers(_source, 1, &buffer));
			processed--;

			// Decode a block of samples and enqueue it.
			u32 n = decode_samples(buffer);
			if (n > 0) {
				const u32 size = n * _resource->channels * _resource->bit_depth / 8;
				AL_CHECK(alBufferData(buffer, _format, _stream_decoded, size, _resource->sample_rate));
				AL_CHECK(alSourceQueueBuffers(_source, 1, &buffer));
			}
		}

		ALint state;
		AL_CHECK(alGetSourcei(_source, AL_SOURCE_STATE, &state));

		if (state != AL_PLAYING && state != AL_PAUSED) {
			// At this point either the source underrun or no buffers were enqueued.
			ALint queued;
			AL_CHECK(alGetSourcei(_source, AL_BUFFERS_QUEUED, &queued));
			if (queued == 0)
				return; // Finished.

			// Underrun, restart playback.
			logi(SOUND, "UNDERRUN!!!");
			AL_CHECK(alSourcePlay(_source));
		}
	}

	void destroy(ResourceManager *rm)
	{
		stop();
		AL_CHECK(alSourcei(_source, AL_BUFFER, 0));
		AL_CHECK(alDeleteBuffers(countof(_buffer), &_buffer[0]));
		AL_CHECK(alDeleteSources(1, &_source));

		// Deallocate streaming memory.
		stb_vorbis_close(_vorbis);
		default_allocator().deallocate(_stream_mem);

		if (_stream != NULL)
			rm->close_stream(_stream);
	}

	void reload(ResourceManager *rm, const SoundResource *new_sr)
	{
		destroy(rm);
		create(rm, _name, _loop, _volume, range(), position());
	}

	void play()
	{
		AL_CHECK(alSourcePlay(_source));
	}

	void pause()
	{
		AL_CHECK(alSourcePause(_source));
	}

	void resume()
	{
		AL_CHECK(alSourcePlay(_source));
	}

	void stop()
	{
		AL_CHECK(alSourceStop(_source));
		AL_CHECK(alSourceRewind(_source)); // Workaround
		ALint processed;
		AL_CHECK(alGetSourcei(_source, AL_BUFFERS_PROCESSED, &processed));

		if (processed > 0) {
			ALuint removed;
			AL_CHECK(alSourceUnqueueBuffers(_source, 1, &removed));
		}
	}

	bool is_playing()
	{
		ALint state;
		AL_CHECK(alGetSourcei(_source, AL_SOURCE_STATE, &state));
		return state == AL_PLAYING;
	}

	bool finished()
	{
		ALint state;
		AL_CHECK(alGetSourcei(_source, AL_SOURCE_STATE, &state));
		return state != AL_PLAYING && state != AL_PAUSED;
	}

	Vector3 position()
	{
		ALfloat pos[3];
		AL_CHECK(alGetSourcefv(_source, AL_POSITION, pos));
		return vector3(pos[0], pos[1], pos[2]);
	}

	float range()
	{
		ALfloat range;
		AL_CHECK(alGetSourcefv(_source, AL_MAX_DISTANCE, &range));
		return range;
	}

	void set_position(const Vector3 &pos)
	{
		AL_CHECK(alSourcefv(_source, AL_POSITION, to_float_ptr(pos)));
	}

	void set_range(f32 range)
	{
		AL_CHECK(alSourcef(_source, AL_MAX_DISTANCE, range));
	}

	void set_volume(f32 volume)
	{
		_volume = volume;
		AL_CHECK(alSourcef(_source, AL_GAIN, volume));
	}
};

#define MAX_OBJECTS       1024
#define INDEX_MASK        0xffff
#define NEW_OBJECT_ID_ADD 0x10000

struct SoundWorldImpl
{
	struct Index
	{
		SoundInstanceId id;
		u16 index;
		u16 next;
	};

	ResourceManager *_resource_manager;
	u32 _num_objects;
	SoundInstance _playing_sounds[MAX_OBJECTS];
	Index _indices[MAX_OBJECTS];
	u16 _freelist_enqueue;
	u16 _freelist_dequeue;
	Matrix4x4 _listener_pose;

	bool has(SoundInstanceId id)
	{
		const Index &in = _indices[id & INDEX_MASK];
		return in.id == id && in.index != UINT16_MAX;
	}

	SoundInstance &lookup(SoundInstanceId id)
	{
		return _playing_sounds[_indices[id & INDEX_MASK].index];
	}

	SoundInstanceId add()
	{
		Index &in = _indices[_freelist_dequeue];
		_freelist_dequeue = in.next;
		in.id += NEW_OBJECT_ID_ADD;
		in.index = _num_objects++;
		SoundInstance &o = _playing_sounds[in.index];
		o._id = in.id;
		return o._id;
	}

	void remove(SoundInstanceId id)
	{
		Index &in = _indices[id & INDEX_MASK];

		SoundInstance &o = _playing_sounds[in.index];
		o = _playing_sounds[--_num_objects];
		_indices[o._id & INDEX_MASK].index = in.index;

		in.index = UINT16_MAX;
		_indices[_freelist_enqueue].next = id & INDEX_MASK;
		_freelist_enqueue = id & INDEX_MASK;
	}

	SoundWorldImpl(ResourceManager &rm)
		: _resource_manager(&rm)
	{
		_num_objects = 0;
		for (u32 i = 0; i < MAX_OBJECTS; ++i) {
			_indices[i].id = i;
			_indices[i].next = i + 1;
		}
		_freelist_dequeue = 0;
		_freelist_enqueue = MAX_OBJECTS - 1;

		set_listener_pose(MATRIX4X4_IDENTITY);
	}

	~SoundWorldImpl()
	{
		for (u32 i = 0; i < _num_objects; ++i)
			stop(_playing_sounds[i]._id);
	}

	SoundWorldImpl(const SoundWorldImpl &) = delete;

	SoundWorldImpl &operator=(const SoundWorldImpl &) = delete;

	SoundInstanceId play(StringId64 name, bool loop, f32 volume, f32 range, const Vector3 &pos)
	{
		SoundInstanceId id = add();
		SoundInstance &si = lookup(id);
		si.create(_resource_manager, name, loop, volume, range, pos);
		si.play();
		return id;
	}

	void stop(SoundInstanceId id)
	{
		SoundInstance &si = lookup(id);
		si.destroy(_resource_manager);
		remove(id);
	}

	bool is_playing(SoundInstanceId id)
	{
		return has(id) && lookup(id).is_playing();
	}

	void stop_all()
	{
		for (u32 i = 0; i < _num_objects; ++i) {
			_playing_sounds[i].stop();
		}
	}

	void pause_all()
	{
		for (u32 i = 0; i < _num_objects; ++i) {
			_playing_sounds[i].pause();
		}
	}

	void resume_all()
	{
		for (u32 i = 0; i < _num_objects; ++i) {
			_playing_sounds[i].resume();
		}
	}

	void set_sound_positions(u32 num, const SoundInstanceId *ids, const Vector3 *positions)
	{
		for (u32 i = 0; i < num; ++i) {
			lookup(ids[i]).set_position(positions[i]);
		}
	}

	void set_sound_ranges(u32 num, const SoundInstanceId *ids, const f32 *ranges)
	{
		for (u32 i = 0; i < num; ++i) {
			lookup(ids[i]).set_range(ranges[i]);
		}
	}

	void set_sound_volumes(u32 num, const SoundInstanceId *ids, const f32 *volumes)
	{
		for (u32 i = 0; i < num; i++) {
			lookup(ids[i]).set_volume(volumes[i]);
		}
	}

	void reload_sounds(const SoundResource *old_sr, const SoundResource *new_sr)
	{
		for (u32 i = 0; i < _num_objects; ++i) {
			if (_playing_sounds[i]._resource == old_sr) {
				_playing_sounds[i].reload(_resource_manager, new_sr);
			}
		}
	}

	void set_listener_pose(const Matrix4x4 &pose)
	{
		const Vector3 pos = translation(pose);
		const Vector3 up = y(pose);
		const Vector3 at = z(pose);

		AL_CHECK(alListener3f(AL_POSITION, pos.x, pos.y, pos.z));
		// AL_CHECK(alListener3f(AL_VELOCITY, vel.x, vel.y, vel.z));

		const ALfloat orientation[] = { up.x, up.y, up.z, at.x, at.y, at.z };
		AL_CHECK(alListenerfv(AL_ORIENTATION, orientation));
		_listener_pose = pose;
	}

	void update()
	{
		TempAllocator256 alloc;
		Array<SoundInstanceId> to_delete(alloc);

		// Update instances with new samples.
		for (u32 i = 0; i < _num_objects; ++i) {
			SoundInstance &instance = _playing_sounds[i];

			instance.update();
			if (instance.finished())
				array::push_back(to_delete, instance._id);
		}

		// Destroy instances which finished playing
		for (u32 i = 0; i < array::size(to_delete); ++i) {
			stop(to_delete[i]);
		}
	}
};

SoundWorld::SoundWorld(Allocator &a, ResourceManager &rm)
	: _marker(SOUND_WORLD_MARKER)
	, _allocator(&a)
	, _impl(NULL)
{
	_impl = CE_NEW(*_allocator, SoundWorldImpl)(rm);
}

SoundWorld::~SoundWorld()
{
	CE_DELETE(*_allocator, _impl);
	_marker = 0;
}

SoundInstanceId SoundWorld::play(StringId64 name, bool loop, f32 volume, f32 range, const Vector3 &pos)
{
	return _impl->play(name, loop, volume, range, pos);
}

void SoundWorld::stop(SoundInstanceId id)
{
	_impl->stop(id);
}

bool SoundWorld::is_playing(SoundInstanceId id)
{
	return _impl->is_playing(id);
}

void SoundWorld::stop_all()
{
	_impl->stop_all();
}

void SoundWorld::pause_all()
{
	_impl->pause_all();
}

void SoundWorld::resume_all()
{
	_impl->resume_all();
}

void SoundWorld::set_sound_positions(u32 num, const SoundInstanceId *ids, const Vector3 *positions)
{
	_impl->set_sound_positions(num, ids, positions);
}

void SoundWorld::set_sound_ranges(u32 num, const SoundInstanceId *ids, const f32 *ranges)
{
	_impl->set_sound_ranges(num, ids, ranges);
}

void SoundWorld::set_sound_volumes(u32 num, const SoundInstanceId *ids, const f32 *volumes)
{
	_impl->set_sound_volumes(num, ids, volumes);
}

void SoundWorld::reload_sounds(const SoundResource *old_sr, const SoundResource *new_sr)
{
	_impl->reload_sounds(old_sr, new_sr);
}

void SoundWorld::set_listener_pose(const Matrix4x4 &pose)
{
	_impl->set_listener_pose(pose);
}

void SoundWorld::update()
{
	_impl->update();
}

} // namespace crown

#endif // if CROWN_SOUND_OPENAL
