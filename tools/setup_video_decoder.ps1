$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$version = 'ffmpeg-n8.1.3-2-g45e8e0a3ff-win64-lgpl-shared-8.1'
$sha256 = 'CE2926E08718B9B4F57B38E735B4695AB32F0E17DB9E091DDA90A8A39F79406D'
$url = "https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2026-09-27-13-04/$version.zip"
$runtime = Join-Path $root 'data/cdata/video'
$headers = Join-Path $root 'deps/ffmpeg/include'
$dlls = @('avutil-60.dll', 'swresample-6.dll', 'avcodec-62.dll', 'avformat-62.dll', 'swscale-9.dll')
$required = @((Join-Path $headers 'libavformat/avformat.h'), (Join-Path $runtime 'FFmpeg-LICENSE.txt'))
$required += $dlls | ForEach-Object { Join-Path $runtime $_ }
$marker = Join-Path $runtime '.decoder-version'
if ((Test-Path $marker) -and (Get-Content $marker -Raw).Trim() -eq $sha256 -and
    @($required | Where-Object { -not (Test-Path $_) }).Count -eq 0) {
    exit 0
}

$cache = Join-Path $root '.tmp/ffmpeg-download'
New-Item -ItemType Directory -Force $cache, $runtime, $headers | Out-Null
$zip = Join-Path $cache 'ffmpeg.zip'
if (-not (Test-Path $zip) -or (Get-FileHash $zip -Algorithm SHA256).Hash -ne $sha256) {
    Write-Host "Downloading the pinned LGPL video decoder ($version)..."
    Invoke-WebRequest $url -OutFile $zip -UseBasicParsing
}
if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $sha256) {
    throw 'Video decoder download failed SHA-256 verification.'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zip)
try {
    foreach ($entry in $archive.Entries) {
        $relative = $entry.FullName.Substring($version.Length + 1)
        $destination = $null
        if ($relative -match '^include/(libavcodec|libavformat|libavutil|libswscale)/[a-zA-Z0-9_]+\.h$') {
            $destination = Join-Path $headers $relative.Substring(8)
        } elseif ($relative.StartsWith('bin/') -and $dlls -contains $relative.Substring(4)) {
            $destination = Join-Path $runtime $relative.Substring(4)
        } elseif ($relative -eq 'LICENSE.txt') {
            $destination = Join-Path $runtime 'FFmpeg-LICENSE.txt'
        }
        if ($destination) {
            New-Item -ItemType Directory -Force (Split-Path $destination -Parent) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destination, $true)
        }
    }
} finally {
    $archive.Dispose()
}
if (@($required | Where-Object { -not (Test-Path $_) }).Count) {
    throw 'Video decoder archive is missing required files.'
}
Set-Content $marker $sha256
Write-Host 'Video decoder headers and redistributable runtime are ready.'
