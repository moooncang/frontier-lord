class_name Constants
## 기획서 10번 1절·05번 3절의 기본값. 같은 이름의 값을 다른 파일에 따로 두지 않는다.

const DAYS_PER_WEEK := 7
const WEEKS_PER_SEASON := 13
const WEEKS_PER_YEAR := 52
const FOOD_PER_PERSON_WEEK := 1.0
const BASE_FARM_HARVEST := 540.0
const SEED_PER_PLOT := 24
const YARD_SPOILAGE := 0.02 # 02번 5절: 창고 용량 초과분
const FOOD_REFERENCE_PRICE := 2 # 곡물 1단위당 동
const COPPER_PER_GOLD := 100
const TAX_BASE_RURAL := 100 # 정규화 과세 인구당 연 동
const TAX_COLLECTION_BASE := 0.85
const TAX_IN_KIND_SHARE := 0.20
const TRIBUTE_RATE := 0.20
const SOLDIER_ANNUAL_WAGE := 800
const PUBLIC_WORKER_ANNUAL_WAGE := 600
const MAINTENANCE_RATE := 0.05
const BIRTH_RATE_YEAR := 0.024 # 02번 2절
const DEATH_RATE_YEAR := 0.012

## 시설 등급별 건설 묶음. 금화 단위는 금, 작업량은 인주.
const GRADE_COST := {
	"T": {"gold": 0, "wood": 0, "stone": 0, "tools": 0, "iron": 0, "work": 0, "staff": 0},
	"A": {"gold": 4, "wood": 8, "stone": 0, "tools": 1, "iron": 0, "work": 8, "staff": 2},
	"B": {"gold": 12, "wood": 20, "stone": 10, "tools": 2, "iron": 0, "work": 24, "staff": 4},
	"C": {"gold": 40, "wood": 40, "stone": 40, "tools": 4, "iron": 0, "work": 80, "staff": 6},
	"D": {"gold": 140, "wood": 80, "stone": 160, "tools": 8, "iron": 10, "work": 240, "staff": 12},
	"E": {"gold": 500, "wood": 160, "stone": 600, "tools": 16, "iron": 40, "work": 800, "staff": 24},
	"F": {"gold": 1600, "wood": 300, "stone": 1800, "tools": 30, "iron": 100, "work": 2400, "staff": 48},
}
