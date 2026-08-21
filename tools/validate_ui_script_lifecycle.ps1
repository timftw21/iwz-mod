param(
	[string]$RepoRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$uiScriptRoot = Join-Path $RepoRoot "data\cdata\ui_scripts"
$uiScriptingSource = Join-Path $RepoRoot "src\client\component\ui_scripting.cpp"

if (-not (Test-Path -LiteralPath $uiScriptRoot -PathType Container)) {
	Write-Error "UI script directory not found: $uiScriptRoot"
	exit 1
}

if (-not (Test-Path -LiteralPath $uiScriptingSource -PathType Leaf)) {
	Write-Error "UI scripting source not found: $uiScriptingSource"
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

$uiScriptingCode = Get-Content -LiteralPath $uiScriptingSource -Raw
if ($uiScriptingCode -match '\.create\(0x1406023A0\s*,') {
	Write-Error ("Custom LUI scripts are hooked below the LUI lifecycle boundary. " +
		"That hook cannot distinguish normal initialization from the stock error-recovery VM.")
	exit 1
}

if ($uiScriptingCode -notmatch 'lui_cod_init_hook\.create\(0x140615090\s*,\s*lui_cod_init_stub\)') {
	Write-Error "Custom LUI scripts must be loaded once from the completed LUI_CoD_Init lifecycle."
	exit 1
}

if ($uiScriptingCode -notmatch 'if\s*\(error_recovery\)[\s\S]*?customScripts=skipped[\s\S]*?return;') {
	Write-Error "The stock error-recovery VM must not receive the custom UI script overlay."
	exit 1
}

if ($uiScriptingCode -notmatch 'selected_roots\.find\(logical_key\)') {
	Write-Error "Logical UI scripts must be deduplicated across search-path roots before execution."
	exit 1
}

Write-Host "UI script lifecycle validation passed."
