"""Validate PH1P35 placed Slice capacity against its actual device database.

This is an independent capacity/location check, not a replacement for TD DRC,
timing, routing, clock, IO-bank, or PLB-control checks. It does not edit any TD DB.
"""
import argparse
import csv
import hashlib
import io
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

L = 'PH1P_PHY_LSLICE'
M = 'PH1P_PHY_MSLICE'
MODELS = (L, M)
EXPECTED_TILE_COUNTS = {3: 1638, 31: 1014}
MOSAIC_NAMES = {3: 'Plb', 31: 'Pmb'}
SLOTS_PER_TILE = 8


class EvidenceError(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise EvidenceError(message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def read_tsv(path, required):
    with Path(path).open(encoding='utf-8-sig', newline='') as fp:
        reader = csv.DictReader(fp, delimiter='\t')
        require(reader.fieldnames and set(required) <= set(reader.fieldnames),
                f'Missing TSV columns: {required}')
        return list(reader)


def parse_chip(text):
    require('f0:ph1_35p ' in text, 'This validator supports only ph1_35p')
    sectors = re.findall(r'# START of ::DeviceSector Objects.*?\n(.*?)# END   of ::DeviceSector Objects', text, re.S)
    require(len(sectors) == 2, 'Expected two device sectors')
    tiles, counts = {}, Counter()
    for secno, sector in enumerate(sectors):
        head = [int(x) for x in re.findall(r'0:(-?\d+)', sector.splitlines()[0])]
        require(len(head) == 13 and head[0] == secno and head[4] == secno * 40,
                'Unexpected PH1P35 sector coordinates')
        require(head[-2:] == [222, 3], 'Unexpected mosaic class range')
        blocks = list(re.finditer(r'# START of ::DeviceMosaic Objects.*?\n(.*?)# END   of ::DeviceMosaic Objects', sector, re.S))
        require(len(blocks) == 222, 'Missing device mosaic classes')
        for kind, match in enumerate(blocks, 3):
            if kind not in MOSAIC_NAMES:
                continue
            block = match.group(1)
            declared = int(re.findall(r'0:(-?\d+)', block.splitlines()[0])[0])
            loc = re.search(r'# START of ::DeviceLocation Objects.*?\n(.*?)\n', block, re.S)
            require(loc is not None, 'Missing device location table')
            vals = [int(x) for x in re.findall(r'0:(-?\d+)', loc[1])]
            require(vals[:2] == [1, declared] and len(vals) == 3 + 4 * declared and vals[-1] == 0,
                    'Malformed device location table')
            for idx in range(2, 2 + 4 * declared, 4):
                col, row, col2, row2 = vals[idx:idx + 4]
                require((col, row) == (col2, row2), 'Expected single logic tile per location')
                key = (col, row + head[4])
                require(key not in tiles, 'Overlapping logic tiles in device dump')
                tiles[key] = dict(col=key[0], row=key[1], sector=secno, mosaic_type=kind,
                                  tile_name=MOSAIC_NAMES[kind])
                counts[kind] += 1
    require(dict(counts) == EXPECTED_TILE_COUNTS, f'Unexpected physical tile counts: {dict(counts)}')
    return tiles


def prove_named_routing_tiles(text, tiles):
    ssms = {}
    for line in re.findall(r'# START of ::SSM Objects.*?\n(.*?)\n', text, re.S):
        match = re.search(r'0:([A-Za-z_]\w*)\s+0:(\d+)\s+0:(\d+)', line)
        if match:
            key = int(match[2])
            require(key not in ssms, 'Duplicate SSM id')
            ssms[key] = match[1]
    require(ssms, 'No named SSMs in device routing dump')
    named = {}
    for line in re.findall(r'# START of ::Ulink Objects.*?\n(.*?)\n', text, re.S):
        vals = [int(x) for x in re.findall(r'0:(-?\d+)', line)]
        require(len(vals) >= 4, 'Malformed routing Ulink')
        col, row, _, count = vals[:4]
        require(count >= 0 and len(vals) >= 4 + 2 * count, 'Truncated routing Ulink')
        for idx in range(count):
            kind, ssm_id = vals[4 + 2 * idx:6 + 2 * idx]
            if kind not in MOSAIC_NAMES:
                continue
            key = (col, row)
            require(key not in named, 'Duplicate named logic tile')
            require(ssms.get(ssm_id) == MOSAIC_NAMES[kind],
                    f'Mosaic {kind} at {key} has incompatible named SSM {ssms.get(ssm_id)}')
            require(key in tiles and tiles[key]['mosaic_type'] == kind,
                    f'Routing/chip tile mismatch at {key}')
            named[key] = dict(ssm_id=ssm_id, ssm_name=ssms[ssm_id])
    require(set(named) == set(tiles), 'Incomplete named routing/device tile correspondence')
    return named


def prove_eight_slots(tile_log, tiles):
    evidence = []
    covered = set()
    for location, block in re.findall(r'TILE_QUERY_BEGIN (\S+)\n(.*?)TILE_QUERY_END', tile_log, re.S):
        require('TILE_QUERY_STATUS=0' in block, f'TD tile query failed: {location}')
        match = re.fullmatch(r'x(\d+)y(\d+)', location)
        require(match is not None, 'Bad TD tile query coordinate')
        key = (int(match[1]), int(match[2]))
        require(key in tiles, f'TD query is not a logic tile: {key}')
        slots = re.findall(r'^RUN-1001 : Slot\[\d+\] x(\d+)y(\d+)z(\d+) type=(\d+)', block, re.M)
        require(len(slots) == 8, f'{key}: expected exactly 8 physical Slice slots')
        require({int(z) for _, _, z, _ in slots} == set(range(8)), f'{key}: unexpected offsets')
        require(all((int(x), int(y)) == key for x, y, _, _ in slots), 'Tile report coordinate mismatch')
        kind = tiles[key]['mosaic_type']
        slot_type = 158 if kind == 3 else 157
        require({int(t) for _, _, _, t in slots} == {slot_type}, 'Unexpected physical slot type')
        covered.add((kind, tiles[key]['sector']))
        evidence.append(dict(col=key[0], row=key[1], mosaic_type=kind, slot_type=slot_type, slots=8))
    require(covered == {(3, 0), (3, 1), (31, 0), (31, 1)},
            'Need eight-slot evidence for both tile classes in both device sectors')
    return evidence


def prove_model_compatibility(datasheet_text):
    normalized = re.sub(r'\s+', '', datasheet_text)
    for expected in ('PLB包括RSB', 'PMB包括RSB和PMU', 'PMU除能够实现所有的PFU功能外', '64*8', '32*16'):
        require(expected in normalized, f'Missing explicit DS1300 compatibility evidence: {expected}')
    return {'Plb': [L], 'Pmb': [L, M]}


def prove_resource_totals(resource_text, tiles):
    rows = list(csv.DictReader(io.StringIO(resource_text)))
    row = next((r for r in rows if r.get('Device') == 'PH1P35MDG324'), None)
    require(row is not None, 'Missing PH1P35MDG324 official resource totals')
    total_slots = len(tiles) * SLOTS_PER_TILE
    memory_slots = sum(t['tile_name'] == 'Pmb' for t in tiles.values()) * SLOTS_PER_TILE
    require(int(row['LUTs']) == total_slots == 21216, 'TD resource LUT total disagrees with tile/slot census')
    require(int(row['DFFs']) == 2 * total_slots, 'TD resource DFF total disagrees with Slice census')
    require(int(row['DRAMs(Kbits)']) * 1024 == memory_slots * 64,
            'TD distributed-RAM total disagrees with memory-capable Slice census')
    return dict(official_luts=int(row['LUTs']), official_dffs=int(row['DFFs']),
                official_distributed_ram_kbits=int(row['DRAMs(Kbits)']),
                slots_from_named_device_tiles=total_slots,
                memory_slots_from_named_device_tiles=memory_slots)


def parse_expected(rows, log):
    match = re.search(r'EXPECTED_SLICE_COUNTS L=(\d+) M=(\d+)', log)
    require(match is not None and 'READONLY_EXPECTED_SLICE_EXPORT_DONE' in log,
            'Independent netlist enumeration did not complete')
    wanted_counts = {L: int(match[1]), M: int(match[2])}
    require(sum(wanted_counts.values()) > 0, 'Empty expected netlist')
    expected = {}
    for row in rows:
        name, model = row.get('cell'), row.get('ref_name')
        require(name and model in MODELS, 'Invalid independent expected Slice entry')
        require(name not in expected, 'Duplicate independent Slice name')
        expected[name] = model
    require(dict(Counter(expected.values())) == {k: v for k, v in wanted_counts.items() if v},
            'Independent expected cells disagree with TD count log')
    return expected


def validate_placement(rows, tiles, expected, compatibility):
    errors = []
    counts = Counter()
    seen = set()
    occupied = {}
    joins = []
    for row in rows:
        name, model = row.get('cell'), row.get('ref_name')
        if model not in MODELS:
            continue
        if not name or name in seen:
            errors.append(dict(code='DUPLICATE_CELL_NAME', cell=name))
            continue
        seen.add(name)
        if expected.get(name) != model:
            errors.append(dict(code='UNEXPECTED_CELL_OR_MODEL', cell=name, model=model))
        if row.get('is_placed') != '1':
            errors.append(dict(code='UNPLACED', cell=name))
            continue
        try:
            col, rr, offset = (int(row[k]) for k in ('col', 'row', 'offset'))
        except (ValueError, TypeError, KeyError):
            errors.append(dict(code='BAD_COORDINATE', cell=name))
            continue
        key = (col, rr)
        if key not in tiles or not 0 <= offset < SLOTS_PER_TILE:
            errors.append(dict(code='INVALID_SLOT', cell=name, location=[col, rr, offset]))
            continue
        tile = tiles[key]
        if model not in compatibility[tile['tile_name']]:
            errors.append(dict(code='INCOMPATIBLE_SLOT', cell=name, model=model,
                               tile_name=tile['tile_name'], location=[col, rr, offset]))
            continue
        position = (col, rr, offset)
        if position in occupied:
            errors.append(dict(code='DUPLICATE_SLOT', cell=name, other=occupied[position], location=list(position)))
            continue
        occupied[position] = name
        counts[f"{model}_in_{tile['tile_name']}"] += 1
        joins.append(dict(**row, tile_name=tile['tile_name'], mosaic_type=tile['mosaic_type']))
    missing = set(expected) - seen
    extra = seen - set(expected)
    if missing:
        errors.append(dict(code='MISSING_CELLS', count=len(missing), examples=sorted(missing)[:8]))
    if extra:
        errors.append(dict(code='EXTRA_CELLS', count=len(extra), examples=sorted(extra)[:8]))
    capacities = {name: sum(t['tile_name'] == name for t in tiles.values()) * 8 for name in ('Plb', 'Pmb')}
    used = {name: sum(counts[f'{m}_in_{name}'] for m in MODELS) for name in capacities}
    for name in used:
        if used[name] > capacities[name]:
            errors.append(dict(code='CAPACITY_EXCEEDED', tile_name=name))
    return dict(passed=not errors, errors=errors, expected_slices=len(expected),
                placed_compatible_unique_slices=len(occupied), expected_model_counts=dict(Counter(expected.values())),
                placed_model_by_physical_tile=dict(counts), capacities=capacities, used=used,
                free={k: capacities[k] - used[k] for k in capacities},
                total_utilization_percent=100 * len(occupied) / sum(capacities.values())), joins


def load_evidence(chip, routing, tile_report, datasheet, expected_cells, expected_log, resource_report):
    tiles = parse_chip(Path(chip).read_text(encoding='utf-8-sig'))
    named = prove_named_routing_tiles(Path(routing).read_text(encoding='utf-8-sig'), tiles)
    slots = prove_eight_slots(Path(tile_report).read_text(encoding='utf-8-sig'), tiles)
    compatibility = prove_model_compatibility(Path(datasheet).read_text(encoding='utf-8-sig'))
    expected = parse_expected(read_tsv(expected_cells, ('cell', 'ref_name')),
                              Path(expected_log).read_text(encoding='utf-8-sig'))
    resource_proof = prove_resource_totals(Path(resource_report).read_text(encoding='utf-8-sig'), tiles)
    for key, values in named.items():
        tiles[key].update(values)
    return tiles, slots, compatibility, expected, resource_proof


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for key in ('chip', 'routing', 'tile_report', 'datasheet', 'expected_cells', 'expected_log', 'resource_report', 'placements', 'out'):
        p.add_argument('--' + key.replace('_', '-'), required=True)
    args = p.parse_args()
    out = Path(args.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    try:
        tiles, slots, compatibility, expected, resource_proof = load_evidence(args.chip, args.routing, args.tile_report,
            args.datasheet, args.expected_cells, args.expected_log, args.resource_report)
        rows = read_tsv(args.placements, ('cell', 'ref_name', 'is_placed', 'col', 'row', 'offset'))
        result, joins = validate_placement(rows, tiles, expected, compatibility)
        result['named_logic_tile_counts'] = dict(Counter(t['tile_name'] for t in tiles.values()))
        result['representative_td_slot_evidence'] = slots
        result['allowed_models'] = compatibility
        result['official_resource_cross_check'] = resource_proof
        result['scope'] = 'Only physical Slice capacity, complete cell correspondence, placement and model/slot compatibility. TD IO/clock/routing/DRC/timing remain separate mandatory checks.'
        for name, data in [('named_logic_tiles.tsv', list(tiles.values())), ('validated_placed_slices.tsv', joins)]:
            if data:
                with (out / name).open('w', encoding='utf-8', newline='') as fp:
                    wr = csv.DictWriter(fp, fieldnames=list(data[0]), delimiter='\t')
                    wr.writeheader()
                    wr.writerows(data)
    except (EvidenceError, OSError, ValueError, IndexError) as err:
        result = dict(passed=False, errors=[dict(code='EVIDENCE_FAILURE', reason=str(err))])
    inputs = {k: v for k, v in vars(args).items() if k != 'out'}
    result['inputs'] = {k: dict(path=str(Path(v).resolve()), sha256=sha(v) if Path(v).is_file() else None)
                        for k, v in inputs.items()}
    result['validator_sha256'] = sha(__file__)
    (out / 'physical_capacity_validation.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
