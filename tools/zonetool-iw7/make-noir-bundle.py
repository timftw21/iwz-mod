"""Generate Noir's zombie bundle manifest from the installed game's asset inventory."""
import argparse
import csv
import json
import re
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("game", type=Path)
    args = parser.parse_args()
    game = args.game.resolve()
    donor = game / "dump/cp_zmb"
    with (donor / "cp_zmb.csv").open(encoding="utf-8-sig", newline="") as file:
        donor_assets = [row[:2] for row in csv.reader(file) if len(row) >= 2]
    with (game / "dump/common_cp/common_cp.csv").open(encoding="utf-8-sig", newline="") as file:
        shared_assets = [row[:2] for row in csv.reader(file) if len(row) >= 2]
    clips = {name.lower(): name for kind, name in shared_assets + donor_assets if kind == "xanim"}
    animation_class = json.loads((donor / "animclass/zombie_asm_animclass.json").read_text())
    entries = {entry["animation"].lower() for state in animation_class["stateMachine"]["states"]
               for entry in state["entries"]}
    if missing := entries - clips.keys():
        raise RuntimeError(f"Animation class requires clips missing from donors: {sorted(missing)}")
    # Preserve the original tree. Include its available leaf clips; the stock tree also
    # lists optional DLC clips that Spaceland itself does not ship or use.
    tree = (donor / "animtrees/zombie.atr").read_text()
    leaves = {match.lower() for match in re.findall(r"^\s*([A-Za-z0-9_]+)\s*(?://[^\n]*)?$", tree, re.M)}
    selected = entries | (leaves & clips.keys())
    shared_references = set()
    for zone in ("mp_prime", "common_mp", "techsets_common_core_mp", "techsets_common_mp", "techsets_mp_prime"):
        with (game / f"dump/{zone}/{zone}.csv").open(encoding="utf-8-sig", newline="") as file:
            for row in csv.reader(file):
                if len(row) >= 2:
                    name = row[1] or (row[2] if len(row) > 2 else "")
                    if name:
                        shared_references.add((row[0], name))
    reference_path = game / "zone_source/iwz_noir_shared.csv"
    with reference_path.open("w", encoding="utf-8", newline="") as file:
        csv.writer(file, lineterminator="\n").writerows(sorted(shared_references))
    required_zones = ("techsets_common", "techsets_common_core_mp", "techsets_common_mp", "techsets_common_cp",
                      "techsets_global_core_mp", "techsets_global_cp", "techsets_cp_zmb",
                      "common_cp", "cp_zmb")
    rows = [["require", zone] for zone in required_zones]
    rows += [["ignore", "iwz_noir_shared"],
            ["addpath", "dump/cp_zmb"], ["addpath", "dump/common_cp"],
            ["animclass", "zombie_asm_animclass"], ["behaviortree", "zombie"],
            ["xmodel", "zombie_male_outfit_1"]]
    # The engine enumerates all network tables. A distinct asset extends the map's
    # class list without competing with its already-loaded ncs_acl_level asset.
    network_table = {"stringType": 17, "sourceType": 0, "stringList": ["zombie_asm_animclass"]}
    table_path = game / "zonetool/iwz_noir_zombies/netconststrings/ncs_acl_iwz_noir.json"
    table_path.parent.mkdir(parents=True, exist_ok=True)
    table_path.write_text(json.dumps(network_table, indent=2), encoding="utf-8")
    rows.append(["netconststrings", "ncs_acl_iwz_noir"])
    # Scriptable characters attach limbs/hair during native spawnagent. The root
    # model alone is not sufficient: these models need network indices as well.
    models = json.loads(Path(__file__).with_name("noir-models.json").read_text())
    gameplay_models = ["zmb_perk_up_n_atoms", "zmb_perk_up_n_atoms_on",
                       "zmb_magic_wheel", "zmb_magic_wheel_on", "zmb_magic_wheel_spinner",
                       "zmb_core_wood_board", "icbm_electricpanel_switch_02"]
    models = sorted(set(models + gameplay_models))
    rows += [["xmodel", model] for model in gameplay_models]
    available_models = set()
    for zone in ("cp_zmb", "common_cp"):
        with (game / f"dump/{zone}/{zone}.csv").open(encoding="utf-8-sig", newline="") as file:
            for row in csv.reader(file):
                if len(row) >= 2 and row[0] == "xmodel":
                    available_models.add(row[1] or (row[2] if len(row) > 2 else ""))
    if missing := set(models) - available_models:
        raise RuntimeError(f"Missing zombie model dependencies: {sorted(missing)}")
    model_table = {"stringType": 0, "sourceType": 0, "stringList": models}
    table_path.with_name("ncs_mdl_iwz_noir.json").write_text(json.dumps(model_table, indent=2), encoding="utf-8")
    rows.append(["netconststrings", "ncs_mdl_iwz_noir"])
    rows += [["xanim", clips[name]] for name in sorted(selected)]
    effects = {
        "vfx/iw7/_requests/coop/vfx_zmb_blackhole_death",
        "vfx/iw7/_requests/coop/vfx_clown_exp",
        "vfx/iw7/core/zombie/vfx_clown_exp_big",
        "vfx/iw7/_requests/coop/zmb_fullbody_gib",
    }
    effects.update("vfx/iw7/core/zombie/vfx_zombie_" + suffix for suffix in (
        "dism_arm_r", "dism_arm_l", "impact_torso_l", "dism_head", "impact_torso_r",
        "impact_arm_l", "impact_arm_r", "impact_limb_r", "impact_limb_l", "impact_head"))
    available = {tuple(row) for row in donor_assets}
    for effect in sorted(effects):
        if ("vfx", effect) not in available:
            raise RuntimeError(f"Missing required zombie effect: {effect}")
        rows.append(["vfx", effect])
    # Stock compiled scripts are loaded on demand by the VM. Loading these assets
    # does not run Spaceland's map script or install its world/collision/navigation.
    rows += [row for row in donor_assets if row[0] == "scriptfile"]
    output = game / "zone_source/iwz_noir_zombies.csv"
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8", newline="") as file:
        csv.writer(file, lineterminator="\n").writerows(rows)
    print(f"Wrote {output}: {len(selected)} clips, {len(effects)} effects, "
          f"{sum(row[0] == 'scriptfile' for row in rows)} stock script assets")


if __name__ == "__main__":
    main()
