param([string]$GodotPath = '')
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
        if ($match.Success) { $GodotPath = $match.Groups[1].Value -replace '_console\.exe$', '.exe' }
    }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath)) {
    throw 'Godot 실행 파일을 -GodotPath로 지정해 주세요.'
}
Start-Process -FilePath $GodotPath -WorkingDirectory $projectRoot -ArgumentList @('--path', ('"' + $projectRoot + '"'), '-s', 'scripts/play-preview.gd')
