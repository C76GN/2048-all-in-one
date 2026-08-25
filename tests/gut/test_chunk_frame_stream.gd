## 验证 persistence Module 的 Feature-neutral framed Variant stream mechanics。
extends GutTest


func test_writer_reader_roundtrip_across_chunk_boundary_and_claim_once() -> void:
	var writer: ChunkFrameStreamWriter = ChunkFrameStreamWriter.new()
	var expected_frames: Array[Dictionary] = []
	for index: int in range(70):
		var bytes: PackedByteArray = PackedByteArray()
		assert_true(bytes.resize(2000) == OK)
		bytes.fill(index & 0xff)
		var frame: Dictionary = {
			&"record_index": index,
			&"bytes": bytes,
		}
		expected_frames.append(frame)
		assert_true(writer.append_variant_frame(frame, "Test frame"))
	assert_true(writer.finish())
	assert_true(writer.is_finished())

	var chunks: Array[PackedByteArray] = writer.take_chunks_taking_ownership()
	assert_true(chunks.size() >= 2)
	if chunks.size() < 2:
		return
	assert_true(chunks[0].size() == ChunkFrameStreamWriter.CHUNK_BYTES)
	assert_true(writer.take_chunks_taking_ownership().is_empty())

	var reader: ChunkFrameStreamReader = (
		ChunkFrameStreamReader.begin_reading_taking_ownership(chunks)
	)
	assert_not_null(reader)
	if reader == null:
		return
	for expected: Dictionary in expected_frames:
		var result: Dictionary = reader.read_variant_frame()
		assert_true(GFVariantData.get_option_bool(result, &"ok", false))
		var actual: Dictionary = GFVariantData.get_option_dictionary(
			result,
			&"value"
		)
		assert_true(actual == expected)
	assert_true(reader.get_remaining_bytes() == 0)
	assert_false(
		GFVariantData.get_option_bool(
			reader.read_variant_frame(),
			&"ok",
			false
		)
	)


func test_reader_rejects_nonfinal_partial_chunk_boundary() -> void:
	var partial_chunk: PackedByteArray = PackedByteArray([0, 0, 0, 1, 0])
	var final_chunk: PackedByteArray = PackedByteArray([0, 0, 0, 1, 0])
	assert_false(ChunkFrameStreamReader.are_chunk_boundaries_valid([
		partial_chunk,
		final_chunk,
	]))
	assert_null(
		ChunkFrameStreamReader.begin_reading_taking_ownership([
			partial_chunk,
			final_chunk,
		])
	)


func test_writer_fails_closed_for_shared_variant_budget() -> void:
	var deep_value: Variant = 0
	for _depth: int in range(
		ChunkFrameVariantBudget.MAX_VARIANT_DEPTH + 1
	):
		deep_value = {&"child": deep_value}
	var too_many_nodes: Array = []
	assert_true(
		too_many_nodes.resize(
			ChunkFrameVariantBudget.MAX_VARIANT_NODES + 1
		) == OK
	)
	for hostile_value: Variant in [deep_value, too_many_nodes]:
		var writer: ChunkFrameStreamWriter = ChunkFrameStreamWriter.new()
		assert_false(writer.append_variant_frame(hostile_value, "Hostile frame"))
		assert_true(writer.is_failed())
		assert_true(writer.get_error_code() == ERR_OUT_OF_MEMORY)
		assert_false(writer.finish())
		assert_true(writer.take_chunks_taking_ownership().is_empty())
