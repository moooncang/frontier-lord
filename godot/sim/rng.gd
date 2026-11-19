class_name Xoshiro128
## xoshiro128** (07번 5절). 32비트 연산을 64비트 int에 마스크로 구현한다.
## 스트림 6개는 세계·기후·외교·전투·사건·특전 순서로 0~5다.

const M := 0xFFFFFFFF
const STREAMS := ["world", "climate", "diplomacy", "battle", "event", "perk"]

var s := [0, 0, 0, 0]
var count := 0 # 소비한 난수 수. 저장해 재현에 쓴다.


func _init(run_seed: int, stream: int = 0) -> void:
	# 시드 파생: splitmix32(seed ^ stream*0x9E3779B9)로 상태 4칸을 채운다.
	var x := (run_seed ^ (stream * 0x9E3779B9)) & M
	for i in 4:
		x = (x + 0x9E3779B9) & M
		var z := x
		z = ((z ^ (z >> 16)) * 0x85EBCA6B) & M
		z = ((z ^ (z >> 13)) * 0xC2B2AE35) & M
		s[i] = (z ^ (z >> 16)) & M
	if s == [0, 0, 0, 0]:
		s[0] = 1


static func _rotl(x: int, k: int) -> int:
	return ((x << k) | (x >> (32 - k))) & M


func next_u32() -> int:
	var result: int = (_rotl((s[1] * 5) & M, 7) * 9) & M
	var t: int = (s[1] << 9) & M
	s[2] ^= s[0]
	s[3] ^= s[1]
	s[1] ^= s[2]
	s[0] ^= s[3]
	s[2] ^= t
	s[3] = _rotl(s[3], 11)
	count += 1
	return result


func randf() -> float:
	return next_u32() / 4294967296.0


func randi_range(a: int, b: int) -> int:
	return a + next_u32() % (b - a + 1)
