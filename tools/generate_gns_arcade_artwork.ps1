[CmdletBinding()]
param(
    [string]$GamePath = "D:\Steam\steamapps\common\Call of Duty - Infinite Warfare",
    [string]$OutputPath = "D:\iwz-mod\assets\gns_arcade\zonetool\iwz_gns_arcade\images"
)

$magick = (Get-Command magick.exe -ErrorAction Stop).Source
$dumpPath = Join-Path $GamePath "dump"
# Fade the black screen background to a true circle, but preserve the bright
# foreground logo and skulls so the outer skulls can extend past the vignette.
$radialAlpha = "min(1,max(0,1-((hypot(i-w/2,j-h/2)/(w/2)-0.82)/0.18)))"
$foregroundAlpha = "min(1,max(r,max(g,b))*3)"
$alphaExpression = "max($radialAlpha,$foregroundAlpha)"
$artwork = @(
    @{ Map = "cp_zmb"; Source = "ghosts_skulls_screen_06a_c"; Target = "iwz_gns_arcade_spaceland_art" },
    @{ Map = "cp_rave"; Source = "ghosts_skulls2_screen_06a_c"; Target = "iwz_gns_arcade_rave_art" },
    @{ Map = "cp_disco"; Source = "ghosts_skulls3_screen_06a_c"; Target = "iwz_gns_arcade_shaolin_art" },
    @{ Map = "cp_town"; Source = "skullhop_screen_06a_c"; Target = "iwz_gns_arcade_attack_art" },
    @{ Map = "cp_final"; Source = "skullbreaker_screen_06a_c"; Target = "iwz_gns_arcade_beast_art" }
)

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

foreach ($entry in $artwork)
{
    $source = Join-Path $dumpPath "$($entry.Map)\images\$($entry.Source).png"
    $target = Join-Path $OutputPath "$($entry.Target).tga"

    if (-not (Test-Path -LiteralPath $source))
    {
        throw "Missing decoded artwork: $source"
    }

    & $magick $source -alpha set -channel A -fx $alphaExpression $target
    if ($LASTEXITCODE -ne 0)
    {
        throw "ImageMagick failed while processing $source"
    }

    Write-Host "Generated $target"
}
