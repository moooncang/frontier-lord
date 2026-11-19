class_name ConciseCopy
extends RefCounted
## 표시 문구만 줄인다. 비용은 호출 화면에서 session.event_cost(option)로 계산한다.

const EVENTS := {
	"EV01": {
		"title": "첫 운영 방침",
		"body": "주민을 먼저 돕거나 행정관과 업무를 정비할 수 있습니다.",
		"labels": ["주민 지원을 먼저 한다", "행정 업무를 먼저 정리한다"]
	},
	"EV02": {
		"title": "이민자 12명",
		"body": "이민자 12명이 정착을 요청했습니다. 주거 12명분과 정착 물자가 필요합니다.",
		"labels": ["정착을 지원해 받아들인다", "식량만 나누고 돌려보낸다", "이번에는 지원하지 않는다"]
	},
	"EV03": {
		"title": "교역로 정비",
		"body": "교역로를 정비하면 남은 회차의 운송 수수료가 줄어듭니다.",
		"labels": ["교역로 정비에 투자한다", "현재 운송 조건을 유지한다"]
	},
	"EV04": {
		"title": "추가 이민 12명",
		"body": "이민자 12명이 더 왔습니다. 주거 12명분과 정착 물자가 필요합니다.",
		"labels": ["정착을 지원해 받아들인다", "기존 주민의 생활을 돌본다"]
	},
	"EV05": {
		"title": "겨울 자재 구매",
		"body": "겨울 준비에 쓸 목재나 장작을 구매할 수 있습니다.",
		"labels": ["목재 30을 구매한다", "장작 120을 구매한다", "추가 구매 없이 준비한다"]
	},
	"EV06": {
		"title": "배급할 식량",
		"body": "공공 식량 80을 주민 창고로 옮길 수 있습니다. 배급할지 비축할지 정해 주세요.",
		"labels": ["주민 창고로 식량을 보낸다", "공공 창고의 식량을 지킨다"]
	},
	"EV07": {
		"title": "겨울 지원",
		"body": "경비 장비를 보강하거나 공동 숙소에 지원금을 보낼 수 있습니다.",
		"labels": ["경비대의 장비를 보강한다", "공동 숙소 운영을 지원한다", "현재 겨울 계획을 유지한다"]
	},
	"EV08": {
		"title": "마지막 점검",
		"body": "올해 통치가 끝나기 전, 주민을 돌보거나 행정 업무를 점검할 수 있습니다.",
		"labels": ["주민의 생활 상태를 살핀다", "행정 업무를 마지막 점검한다"]
	},
	"EV09": {
		"title": "진료소 지원",
		"body": "진료소에 식량을 보내면 주민 건강을 높일 수 있습니다.",
		"labels": ["진료소에 식량을 지원한다", "식량을 비축해 두기로 한다"]
	},
	"EV10": {
		"title": "농업 연구 지원",
		"body": "도구 1개를 지원하면 보관 중인 식량 60을 추가로 확보합니다.",
		"labels": ["도구를 주고 식량을 얻는다", "현재 보유한 도구를 남긴다"]
	},
	"EV11": {
		"title": "목재 매입 제안",
		"body": "이웃 영지가 목재 30을 사겠다고 합니다. 대금은 즉시 받습니다.",
		"labels": ["이웃 영지에 목재를 판다", "건설에 쓸 목재를 남긴다"]
	},
	"EV12": {
		"title": "도구 보수",
		"body": "두르간이 돈을 받고 공용 도구 3개를 보수하겠다고 합니다.",
		"labels": ["도구 보수 비용을 지급한다", "현재 쓰는 도구를 유지한다"]
	},
	"EV13": {
		"title": "장작 교환 제안",
		"body": "식량 40을 내주면 발견한 장작 80을 가져오겠다고 합니다.",
		"labels": ["식량을 내주고 장작을 받는다", "비축한 식량을 그대로 둔다"]
	},
	"EV14": {
		"title": "왕실 감찰",
		"body": "감찰관이 행정관과 장부를 검토하자고 합니다.",
		"labels": ["행정관과 함께 장부를 본다", "기존 업무 순서를 유지한다"]
	},
	"EV15": {
		"title": "용병대 순찰",
		"body": "용병대가 돈을 받고 교역로를 순찰하겠다고 합니다.",
		"labels": ["용병대의 순찰을 의뢰한다", "현재 경비 인력을 유지한다"]
	}
}

const EFFECT_NAMES := {
	"food": "공공 식량", "wood": "목재", "stone": "석재", "tools": "도구",
	"fuel": "장작", "money": "금고", "resident_food": "주민 식량",
	"pop": "인구", "mood": "민심", "health": "건강", "security": "치안",
	"trust": "행정관 신뢰", "village": "주민 관계", "guild": "상인 호감"
}

const PERK_NAMES := {
	"harvest": "수확량", "sow_labor": "파종 필요 인력", "seed": "파종 종자 소모",
	"gather": "채집량", "logging": "벌목량", "tool_use": "벌목·채석 도구 소모",
	"maintenance": "시설 유지비", "wages": "공공 급여", "buy": "물자 구매가",
	"storage": "식량 저장 용량", "heating": "난방 장작 소비"
}


static func event_brief(id: String, event: Dictionary) -> Dictionary:
	var copy: Dictionary = EVENTS.get(id, {})
	var labels: Array = copy.get("labels", [])
	var options: Array[Dictionary] = []
	var original: Array = event.get("options", [])
	for index in original.size():
		var option: Dictionary = original[index]
		options.append({
			"label": labels[index] if index < labels.size() else str(option.get("label", "선택")),
			"effect": _effects(option.get("effects", {}))
		})
	return {
		"title": copy.get("title", event.get("title", "영지 소식")),
		"body": copy.get("body", event.get("body", "")),
		"options": options
	}


static func _effects(effects: Dictionary) -> String:
	var parts: Array[String] = []
	for key in effects:
		var value: float = float(effects[key])
		if key == "trade_discount":
			parts.append("운송 수수료 " + _signed(-value * 100.0) + "%")
		elif key == "money":
			parts.append("금고 " + _signed(value / 100.0) + "금")
		else:
			parts.append(str(EFFECT_NAMES.get(key, key)) + " " + _signed(value))
	return " · ".join(parts) if not parts.is_empty() else "변화 없음"


static func perk_brief(_id: String, perk: Dictionary) -> String:
	if not perk.get("extra_bonuses", {}).is_empty():
		return str(perk.get("description", "")).replace("\n", " · ")
	var effect: String = str(perk.get("effect", ""))
	var value: float = float(perk.get("value", 1.0))
	match effect:
		"tax": return "세금 수금률 " + _signed(value * 100.0) + "%p"
		"trust": return "면담 신뢰 회복 " + _signed(value)
		"winter_gather": return "겨울 채집 " + _signed(value * 100.0) + "%p (봄 생산량 기준)"
	if PERK_NAMES.has(effect):
		return str(PERK_NAMES[effect]) + " " + _signed((value - 1.0) * 100.0) + "%"
	return str(perk.get("description", "")).replace("\n", " · ")


static func _signed(value: float) -> String:
	var amount: String = "%.0f" % value if is_equal_approx(value, roundf(value)) else "%.2f" % value
	return ("+" if value > 0 else "") + amount
