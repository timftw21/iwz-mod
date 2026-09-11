param([int]$Port = 8765)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'node_modules/three/build/three.module.js'))) {
    npm ci --prefix $PSScriptRoot --ignore-scripts --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { throw 'Could not install viewer dependency' }
}
Write-Host "Open http://127.0.0.1:$Port in your browser. Keep this terminal running."
python (Join-Path $PSScriptRoot 'server.py') --port $Port
