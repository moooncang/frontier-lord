# 에셋 적용 현황

게임명: **변경의 신임 영주가 되었다**. 실제 연결은 `content/assets.json`이 기준이다. 2026-11-18 개편부터 영주관·집무실과 별도 건설 지구가 같은 도트 팔레트를 사용한다. 본문과 버튼 글자는 읽기 쉬운 한글 시스템 글꼴로 표시한다.

## 현재 사용하는 신규 세트

`assets/frontier_v2/`에 내장 **image_gen**으로 생성한 PNG 원본 8장과 독립 시설 `AtlasTexture` 27종과 겨울 교체 텍스처 9종을 저장했다. 투명 PNG의 알파는 그대로 보존한다. 게임에서는 각 시설을 별도 노드·클릭 영역으로 합성하므로 배경에 건설 결과가 미리 그려져 있지 않다.

| 파일 | 용도 |
|---|---|
| `manor.png` | 영주관 메뉴와 영지 집무실 |
| `district.png` | 봄·여름 건설 지구. 길과 두 지면 기준 고정 |
| `district_autumn.png`, `district_winter.png` | 같은 구도의 가을·겨울 지형 |
| `settlement_a.png` | 주거·우물·선술집·진료소·예배당·장터·수레 차고·서기관실·성소 |
| `settlement_b.png` | 농지·채소밭·채집터·방앗간·훈연장·곳간·벌목소·제재소·채석장 |
| `settlement_c.png` | 대장간·목책·망루·제빵소·어장·임시 주거·임시 곳간·행정 천막·공사장 |
| `settlement_b_winter.png` | 수확 후 밭·휴지기 채소밭과 눈 덮인 생산 시설 9종 |
| `building_*.tres` | 시트의 418×418 영역을 참조하는 개별 시설 텍스처 |

지형·집무실 PNG는 1536×1024, 시설 시트는 1254×1254다. 3×3 영역의 각 건물은 독립적으로 표시한다. 모든 시설 22종에 전용 그림이 있으며 임시 시설과 공사장도 완성 시설 그림을 대신 사용하지 않는다. Godot의 nearest 필터와 픽셀 단위 배치로 합성한다. 배경의 지면에 발 위치를 맞추고, 지구별 5~6개 시설만 표시한다.

최종 생성 프롬프트: [generation_prompts.json](frontier_v2/generation_prompts.json), 계절 편집 프롬프트: [seasonal_edit_prompts.json](frontier_v2/seasonal_edit_prompts.json). 겨울 시설 편집은 [winter_sprite_prompt.json](frontier_v2/winter_sprite_prompt.json)에 기록했다. 별도 API·CLI는 사용하지 않았다. 새로운 배경이 과거 일체형 전경이나 기존 건물 파일을 덮어쓰지 않는다.

## 사건·성장에 따른 판타지 지구

`assets/fantasy_v1/`에는 내장 **image_gen**으로 새로 제작한 배경 6장과 투명 건물 시트 2장, 독립 시설 `AtlasTexture` 18종이 있다. 기존 자산은 보존했다. [최종 생성·편집 프롬프트](fantasy_v1/generation_prompts.json)에 모든 요청을 기록했다. 별도 API·CLI나 이미지 후처리로 원본의 알파를 변경하지 않았다.

| 계열 | 배경 | 독립 건물 3종 |
|---|---|---|
| 정령숲 | `district_grove.png` | 정령 묘목원 · 살아있는 수로 · 세계수 정원 |
| 화룡 | `district_ember.png` | 불씨 사육장 · 용열 가마 · 화룡 대화로 |
| 달빛수로 | `district_tide.png` | 달빛 우물 · 수정 양식장 · 조수 성소 |
| 태엽 | `district_clockwork.png` | 태엽 작업장 · 골렘 채석장 · 자동공방 |
| 망령 | `district_veil.png` | 납골 봉인소 · 기억의 전당 · 황혼 파수탑 |
| 별 | `district_astral.png` | 별빛 관측소 · 마력 온실 · 천구 도서관 |

배경은 1536×1024이고 기존 지형의 도로·두 단 지면을 유지한다. 시트 `fantasy_a.png`(정령숲·화룡·달빛수로)와 `fantasy_b.png`(태엽·망령·별)는 1254×1254이며 각 418×418 셀을 별도 시설로 사용한다. B 시트는 칸 사이 여백을 넓혀 다시 생성했고, 텍스처 참조 영역만 투명 여백 안쪽으로 맞춰 건물 크기와 발 위치를 정렬했다. 원본 PNG는 수정하지 않았다. 연결 키는 `realm_district_<계열>`과 `building_fantasy_<계열>_<1~3>`이다.

이계 지구에는 채택한 계열만 표시한다. 계열당 3개 건물을 한 줄에 배치하며, 두 계열을 채택하면 최대 6개 시설과 두 지형을 위·아래 줄로 합성한다. 최초 완공부터 전용 배경으로 변하고 완공 수에 따라 불빛·표식이 늘어난다. 세 건물을 모두 완공하면 정령숲·달빛수로는 농경지, 화룡·태엽은 작업장, 망령은 성벽, 별은 마을의 배경에도 영향을 준다. 판타지 연출은 저장 상태를 읽을 뿐 경제 수치나 난수를 변경하지 않는다.

## 인물·성물과 기존 원본

정본 인물 12장과 성물 48종은 기존 자산을 계속 사용한다. CH01 오딜, CH02 카트린, CH03 아녜스, CH04 베아트릭스, CH05 이네스, CH06 시아렐, CH07 클로틸드, CH08 두르간, CH09 요스트, CH10 마티아스, CH11 디트마르, CH12 잉가의 대응은 `기획서/04 인물과 사건 설계.md`를 따른다. 보좌관 정보는 실제 임명 상태를 읽어 표시한다.

이전 `world/*.webp`, `backgrounds/settlement_s1_*.webp`, `interiors/study.webp`, `interface/*.webp`는 호환·비교용으로 보존한다. 건강·치안의 일부 작은 아이콘은 대체 표시가 남아 있다.

과거 생성 기록은 `../../에셋 원본/`의 `generation_canonical.json`, `generation_pixel.json`, `generation_modular.json`, `generation_study.json`, `generation_expedition.json`, `generation_pixel_ui.json`에 남아 있다. 재패키징 스크립트 `prepare_modular.gd`, `prepare_characters.gd`, `prepare_assets.gd`, `prepare_study.gd`는 이전 세트를 위한 것이다. 신규 세트는 PNG와 AtlasTexture를 직접 임포트한다.

## 글꼴과 UI

`RealmTheme`가 얇은 픽셀 경계, 목재·철색·밝은 장부색을 공통으로 제공한다. 선택 상태, 주 행동, 보조 행동을 구분하며 본문을 그림에 굽지 않는다. 설명은 보통 18px 이상, 주요 수치는 24px, 버튼은 19px다. 공간이 작은 HUD 보조 표기만 14~18px를 사용한다. 실제 비용과 주 행동은 항상 화면 안에서 확인할 수 있게 한다.

특수 연출용 [Galmuri](https://github.com/quiple/galmuri)는 `fonts/`에 보관하며 라이선스는 동봉한 SIL OFL 1.1을 따른다. 배포 시 JSON 파일은 export 포함 필터 `*.json`에 포함한다.
