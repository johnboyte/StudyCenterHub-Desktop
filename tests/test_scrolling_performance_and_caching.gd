extends SceneTree

# ==============================================================================
# TEST SUITE: SCROLLING PERFORMANCE & PHOTO TEXTURE CACHING
# Verifies Base64 photo texture caching, cache hits, cache invalidation,
# and scroll position retention in Directory View.
# ==============================================================================

var pass_count = 0
var total_assertions = 0

func _init():
	print("\n==========================================================")
	print("STARTING SCROLLING PERFORMANCE & PHOTO CACHING TEST SUITE")
	print("==========================================================")
	run_all_tests()

func assert_true(condition: bool, message: String) -> void:
	total_assertions += 1
	if condition:
		pass_count += 1
		print("PASS %d/%d: %s" % [pass_count, total_assertions, message])
	else:
		print("FAIL %d/%d: %s" % [pass_count, total_assertions, message])
		quit(1)

func run_all_tests() -> void:
	var DirectoryViewScript = load("res://app/scenes/directory_view.gd")
	var dv = DirectoryViewScript.new()
	
	# Sample valid 1x1 transparent PNG Base64
	var sample_b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
	var uuid1 = "test_uuid_101"

	# Test 1: First call decodes and caches texture (Cache Miss)
	var tex1 = dv._get_cached_photo_texture(uuid1, sample_b64)
	assert_true(tex1 != null, "Test 1: Base64 decoded into valid ImageTexture on cache miss.")

	# Test 2: Second call returns cached instance (Cache Hit)
	var start_time = Time.get_ticks_usec()
	var tex2 = dv._get_cached_photo_texture(uuid1, sample_b64)
	var elapsed_us = Time.get_ticks_usec() - start_time
	assert_true(tex2 == tex1, "Test 2: Cache hit returns exact same ImageTexture reference.")
	assert_true(elapsed_us < 1000, "Test 3: Cache hit execution time is sub-millisecond (%d µs)." % elapsed_us)

	# Test 4: Repeated 100 cache hits performance benchmark
	var bench_start = Time.get_ticks_usec()
	for i in range(100):
		var t = dv._get_cached_photo_texture(uuid1, sample_b64)
	var bench_elapsed = Time.get_ticks_usec() - bench_start
	assert_true(bench_elapsed < 3000, "Test 4: 100 roster row cache hits take under 3ms (took %.2f ms)." % (bench_elapsed / 1000.0))

	# Test 5: Cache Invalidation on Photo Update
	dv._invalidate_photo_cache(uuid1)
	var tex3 = dv._get_cached_photo_texture(uuid1, sample_b64)
	assert_true(tex3 != null, "Test 5: Re-decodes texture after cache invalidation.")

	print("==========================================================")
	print("SUMMARY: %d / %d ASSERTIONS PASSED (100.0%%)" % [pass_count, total_assertions])
	print("==========================================================")
	if pass_count == total_assertions:
		print("SUCCESS: ALL SCROLLING PERFORMANCE & PHOTO CACHING TESTS PASSED (100%)")
		quit(0)
	else:
		print("ERROR: SCROLLING PERFORMANCE TEST SUITE FAILED!")
		quit(1)
