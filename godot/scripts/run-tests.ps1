param(
    [string]$GodotPath = '',
    [switch]$Render
)
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $GodotPath) {
    $command = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $GodotPath = $command.Source }
}
if (-not $GodotPath) {
    $metadata = Join-Path $projectRoot '.godot\editor\project_metadata.cfg'
    if (Test-Path -LiteralPath $metadata) {
        $match = [regex]::Match((Get-Content -LiteralPath $metadata -Raw), 'executable_path="([^"]+)"')
        if ($match.Success) { $GodotPath = $match.Groups[1].Value }
    }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath)) {
    throw 'Godot 4.7 실행 파일을 -GodotPath로 지정해 주세요.'
}
$consolePath = $GodotPath -replace '(?<!_console)\.exe$', '_console.exe'
if (Test-Path -LiteralPath $consolePath) { $GodotPath = $consolePath }
$output = Join-Path $projectRoot 'tests\output'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$previousAppData = $env:APPDATA
$previousLocalData = $env:LOCALAPPDATA
try {
    # 이 테스트 프로세스의 Godot 데이터만 작업 폴더에 격리한다.
    $env:APPDATA = Join-Path $output 'appdata'
    $env:LOCALAPPDATA = Join-Path $output 'localdata'
    New-Item -ItemType Directory -Force -Path $env:APPDATA,$env:LOCALAPPDATA | Out-Null
    $importLog = Join-Path $output 'import.log'
    & $GodotPath --headless --path $projectRoot --editor --quit --log-file $importLog
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $importLog -Pattern 'SCRIPT ERROR|Parse Error|Compile Error' -Quiet)) {
        throw 'Godot 스크립트 임포트 실패'
    }
    foreach ($test in @('test_year_one','test_gameplay','test_ui','test_chronicle','test_weekly_brief','test_cabinet_rules','test_cabinet_actions','test_legacy_path','test_house_content','test_seasonal_investments','test_frontier_difficulty','test_fantasy_frontiers','test_fantasy_replay','test_fantasy_board','test_fantasy_frontier_ui','test_house_legacy','test_house_ui','test_season_support_ui','test_district_board','test_office_ui','test_campaign_director','test_turn_receipt','test_onboarding','test_workcrew_rules','test_realm_rules','test_realm_construction','test_realm_feedback','test_realm_playflow','test_expedition_modifiers','test_village_relics','test_content_plus','test_event_expansion','test_crisis_director','test_relics_plus','test_operating_builds','test_plus_ui','test_event_expansion_ui','test_operating_builds_ui','test_village_relics_ui','test_realm_ui','test_chronicle_ui','test_steward_ui','test_cabinet_ui','test_expedition_ui','test_guided_run','test_week_feedback','test_exit_flow')) {
        $log = Join-Path $output ($test + '.log')
        & $GodotPath --headless --path $projectRoot --log-file $log -s ('tests/' + $test + '.gd')
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|ERROR:' -Quiet)) {
            throw ($test + ' 실패: ' + $log)
        }
    }
    if ($Render) {
        foreach ($sceneTest in @('test_district_board','test_office_ui','test_season_support_ui','test_fantasy_board','test_fantasy_frontier_ui')) {
            $sceneLog = Join-Path $output ($sceneTest + '_render.log')
            & $GodotPath --path $projectRoot --log-file $sceneLog -s ('tests/' + $sceneTest + '.gd')
            if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $sceneLog -Pattern 'SCRIPT ERROR|ERROR:' -Quiet)) {
                throw ($sceneTest + ' 렌더링 검증 실패')
            }
        }
        $houseLog = Join-Path $output 'house_ui_render.log'
        & $GodotPath --path $projectRoot --log-file $houseLog -s tests/test_house_ui.gd
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $houseLog -Pattern 'SCRIPT ERROR|ERROR:' -Quiet)) {
            throw '가문 강화·방침·지원 물자·특전 선택권 렌더링 검증 실패'
        }
        $buildsLog = Join-Path $output 'operating_builds_render.log'
        & $GodotPath --path $projectRoot --log-file $buildsLog -s tests/test_operating_builds_ui.gd
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $buildsLog -Pattern 'SCRIPT ERROR|ERROR:' -Quiet)) {
            throw '운영 조합·성물 교체 예고·특전 연결 렌더링 검증 실패'
        }
        $eventLog = Join-Path $output 'event_expansion_render.log'
        & $GodotPath --path $projectRoot --log-file $eventLog -s tests/test_event_expansion_ui.gd
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $eventLog -Pattern 'SCRIPT ERROR|ERROR:' -Quiet)) {
            throw '긍정·부정 사건 선택·성물 대응·후속 예고 렌더링 검증 실패'
        }
        $plusLog = Join-Path $output 'plus_render.log'
        & $GodotPath --path $projectRoot --log-file $plusLog -s tests/test_plus_ui.gd
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $plusLog -Pattern 'SCRIPT ERROR|ERROR:' -Quiet)) {
            throw '위기 예고·대비·압박 단계 렌더링 검증 실패'
        }
        $log = Join-Path $output 'render.log'
        & $GodotPath --path $projectRoot --log-file $log -s tests/test_ui.gd
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|ERROR:' -Quiet)) {
            throw '렌더링 검증 실패'
        }
        $log = Join-Path $output 'realm_render.log'
        & $GodotPath --path $projectRoot --log-file $log -s tests/test_realm_ui.gd
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|ERROR:' -Quiet)) {
            throw 'realm UI render check failed'
        }
        $log = Join-Path $output 'village_relics_render.log'
        & $GodotPath --path $projectRoot --log-file $log -s tests/test_village_relics_ui.gd
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|ERROR:' -Quiet)) {
            throw '성물 선택·성소·발견 도감 렌더링 검증 실패'
        }
        $log = Join-Path $output 'chronicle_render.log'
        & $GodotPath --path $projectRoot --log-file $log -s tests/test_chronicle_ui.gd
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|ERROR:' -Quiet)) {
            throw '변경 연대기 렌더링 검증 실패'
        }
        $log = Join-Path $output 'steward_render.log'
        & $GodotPath --path $projectRoot --log-file $log -s tests/test_steward_ui.gd
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|ERROR:' -Quiet)) {
            throw '주간 보고 UI 렌더링 검증 실패'
        }
        $log = Join-Path $output 'cabinet_render.log'
        & $GodotPath --path $projectRoot --log-file $log -s tests/test_cabinet_ui.gd
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|ERROR:' -Quiet)) {
            throw '간편 통치 UI 렌더링 검증 실패'
        }
        $log = Join-Path $output 'expedition_render.log'
        & $GodotPath --path $projectRoot --log-file $log -s tests/test_expedition_ui.gd
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|ERROR:' -Quiet)) {
            throw '출정·계절 운영 UI 렌더링 검증 실패'
        }
        $log = Join-Path $output 'guided_render.log'
        & $GodotPath --path $projectRoot --log-file $log -s tests/test_guided_run.gd
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|ERROR:' -Quiet)) {
            throw '실제 조작 튜토리얼 검증 실패'
        }
        $log = Join-Path $output 'exit_render.log'
        & $GodotPath --path $projectRoot --log-file $log -s tests/test_exit_flow.gd
        if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|ERROR:' -Quiet)) {
            throw '저장 실패·종료 흐름 검증 실패'
        }
    }
    Write-Output '전체 검증 통과'
} finally {
    $env:APPDATA = $previousAppData
    $env:LOCALAPPDATA = $previousLocalData
}
