-- Fetch matching headers and DLLs before any project starts compiling. Runtime
-- DLLs go into cdata so release data artifacts include the optional decoder.
if _ACTION == "vs2022" then
    local script = path.join(_MAIN_SCRIPT_DIR, "tools/setup_video_decoder.ps1")
    local result = os.execute('powershell -NoProfile -ExecutionPolicy Bypass -File "' .. script .. '"')
    if result ~= 0 and result ~= true then
        error("Unable to prepare the video decoder")
    end
end

ffmpeg = {}
function ffmpeg.import()
    includedirs {path.join(dependencies.basePath, "ffmpeg/include")}
end
function ffmpeg.project()
end
table.insert(dependencies, ffmpeg)
