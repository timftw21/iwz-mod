"""Install the IW7 stock zombie asset handlers into a local x64-zt checkout."""
import argparse
from pathlib import Path
import shutil


def insert_before(path, anchor, addition):
    content = path.read_text(encoding="utf-8")
    if addition in content:
        return
    if content.count(anchor) != 1:
        raise RuntimeError(f"Expected one integration point in {path}: {anchor!r}")
    path.write_text(content.replace(anchor, addition + anchor), encoding="utf-8")


def replace_once(path, old, new):
    content = path.read_text(encoding="utf-8")
    if new in content:
        return
    if content.count(old) != 1:
        raise RuntimeError(f"Expected one replacement point in {path}")
    path.write_text(content.replace(old, new), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkout", type=Path)
    args = parser.parse_args()
    root = args.checkout.resolve()
    iw7 = root / "src/zonetool/zonetool/iw7"
    if not (iw7 / "zone.cpp").is_file():
        parser.error("Expected an x64-zt checkout with the IW7 zone linker")
    for extension in ("cpp", "hpp"):
        source = Path(__file__).with_name(f"zombie_assets.{extension}")
        destination = iw7 / f"assets/zombie_assets.{extension}"
        if not destination.exists() or source.read_bytes() != destination.read_bytes():
            shutil.copyfile(source, destination)
    for filename in ("zone.cpp", "zonetool.cpp"):
        insert_before(iw7 / filename, '#include "zonetool.hpp"',
                      '#include "assets/zombie_assets.hpp"\n')
    insert_before(iw7 / "zone.cpp", "\t\t\tADD_ASSET(ASSET_TYPE_DDL, ddl);",
                  "\t\t\tADD_ASSET(ASSET_TYPE_ANIMCLASS, iwz_anim_class);\n"
                  "\t\t\tADD_ASSET(ASSET_TYPE_BEHAVIOR_TREE, iwz_behavior_tree);\n")
    insert_before(iw7 / "zonetool.cpp", "\t\t\tDUMP_ASSET(ASSET_TYPE_DDL, ddl, DDLFile);",
                  "\t\t\tDUMP_ASSET(ASSET_TYPE_ANIMCLASS, iwz_anim_class, AnimationClass);\n"
                  "\t\t\tDUMP_ASSET(ASSET_TYPE_BEHAVIOR_TREE, iwz_behavior_tree, BehaviorTree);\n")
    replace_once(iw7 / "zonetool.cpp", "auto ptr = std::make_shared<zone_buffer>();",
                 'auto capacity = MAX_ZONE_SIZE;\n'
                 '\t\tif (const auto* setting = std::getenv("ZONETOOL_ZONE_BUFFER_MB"))\n'
                 '\t\t{\n'
                 '\t\t\tconst auto mb = std::stoul(setting);\n'
                 '\t\t\tif (mb < 16 || mb > 2048) throw std::runtime_error("Zone buffer must be 16..2048 MiB");\n'
                 '\t\t\tcapacity = mb * 1024ull * 1024ull;\n'
                 '\t\t}\n'
                 '\t\tZONETOOL_INFO("Zone serialization buffer: %llu MiB", capacity / (1024ull * 1024ull));\n'
                 '\t\tauto ptr = std::make_shared<zone_buffer>(capacity);')
    replace_once(root / "src/zonetool/zonetool/shared/interfaces/zonebuffer.cpp",
                 'ZONETOOL_ERROR("No more space left in zone buffer."); // this->realloc(((size * count) + m_pos) - m_len);\n\t\t\treturn;',
                 'throw std::runtime_error("No more space left in zone buffer");')
    # Sound rules may omit either alias. Preserve nulls and relocate present
    # strings; upstream wrote both unconditionally and left donor pointers behind.
    replace_once(iw7 / "assets/physics_sfx_event.cpp",
                 '\t\t\tbuf->write_str(data->u.soundRule.hitSoundAlias);\n'
                 '\t\t\tbuf->write_str(data->u.soundRule.scrapeSoundAlias);',
                 '\t\t\tif (data->u.soundRule.hitSoundAlias)\n'
                 '\t\t\t\tdest->u.soundRule.hitSoundAlias = buf->write_str(data->u.soundRule.hitSoundAlias);\n'
                 '\t\t\tif (data->u.soundRule.scrapeSoundAlias)\n'
                 '\t\t\t\tdest->u.soundRule.scrapeSoundAlias = buf->write_str(data->u.soundRule.scrapeSoundAlias);')
    # Match the existing vertex-shader donor path: pixel shaders also retain their
    # bytecode in the renderer-free tool. Reject missing/default donor assets.
    for stage in ("pixel", "hull", "domain"):
        shader = iw7 / f"assets/{stage}shader.cpp"
        content = shader.read_text(encoding="utf-8")
        old = f'\t\t\tZONETOOL_FATAL("{stage}shader \\"%s\\" not found.", name.data());'
        if "db_find_x_asset_header_safe" not in content:
            if content.count(old) != 1:
                raise RuntimeError(f"Expected {stage} shader missing-file branch")
            asset_type = f"ASSET_TYPE_{stage.upper()}SHADER"
            replacement = (f'\t\t\tthis->asset_ = db_find_x_asset_header_safe({asset_type}, name).{stage}Shader;\n'
                           f'\t\t\tif (!this->asset_ || DB_IsXAssetDefault({asset_type}, name.data()))\n'
                           '\t\t\t{\n\t' + old + '\n\t\t\t}')
            shader.write_text(content.replace(old, replacement), encoding="utf-8")
    project = root / "build/zonetool.vcxproj"
    if project.is_file():
        # Keep an existing generated project usable without regenerating its dependencies.
        for item, extension in (("ClCompile", "cpp"), ("ClInclude", "hpp")):
            anchor = f'    <{item} Include="..\\src\\zonetool\\zonetool\\iw7\\assets\\aipaths.{extension}"'
            insert_before(project, anchor,
                          f'    <{item} Include="..\\src\\zonetool\\zonetool\\iw7\\assets\\zombie_assets.{extension}" />\n')
    print(f"Installed IW7 animation class and behavior tree handlers in {root}")


if __name__ == "__main__":
    main()
