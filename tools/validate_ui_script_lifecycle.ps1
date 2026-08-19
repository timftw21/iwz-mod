param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$uiScriptRoot = Join-Path $RepoRoot "data\cdata\ui_scripts"

if (-not (Test-Path -LiteralPath $uiScriptRoot -PathType Container)) {
	Write-Error "UI script directory not found: $uiScriptRoot"
	exit 1
}

$violations = @()

Get-ChildItem -LiteralPath $uiScriptRoot -Filter "*.lua" -File -Recurse | ForEach-Object {
	$lines = Get-Content -LiteralPath $_.FullName

	for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
		# Project UI scripts keep file-scope statements unindented. Inspect complete
		# top-level if conditions so split conditions are covered as well.
		if ($lines[$lineIndex] -notmatch '^if\b') {
			continue
		}

		$condition = $lines[$lineIndex]
		$conditionEnd = $lineIndex
		while ($condition -notmatch '\bthen\s*(--.*)?$' -and $conditionEnd + 1 -lt $lines.Count) {
			$conditionEnd++
			$condition += " " + $lines[$conditionEnd].Trim()
		}

		$targetsFrontendVm = $condition -match 'not\s+Engine\.InFrontend\s*\(\s*\)'
		$gatesOnInitialMode = $condition -match 'Engine\.IsAliensMode\s*\(\s*\)'

		if ($targetsFrontendVm -and $gatesOnInitialMode) {
			$violations += "$($_.FullName):$($lineIndex + 1)"
		}

		$lineIndex = $conditionEnd
	}
}

if ($violations.Count -gt 0) {
	Write-Error ("Unsafe frontend UI lifecycle gate detected at: " + ($violations -join ", ") +
		". Frontend HKS can start before Zombies mode is selected. Register the wrapper " +
		"for every frontend VM and check CONDITIONS.IsThirdGameMode inside the menu constructor.")
	exit 1
}

Write-Host "UI script lifecycle validation passed."
