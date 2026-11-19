# 변경의 신임 영주가 되었다

변경의 영주가 되어 52주 동안 영지를 꾸리는 영지 경영 로그라이트. Godot 4.7.2로 만든다.

**브라우저에서 바로 하기: https://moooncang.github.io/frontier-lord/**

처음 열 때 100MB쯤 내려받는다. 화면은 가로 1280 이상에서 맞게 보인다. 저장은 브라우저 안에 남는다.

## 폴더

| 폴더 | 내용 |
|---|---|
| [godot/](godot/) | 게임 본체. 규칙은 `sim/`, 화면은 `ui/`, 데이터는 `content/`, 검사는 `tests/` |
| [기획서/](기획서/) | 제작 기준 문서 12편 |
| [에셋 원본/](에셋%20원본/) | 도트 에셋 원본 시트 |
| [에셋 생성 요청서.md](에셋%20생성%20요청서.md) | 에셋 발주 내역 |

현재 구현 범위와 최근 변경은 [godot/README.md](godot/README.md)에 있다.

## 실행

Godot 4.7.2로 `godot/project.godot`을 연다. 테스트는 다음처럼 돌린다.

```
godot --headless --path godot -s tests/test_realm_rules.gd
```

## 웹 빌드 다시 올리기

`godot/export_presets.cfg`의 Web 프리셋으로 내보낸 뒤 `gh-pages` 브랜치에 올린다.

```
godot --headless --path godot --export-release "Web" ../web-build/index.html
```
