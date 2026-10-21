// Offline authoring: node design/town-500m/phase2/terrain-authoring.cjs [--check]
// Reuses the Concept B convex split/OBJ/ConcavePolygonShape3D pattern, without its 200m data.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '../../..');
const sourceDir = path.resolve(__dirname, '..');
const outputDir = path.join(root, 'Scene/World/Town500m/Terrain');
const read = name => JSON.parse(fs.readFileSync(path.join(sourceDir, name)));
const terrain = read('terrain-contract.json');
const layout = read('layout.json');
const catalogue = read('building-catalogue.json');
const EPS = 1e-8;
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const lerp = (a, b, t) => a + (b - a) * t;
const sub = (a, b) => [a[0] - b[0], a[1] - b[1]];
const cross = (a, b) => a[0] * b[1] - a[1] * b[0];
const signedArea = poly => poly.reduce((s, p, i) => s + cross(p, poly[(i + 1) % poly.length]), 0) / 2;
const area = poly => Math.abs(signedArea(poly));
const bounds = poly => [Math.min(...poly.map(p => p[0])), Math.min(...poly.map(p => p[1])), Math.max(...poly.map(p => p[0])), Math.max(...poly.map(p => p[1]))];
const overlap = (a, b) => a[0] <= b[2] && a[2] >= b[0] && a[1] <= b[3] && a[3] >= b[1];
const center = poly => [poly.reduce((s, p) => s + p[0], 0) / poly.length, poly.reduce((s, p) => s + p[1], 0) / poly.length];
const pointKey = p => p.map(v => v.toFixed(7)).join(',');
const round = v => Number(v.toFixed(7));
const num = v => round(v).toString();
function rectangle(cx, cz, width, depth, yaw = 0) {
    const angle = yaw * Math.PI / 180, c = Math.cos(angle), s = Math.sin(angle);
    return [[-width / 2, -depth / 2], [width / 2, -depth / 2], [width / 2, depth / 2], [-width / 2, depth / 2]]
        .map(([x, z]) => [cx + c * x + s * z, cz - s * x + c * z]);
}
function projection(p, a, b) {
    const d = sub(b, a), length2 = d[0] ** 2 + d[1] ** 2;
    const t = clamp(((p[0] - a[0]) * d[0] + (p[1] - a[1]) * d[1]) / length2, 0, 1);
    const q = [lerp(a[0], b[0], t), lerp(a[1], b[1], t)];
    return {t, distance: Math.hypot(...sub(p, q))};
}
function inside(p, poly) {
    let result = false;
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        const a = poly[i], b = poly[j];
        if (((a[1] > p[1]) !== (b[1] > p[1])) && p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0]) result = !result;
    }
    return result;
}
function clean(poly) {
    const result = [];
    for (const p of poly) if (!result.length || Math.hypot(...sub(p, result[result.length - 1])) > EPS) result.push(p);
    if (result.length > 1 && Math.hypot(...sub(result[0], result[result.length - 1])) < EPS) result.pop();
    return result;
}
function splitPolygon(poly, a, b) {
    const positive = [], negative = [], direction = sub(b, a);
    for (let i = 0; i < poly.length; i++) {
        const p = poly[i], q = poly[(i + 1) % poly.length];
        const dp = cross(direction, sub(p, a)), dq = cross(direction, sub(q, a));
        if (dp >= -EPS) positive.push(p);
        if (dp <= EPS) negative.push(p);
        if ((dp > EPS && dq < -EPS) || (dp < -EPS && dq > EPS)) {
            const t = dp / (dp - dq), v = [lerp(p[0], q[0], t), lerp(p[1], q[1], t)];
            positive.push(v); negative.push(v);
        }
    }
    return [clean(positive), clean(negative)].filter(p => p.length >= 3 && area(p) > EPS);
}
function partitionConvex(poly, clip) {
    let remaining = poly, outside = [];
    for (let i = 0; i < clip.length && remaining.length >= 3; i++) {
        const a = clip[i], b = clip[(i + 1) % clip.length];
        const pieces = splitPolygon(remaining, a, b);
        remaining = [];
        for (const p of pieces) {
            if (cross(sub(b, a), sub(center(p), a)) >= -EPS) remaining = p;
            else outside.push(p);
        }
    }
    return [...outside, ...(remaining.length >= 3 ? [remaining] : [])];
}
const wetPolygons = [terrain.hydrology.river.actual_water_polygon_xz_m, terrain.hydrology.lake.actual_water_polygon_xz_m];
const wet = p => wetPolygons.some(poly => inside(p, poly));
const bankEdges = wetPolygons.flatMap(poly => poly.map((p, i) => [p, poly[(i + 1) % poly.length]]))
    .filter(([a, b]) => !(Math.abs(a[0]) === 250 && a[0] === b[0]) && !(Math.abs(a[1]) === 250 && a[1] === b[1]));
const bankDistance = p => Math.min(...bankEdges.map(([a, b]) => projection(p, a, b).distance));
const bankReservations = bankEdges.map(([a, b]) => {
    const d = sub(b, a);
    return {center: center([a, b]), size: [Math.hypot(...d) + 12, 12], yaw: -Math.atan2(d[1], d[0]) * 180 / Math.PI};
});
const pads = [
    ...catalogue.structures.map(s => ({id: s.id, center: s.position_xz_m, size: s.footprint_m.map(v => v + 2 * s.pad_intent.flat_extension_m), yaw: s.yaw_deg, y: s.pad_intent.surface_y_m})),
    ...terrain.pads.map(p => ({id: p.id, center: p.center_xz_m, size: p.size_m, yaw: p.yaw_deg || 0, y: p.surface_y_m})),
    {id: 'DOCK_SHORE', center: terrain.dock.gangway_from_xz_m, size: terrain.dock.shore_landing_size_m, yaw: 0, y: terrain.dock.deck_surface_y_m},
    {id: 'GANGWAY_DRY_APPROACH', center: center([terrain.dock.gangway_from_xz_m, terrain.dock.gangway_to_xz_m]), size: [terrain.dock.gangway_clear_width_m + 0.8, terrain.dock.gangway_length_m], yaw: 0, y: terrain.dock.deck_surface_y_m},
    ...terrain.corrected_corridors.flatMap(r => r.points_xz_m.slice(1, -1).map((p, i) => ({id: `${r.id}_JOINT_${i + 1}`, center: p, size: [r.width_m, r.width_m], yaw: 0, y: r.surface_y_m[i + 1]})))
].map(p => ({...p, poly: rectangle(...p.center, ...p.size, p.yaw)}));
function padDistance(p, pad) {
    const angle = pad.yaw * Math.PI / 180, c = Math.cos(angle), s = Math.sin(angle), d = sub(p, pad.center);
    const x = c * d[0] - s * d[1], z = s * d[0] + c * d[1];
    return Math.hypot(Math.max(0, Math.abs(x) - pad.size[0] / 2), Math.max(0, Math.abs(z) - pad.size[1] / 2));
}
const doorAprons = catalogue.structures.filter(s => s.door_apron).map(s => ({
    id: `APRON_${s.id}`, points_xz_m: [s.door_threshold_xz_m, s.door_apron.to_xz_m],
    width_m: s.door_apron.width_m, surface_y_m: [s.pad_intent.surface_y_m, s.pad_intent.surface_y_m]
}));
const routes = [...terrain.corrected_corridors.map(r => ({...r, priority: r.surface === 'asphalt' ? 4 : r.surface === 'gravel' ? 3 : 2})), ...layout.access_paths.map(r => ({...r, priority: 1})), ...doorAprons.map(r => ({...r, priority: 1})), ...terrain.route_graph.edges.filter(e => e.kind === 'dry_path').map(e => ({...e, width_m: e.clear_width_m, priority: 0}))];
const segments = routes.flatMap(r => r.points_xz_m.slice(1).map((b, i) => {
    const a = r.points_xz_m[i], d = sub(b, a), length = Math.hypot(...d), n = [-d[1] / length, d[0] / length];
    if (length < EPS) return null;
    const width = r.width_m;
    const poly = [[a[0] + n[0] * width / 2, a[1] + n[1] * width / 2], [a[0] - n[0] * width / 2, a[1] - n[1] * width / 2], [b[0] - n[0] * width / 2, b[1] - n[1] * width / 2], [b[0] + n[0] * width / 2, b[1] + n[1] * width / 2]];
    if (signedArea(poly) < 0) poly.reverse();
    return {id: r.id, a, b, width, priority: r.priority, y0: r.surface_y_m[i], y1: r.surface_y_m[i + 1], poly};
}).filter(Boolean));
function convexIntersection(poly, clip) {
    let remaining = poly;
    for (let i = 0; i < clip.length && remaining.length >= 3; i++) {
        const a = clip[i], b = clip[(i + 1) % clip.length];
        remaining = splitPolygon(remaining, a, b).find(p => cross(sub(b, a), sub(center(p), a)) >= -EPS) || [];
    }
    return remaining;
}
for (const segment of segments) {
    const points = [{t: 0, y: segment.y0}, {t: 1, y: segment.y1}], sb = bounds(segment.poly);
    for (const adjacent of segments.filter(s => s !== segment && s.id === segment.id)) {
        const meetsStart = Math.hypot(...sub(adjacent.b, segment.a)) < 1e-6;
        const meetsEnd = Math.hypot(...sub(adjacent.a, segment.b)) < 1e-6;
        if (!meetsStart && !meetsEnd) continue;
        const cut = convexIntersection(segment.poly, adjacent.poly);
        if (cut.length < 3 || area(cut) < 1e-7) continue;
        const ts = cut.map(p => projection(p, segment.a, segment.b).t), y = meetsStart ? segment.y0 : segment.y1;
        points.push({t: Math.min(...ts), y}, {t: Math.max(...ts), y});
    }
    for (const pad of pads) {
        if (!overlap(sb, bounds(pad.poly))) continue;
        const cut = convexIntersection(segment.poly, pad.poly);
        if (cut.length < 3 || area(cut) < 1e-7) continue;
        const ts = cut.map(p => projection(p, segment.a, segment.b).t);
        points.push({t: Math.min(...ts), y: pad.y}, {t: Math.max(...ts), y: pad.y});
    }
    points.sort((a, b) => a.t - b.t);
    segment.profile = [];
    for (const p of points) {
        const prior = segment.profile[segment.profile.length - 1];
        if (prior && Math.abs(prior.t - p.t) < 1e-7) {assert(Math.abs(prior.y - p.y) < 1e-5, `Contradictory pad/road height ${segment.id}`); continue;}
        segment.profile.push(p);
    }
}
function segmentHeight(segment, t) {
    const points = segment.profile;
    for (let i = 1; i < points.length; i++) if (t <= points[i].t + 1e-8) return lerp(points[i - 1].y, points[i].y, clamp((t - points[i - 1].t) / (points[i].t - points[i - 1].t), 0, 1));
    return points[points.length - 1].y;
}
const core = layout.zones.find(z => z.id === 'town').polygon_xz_m;
function baseHeight(x, z) {
    const p = [x, z];
    let y = z > 100 && x < 100 ? 1.5 : x > 90 && z < -80 ? 3 : 2;
    const hills = terrain.terrain_anchors.filter(a => a.id.startsWith('HILL_'));
    for (const anchor of hills) {
        const distance = Math.hypot(...sub(p, anchor.xz_m));
        const radius = anchor.id === 'HILL_W' ? 155 : 115;
        y = Math.max(y, 2 + (anchor.y_m - 2) * Math.max(0, Math.cos(Math.min(1, distance / radius) * Math.PI / 2)) ** 2);
    }
    if (inside(p, core)) y = clamp(y, ...terrain.elevation_policy.core_surface_range_y_m);
    const distance = bankDistance(p);
    if (distance < 2) y = lerp(-0.35, 3, distance / 2);
    else {
        const reserveDistance = Math.min(...bankReservations.map(r => padDistance(p, r)));
        if (reserveDistance < 4) y = lerp(3, y, reserveDistance / 4);
    }
    return y;
}
function authoredHeight(x, z) {
    const p = [x, z];
    let y = baseHeight(x, z);
    let nearest = null, distance = Infinity;
    for (const pad of pads) {
        const d = padDistance(p, pad);
        if (d < distance) {distance = d; nearest = pad;}
    }
    if (distance <= 4) y = lerp(nearest.y, y, clamp(distance / 4, 0, 1));
    let road = null, roadDistance = Infinity, insideRoad = false;
    for (const segment of segments) {
        const sample = projection(p, segment.a, segment.b), d = Math.max(0, sample.distance - segment.width / 2);
        const inStrip = segment.poly.every((a, i) => {
            const edge = sub(segment.poly[(i + 1) % segment.poly.length], a);
            return cross(edge, sub(p, a)) / Math.hypot(...edge) >= -1e-5;
        });
        const score = sample.distance / segment.width;
        if (inStrip && (!insideRoad || segment.priority > road.segment.priority || (segment.priority === road.segment.priority && score < roadDistance))) {
            road = {segment, sample, distance: 0}; roadDistance = score; insideRoad = true;
        } else if (!insideRoad && d < 4 && (!road || score < roadDistance)) {
            road = {segment, sample, distance: d}; roadDistance = score;
        }
    }
    if (road) y = lerp(segmentHeight(road.segment, road.sample.t), y, clamp(road.distance / 4, 0, 1));
    if (distance < 1e-7) y = nearest.y;
    // Boundary cliffs follow bank/pad/shoulder shaping, so those blends cannot erase containment.
    const edgeDistance = Math.min(250 - Math.abs(x), 250 - Math.abs(z));
    if (edgeDistance < 2 && !insideRoad) {
        const reserveDistance = Math.min(...bankReservations.map(r => padDistance(p, r)));
        const lift = 3 + clamp(reserveDistance / 4, 0, 1);
        y += lift * clamp(1 - edgeDistance / 2, 0, 1);
        if (reserveDistance < 1e-5) y = Math.min(6, y);
    }
    return clamp(y, -0.35, 20);
}
function buildPolygons() {
    let cells = [];
    const xs = [...new Set([...Array.from({length: 51}, (_, i) => -250 + i * 10), -248, 248, ...terrain.terrain_anchors.map(a => a.xz_m[0])])].sort((a, b) => a - b);
    const zs = [...new Set([...Array.from({length: 51}, (_, i) => -250 + i * 10), -248, 248, ...terrain.terrain_anchors.map(a => a.xz_m[1])])].sort((a, b) => a - b);
    for (let i = 1; i < xs.length; i++) for (let j = 1; j < zs.length; j++) {
        const xSteps = zs[j] <= -248 || zs[j - 1] >= 248 ? Math.ceil(xs[i] - xs[i - 1]) : 1;
        const zSteps = xs[i] <= -248 || xs[i - 1] >= 248 ? Math.ceil(zs[j] - zs[j - 1]) : 1;
        for (let ix = 0; ix < xSteps; ix++) for (let iz = 0; iz < zSteps; iz++) {
            const x0 = lerp(xs[i - 1], xs[i], ix / xSteps), x1 = lerp(xs[i - 1], xs[i], (ix + 1) / xSteps);
            const z0 = lerp(zs[j - 1], zs[j], iz / zSteps), z1 = lerp(zs[j - 1], zs[j], (iz + 1) / zSteps);
            cells.push(rectangle((x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0));
        }
    }
    let wetRemoved = 0;
    // Concave wet polygons need no new triangulator: all boundary lines partition convex cells first.
    for (const water of wetPolygons) {
        const waterBounds = bounds(water), next = [];
        for (const cell of cells) {
            if (!overlap(bounds(cell), waterBounds)) {next.push(cell); continue;}
            let pieces = [cell];
            for (let i = 0; i < water.length; i++) pieces = pieces.flatMap(p => splitPolygon(p, water[i], water[(i + 1) % water.length]));
            for (const piece of pieces) {
                if (inside(center(piece), water)) wetRemoved += area(piece);
                else next.push(piece);
            }
        }
        cells = next;
    }
    const bankBands = bankEdges.flatMap(([a, b]) => {
        const d = sub(b, a), length = Math.hypot(...d), yaw = -Math.atan2(d[1], d[0]) * 180 / Math.PI;
        return [2, 6, 10].map(width => rectangle((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, length + width * 2, width * 2, yaw));
    });
    const profileCuts = segments.flatMap(s => s.profile.filter(p => p.t > 1e-7 && p.t < 1 - 1e-7).map(p => {
        const d = sub(s.b, s.a), b = [s.a[0] + d[0] * p.t, s.a[1] + d[1] * p.t], length = Math.hypot(...sub(b, s.a));
        return rectangle((s.a[0] + b[0]) / 2, (s.a[1] + b[1]) / 2, length, s.width + 8, -Math.atan2(d[1], d[0]) * 180 / Math.PI);
    }));
    const clips = [...pads.map(p => p.poly), ...segments.map(s => s.poly), ...profileCuts, ...bankBands];
    for (const clip of clips) {
        assert(signedArea(clip) > 0, `Convex partition requires positive XZ winding ${JSON.stringify(clip)}`);
        const clipBounds = bounds(clip);
        cells = cells.flatMap(cell => overlap(bounds(cell), clipBounds) ? partitionConvex(cell, clip) : [cell]);
    }
    // Pad corner transitions must not share a shoulder fan with the flat side.
    for (const pad of pads) {
        const blendBounds = bounds(rectangle(...pad.center, ...pad.size.map(size => size + 2 * terrain.elevation_policy.pad_blend_margin_m), pad.yaw));
        cells = cells.flatMap(cell => {
            if (!overlap(bounds(cell), blendBounds)) return [cell];
            let pieces = [cell];
            for (let i = 0; i < pad.poly.length; i++) pieces = pieces.flatMap(piece => splitPolygon(piece, pad.poly[i], pad.poly[(i + 1) % pad.poly.length]));
            return pieces;
        });
    }
    for (const zone of layout.zones.filter(z => !['river', 'lake'].includes(z.id))) {
        const poly = zone.polygon_xz_m, zoneBounds = bounds(poly);
        cells = cells.flatMap(cell => {
            if (!overlap(bounds(cell), zoneBounds)) return [cell];
            let pieces = [cell];
            for (let i = 0; i < poly.length; i++) pieces = pieces.flatMap(p => splitPolygon(p, poly[i], poly[(i + 1) % poly.length]));
            return pieces;
        });
    }
    return {cells: cells.filter(p => area(p) > 1e-8), wetRemoved};
}
// Add all vertices that lie on another polygon's edge, so chunks/pads/banks have no T-junctions.
function conformEdges(cells) {
    const vertices = new Map(), weldBins = new Map(), tolerance = 1e-5;
    const weldKey = p => p.map(v => Math.floor(v / tolerance)).join(',');
    for (const cell of cells) for (const p of cell) {
        const ix = Math.floor(p[0] / tolerance), iz = Math.floor(p[1] / tolerance);
        let welded = null;
        for (let dx = -1; dx <= 1 && !welded; dx++) for (let dz = -1; dz <= 1 && !welded; dz++) {
            welded = (weldBins.get(`${ix + dx},${iz + dz}`) || []).find(q => Math.hypot(...sub(p, q)) < tolerance) || null;
        }
        if (!welded) {
            welded = p.map(v => Math.abs(v / 50 - Math.round(v / 50)) < 1e-8 ? Math.round(v / 50) * 50 : round(v));
            const key = weldKey(welded);
            if (!weldBins.has(key)) weldBins.set(key, []);
            weldBins.get(key).push(welded);
        }
        vertices.set(pointKey(p), welded);
    }
    const bins = new Map(), bin = p => `${Math.floor(p[0] / 10)},${Math.floor(p[1] / 10)}`;
    for (const p of new Set(vertices.values())) {const key = bin(p); if (!bins.has(key)) bins.set(key, []); bins.get(key).push(p);}
    return cells.map(cell => {
        const result = [];
        for (let i = 0; i < cell.length; i++) {
            const a = vertices.get(pointKey(cell[i])), b = vertices.get(pointKey(cell[(i + 1) % cell.length])), d = sub(b, a), length = Math.hypot(...d), candidates = [];
            result.push(a);
            const bb = bounds([a, b]);
            for (let ix = Math.floor((bb[0] - 1e-6) / 10); ix <= Math.floor((bb[2] + 1e-6) / 10); ix++) for (let iz = Math.floor((bb[1] - 1e-6) / 10); iz <= Math.floor((bb[3] + 1e-6) / 10); iz++) {
                for (const p of bins.get(`${ix},${iz}`) || []) {
                    const t = ((p[0] - a[0]) * d[0] + (p[1] - a[1]) * d[1]) / length ** 2;
                    if (Math.hypot(...sub(p, a)) > tolerance && Math.hypot(...sub(p, b)) > tolerance && t > 0 && t < 1 && Math.abs(cross(d, sub(p, a))) / length < 2e-7) candidates.push({p, t});
                }
            }
            candidates.sort((p, q) => p.t - q.t);
            result.push(...candidates.map(q => q.p));
        }
        return clean(result);
    }).filter(cell => cell.length >= 3 && area(cell) > 1e-8);
}
let triangles = null, triangleBins = null;
function generate() {
    const result = buildPolygons(), cells = conformEdges(result.cells);
    triangles = [];
    triangleBins = null;
    for (const cell of cells) {
        // Interpolate the existing boundary: resampling curved heights creates steep dips in thin clipped cells.
        const c = center(cell), cy = cell.reduce((sum, point) => sum + authoredHeight(...point), 0) / cell.length;
        for (let i = 0; i < cell.length; i++) {
            const a = cell[i], b = cell[(i + 1) % cell.length];
            if (signedArea([c, a, b]) > 1e-10) triangles.push([[c[0], cy, c[1]], [a[0], authoredHeight(...a), a[1]], [b[0], authoredHeight(...b), b[1]]]);
        }
    }
    // Welding can leave microscopic dry three-edge slivers; close only those bounded dry loops.
    const edgeMap = new Map();
    for (const face of triangles) for (let i = 0; i < 3; i++) {
        const a = face[i], b = face[(i + 1) % 3], key = [pointKey([a[0], a[2]]), pointKey([b[0], b[2]])].sort().join('|');
        const edge = edgeMap.get(key) || {a, b, count: 0}; edge.count++; edgeMap.set(key, edge);
    }
    const dryEdges = [...edgeMap.values()].filter(e => {
        const p = [(e.a[0] + e.b[0]) / 2, (e.a[2] + e.b[2]) / 2];
        return e.count === 1 && Math.abs(p[0]) < 249.99999 && Math.abs(p[1]) < 249.99999 && bankDistance(p) > 0.0001;
    });
    let healedSliverArea = 0;
    while (dryEdges.length) {
        const first = dryEdges.pop(), loop = [first.a, first.b];
        while (pointKey([loop[0][0], loop[0][2]]) !== pointKey([loop[loop.length - 1][0], loop[loop.length - 1][2]])) {
            const last = loop[loop.length - 1], index = dryEdges.findIndex(e => pointKey([e.a[0], e.a[2]]) === pointKey([last[0], last[2]]) || pointKey([e.b[0], e.b[2]]) === pointKey([last[0], last[2]]));
            assert(index >= 0 && loop.length <= 4, 'Unexpected open dry terrain seam');
            const [edge] = dryEdges.splice(index, 1);
            loop.push(pointKey([edge.a[0], edge.a[2]]) === pointKey([last[0], last[2]]) ? edge.b : edge.a);
        }
        loop.pop();
        assert(loop.length === 3, 'Precision seam must be a three-edge sliver');
        const poly = loop.map(v => [v[0], v[2]]), size = area(poly);
        assert(size < 0.001 && !wet(center(poly)), 'Refuse to fill a non-precision/wet gap');
        if (signedArea(poly) < 0) loop.reverse();
        triangles.push(loop); healedSliverArea += size;
    }
    return {...result, cells, triangles, healedSliverArea};
}
function triangleHeight(x, z, triangle) {
    const [a, b, c] = triangle, den = (b[2] - c[2]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[2] - c[2]);
    const u = ((b[2] - c[2]) * (x - c[0]) + (c[0] - b[0]) * (z - c[2])) / den;
    const v = ((c[2] - a[2]) * (x - c[0]) + (a[0] - c[0]) * (z - c[2])) / den;
    return u >= -1e-7 && v >= -1e-7 && u + v <= 1 + 1e-7 ? u * a[1] + v * b[1] + (1 - u - v) * c[1] : null;
}
function heightAt(x, z) {
    if (!triangles) generate();
    if (!triangleBins) {
        triangleBins = new Map();
        for (const triangle of triangles) {
            const bb = bounds(triangle.map(v => [v[0], v[2]]));
            for (let ix = Math.floor(bb[0] / 10); ix <= Math.floor(bb[2] / 10); ix++) for (let iz = Math.floor(bb[1] / 10); iz <= Math.floor(bb[3] / 10); iz++) {
                const key = `${ix},${iz}`; if (!triangleBins.has(key)) triangleBins.set(key, []); triangleBins.get(key).push(triangle);
            }
        }
    }
    for (const triangle of triangleBins.get(`${Math.floor(x / 10)},${Math.floor(z / 10)}`) || []) {const y = triangleHeight(x, z, triangle); if (y !== null) return y;}
    return null;
}
function sampleProfiles(sampleRoutes = terrain.corrected_corridors) {
    if (!triangles) generate();
    return sampleRoutes.map(route => {
        let worst = {grade_percent: 0}, maxProfileError = 0;
        for (let i = 1; i < route.points_xz_m.length; i++) {
            const a = route.points_xz_m[i - 1], b = route.points_xz_m[i], d = sub(b, a), length = Math.hypot(...d), normal = [-d[1] / length, d[0] / length], steps = Math.ceil(length);
            const width = route.width_m || route.clear_width_m;
            for (const offset of [-width / 2, 0, width / 2]) {
                let previous = null;
                for (let j = 0; j <= steps; j++) {
                    const p = [a[0] + d[0] * j / steps + normal[0] * offset, a[1] + d[1] * j / steps + normal[1] * offset], y = heightAt(...p);
                    if (y === null || wet(p)) {previous = null; continue;}
                    const intended = lerp(route.surface_y_m[i - 1], route.surface_y_m[i], j / steps);
                    maxProfileError = Math.max(maxProfileError, Math.abs(y - intended));
                    if (previous) {
                        const grade = Math.abs(y - previous.y) / (length / steps) * 100;
                        if (grade > worst.grade_percent) worst = {grade_percent: grade, offset_m: offset, segment: i - 1, from_xz_m: previous.p, to_xz_m: p, from_y_m: previous.y, to_y_m: y};
                    }
                    previous = {p, y};
                }
            }
        }
        return {id: route.id, maximum_grade_percent: route.maximum_grade_percent, maximum_profile_error_m: maxProfileError, worst, pass: worst.grade_percent <= route.maximum_grade_percent + 0.01};
    });
}
function continuousGrades() {
    if (!triangles) generate();
    return terrain.corrected_corridors.map(route => {
        let maximum = 0, witness = null;
        for (const segment of segments.filter(s => s.id === route.id)) for (const face of triangles) {
            const xz = face.map(v => [v[0], v[2]]), p = center(xz);
            if (!segment.poly.every((a, i) => cross(sub(segment.poly[(i + 1) % 4], a), sub(p, a)) >= -1e-7)) continue;
            const [a, b, c] = face, dx1 = b[0] - a[0], dz1 = b[2] - a[2], dx2 = c[0] - a[0], dz2 = c[2] - a[2], den = dx1 * dz2 - dx2 * dz1;
            if (Math.abs(den) < 2e-5) continue;
            const dy1 = b[1] - a[1], dy2 = c[1] - a[1], gx = (dy1 * dz2 - dy2 * dz1) / den, gz = (dx1 * dy2 - dx2 * dy1) / den;
            const d = sub(segment.b, segment.a), grade = Math.abs(gx * d[0] + gz * d[1]) / Math.hypot(...d) * 100;
            if (grade > maximum) {maximum = grade; witness = {centroid_xz_m: p, face_area_m2: Math.abs(den) / 2, vertices: face};}
        }
        return {id: route.id, maximum_grade_percent: route.maximum_grade_percent, maximum_triangle_longitudinal_grade_percent: maximum, numerical_sliver_area_exclusion_m2: 1e-5, pass: maximum <= route.maximum_grade_percent + 0.01, witness};
    });
}
function writeOBJ(faces) {
    const lines = ['# Static dry Town500m terrain; X east Z south Y up; identity root.'];
    for (const triangle of faces) for (const p of [triangle[0], triangle[2], triangle[1]]) lines.push(`v ${p.map(num).join(' ')}`);
    for (let i = 0; i < faces.length; i++) lines.push(`f ${i * 3 + 1} ${i * 3 + 2} ${i * 3 + 3}`);
    return lines.join('\n') + '\n';
}
function verify(result) {
    const totalArea = triangles.reduce((sum, t) => sum + area(t.map(v => [v[0], v[2]])), 0);
    assert(Math.abs(totalArea + result.wetRemoved - 250000) < 0.01, `Dry/wet area mismatch ${totalArea + result.wetRemoved}`);
    const vertices = new Map(), faces = new Set(), edges = new Map();
    let minimum = Infinity, maximum = -Infinity, wetIntersectionArea = 0, maximumBankReserveHeight = -Infinity;
    const reservePolys = bankReservations.map(r => ({poly: rectangle(...r.center, ...r.size, r.yaw)})).map(r => ({...r, bb: bounds(r.poly)}));
    for (const triangle of triangles) {
        const xz = triangle.map(v => [v[0], v[2]]);
        assert(!wet(center(xz)), 'Wet interior has terrain triangle');
        for (const water of wetPolygons) {
            if (!overlap(bounds(xz), bounds(water))) continue;
            let pieces = [xz];
            for (let i = 0; i < water.length; i++) pieces = pieces.flatMap(p => splitPolygon(p, water[i], water[(i + 1) % water.length]));
            wetIntersectionArea += pieces.filter(p => inside(center(p), water)).reduce((sum, p) => sum + area(p), 0);
        }
        assert(signedArea(xz) > 0, 'Unexpected collision winding');
        for (const reserve of reservePolys) {
            if (!overlap(bounds(xz), reserve.bb)) continue;
            const cut = convexIntersection(xz, reserve.poly);
            if (cut.length >= 3 && area(cut) > 1e-7) {
                maximumBankReserveHeight = Math.max(maximumBankReserveHeight, ...cut.map(p => triangleHeight(...p, triangle)));
            }
        }
        const face = triangle.map(v => pointKey([v[0], v[2]])).sort().join('|');
        assert(!faces.has(face), 'Duplicate triangle'); faces.add(face);
        for (const [x, y, z] of triangle) {
            const key = pointKey([x, z]);
            if (vertices.has(key)) assert(Math.abs(vertices.get(key) - y) < 1e-7, `Height seam ${key}`);
            vertices.set(key, y); minimum = Math.min(minimum, y); maximum = Math.max(maximum, y);
            assert(y >= -0.350001 && y <= 20.000001, 'Terrain height outside contract');
            if (inside([x, z], core)) assert(y >= 0.499999 && y <= 3.500001, 'Core relief exceeds contract');
        }
        for (let i = 0; i < 3; i++) {const key = [pointKey(xz[i]), pointKey(xz[(i + 1) % 3])].sort().join('|'); edges.set(key, (edges.get(key) || 0) + 1);}
    }
    assert([...edges.values()].every(v => v <= 2), 'Overlapping/nonmanifold triangle edge');
    assert(wetIntersectionArea < 0.001, `Wet triangle intersection exceeds numerical clipping tolerance ${wetIntersectionArea}`);
    assert(maximumBankReserveHeight <= 6.0001, `Bank reservation exceeds conservative jump fixture height ${maximumBankReserveHeight}`);
    const boundaryEdges = [...edges].filter(([, count]) => count === 1).map(([key]) => key.split('|').map(k => k.split(',').map(Number)));
    for (const [a, b] of boundaryEdges) {
        const p = center([a, b]);
        assert(Math.abs(p[0]) > 249.99999 || Math.abs(p[1]) > 249.99999 || bankDistance(p) < 0.0001, `Internal dry seam ${JSON.stringify([a, b])}`);
    }
    const padChecks = pads.map(p => {
        const samples = [p.center, ...p.poly, ...p.poly.map((a, i) => center([a, p.poly[(i + 1) % p.poly.length]]))].filter(q => !wet(q));
        const errors = samples.map(q => Math.abs(heightAt(...q) - p.y));
        assert(errors.every(e => e < 1e-5), `Pad not flat ${p.id}: ${Math.max(...errors)}`);
        return {id: p.id, surface_y_m: p.y, yaw_deg: p.yaw, center_xz_m: p.center, size_m: p.size, maximum_error_m: Math.max(...errors)};
    });
    const anchors = terrain.terrain_anchors.filter(a => a.id.startsWith('HILL_')).map(a => ({id: a.id, xz_m: a.xz_m, target_y_m: a.y_m, observed_y_m: heightAt(...a.xz_m)}));
    for (const anchor of anchors) assert(Math.abs(anchor.observed_y_m - anchor.target_y_m) < 1e-5, `Hill peak ${anchor.id}`);
    const spawnContact = [-230.06922913, 172.22286987];
    const spawnFace = triangles.find(face => triangleHeight(...spawnContact, face) !== null);
    assert(spawnFace, 'S1 shoulder contact has dry terrain');
    const u = spawnFace[1].map((value, i) => value - spawnFace[0][i]), v = spawnFace[2].map((value, i) => value - spawnFace[0][i]);
    const normal = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
    const spawnSlope = Math.atan2(Math.hypot(normal[0], normal[2]), Math.abs(normal[1])) * 180 / Math.PI;
    assert(spawnSlope < 45 && Math.abs(heightAt(...spawnContact) - authoredHeight(...spawnContact)) < 1e-5, `S1 shoulder interpolation regression: slope=${spawnSlope}`);
    const thinContact = [-231.045272827, -60.229095458];
    const thinFace = triangles.find(face => triangleHeight(...thinContact, face) !== null);
    assert(thinFace, 'Measured S2 north-route contact has dry terrain');
    const thinU = thinFace[1].map((value, i) => value - thinFace[0][i]), thinV = thinFace[2].map((value, i) => value - thinFace[0][i]);
    const thinNormal = [thinU[1] * thinV[2] - thinU[2] * thinV[1], thinU[2] * thinV[0] - thinU[0] * thinV[2], thinU[0] * thinV[1] - thinU[1] * thinV[0]];
    const thinSlope = Math.atan2(Math.hypot(thinNormal[0], thinNormal[2]), Math.abs(thinNormal[1])) * 180 / Math.PI;
    assert(thinSlope < 10, `Thin-cell centroid creates a false terrain ridge: slope=${thinSlope}`);
    return {thin_cell_centroid_regression: {contact_xz_m: thinContact, slope_deg: thinSlope, limit_deg: 10}, spawn_shoulder_regression: {contact_xz_m: spawnContact, physical_height_m: heightAt(...spawnContact), authored_height_m: authoredHeight(...spawnContact), slope_deg: spawnSlope}, dry_area_m2: totalArea, excluded_wet_union_area_m2: result.wetRemoved, triangle_count: triangles.length, vertex_count: vertices.size, min_y_m: minimum, max_y_m: maximum, exact_flat_pads: padChecks, hill_anchors: anchors, shared_vertex_height_seams: 0, internal_open_edges: 0, boundary_edges: boundaryEdges.length, duplicate_triangles: 0, coordinate_weld_tolerance_m: 1e-5, precision_dry_sliver_closure_area_m2: result.healedSliverArea, full_triangle_wet_intersection_area_m2: wetIntersectionArea, bank_reservation_setback_m: 6, maximum_collision_height_within_6m_bank_reservation_y_m: maximumBankReserveHeight};
}
function build(checkOnly = false) {
    const result = generate(), report = verify(result), chunks = new Map();
    const grades = sampleProfiles();
    assert(grades.every(r => r.pass), `Actual corridor grade failure: ${JSON.stringify(grades.filter(r => !r.pass))}`);
    const continuous = continuousGrades();
    assert(continuous.every(r => r.pass), `Continuous corridor triangle grade failure: ${JSON.stringify(continuous.filter(r => !r.pass))}`);
    const graphGrades = sampleProfiles(terrain.route_graph.edges.filter(e => e.kind === 'dry_path'));
    assert(graphGrades.every(r => r.pass), `Dry route graph grade failure: ${JSON.stringify(graphGrades.filter(r => !r.pass))}`);
    const colours = {town: [.42, .39, .33], industry: [.35, .4, .43], bunker: [.4, .42, .35], hills: [.51, .48, .4], forest: [.3, .4, .3], farmland: [.49, .43, .3], shore: [.48, .44, .36]};
    for (const triangle of triangles) {
        const c = center(triangle.map(v => [v[0], v[2]]));
        const ix = Math.min(4, Math.floor((c[0] + 250) / 100)), iz = Math.min(4, Math.floor((c[1] + 250) / 100));
        const zone = layout.zones.find(z => !['river', 'lake'].includes(z.id) && inside(c, z.polygon_xz_m))?.id || 'shore';
        const key = `chunk_${ix}_${iz}_${zone}`;
        assert(triangle.every(v => v[0] >= -250 + ix * 100 - 1e-5 && v[0] <= -150 + ix * 100 + 1e-5 && v[2] >= -250 + iz * 100 - 1e-5 && v[2] <= -150 + iz * 100 + 1e-5), 'Terrain triangle crosses its chunk boundary');
        if (!chunks.has(key)) chunks.set(key, []); chunks.get(key).push(triangle);
    }
    const ext = [], shapes = [], nodes = [], mats = Object.entries(colours).map(([id, rgb]) => `[sub_resource type="StandardMaterial3D" id="${id}"]\nalbedo_color = Color(${rgb.join(', ')}, 1)\nroughness = 1\ncull_mode = 2`);
    for (const [name, faces] of chunks) {
        const file = `${name}.obj`, zone = name.split('_').slice(3).join('_');
        const content = writeOBJ(faces);
        if (checkOnly) assert.equal(fs.readFileSync(path.join(outputDir, file), 'utf8'), content, `Stale ${file}`);
        else fs.writeFileSync(path.join(outputDir, file), content);
        ext.push(`[ext_resource type="ArrayMesh" path="res://Scene/World/Town500m/Terrain/${file}" id="${name}"]`);
        shapes.push(`[sub_resource type="ConcavePolygonShape3D" id="shape_${name}"]\ndata = PackedVector3Array(${faces.flat(2).map(num).join(', ')})\nbackface_collision = true`);
        nodes.push(`[node name="${name}" type="MeshInstance3D" parent="."]\nmesh = ExtResource("${name}")\nmaterial_override = SubResource("${zone}")\n\n[node name="DryTerrainBody" type="StaticBody3D" parent="${name}"]\ncollision_layer = 1\ncollision_mask = 0\n\n[node name="CollisionShape3D" type="CollisionShape3D" parent="${name}/DryTerrainBody"]\nshape = SubResource("shape_${name}")`);
    }
    const scene = `[gd_scene load_steps=${ext.length + shapes.length + mats.length + 1} format=3]\n\n${ext.join('\n\n')}\n\n${mats.join('\n\n')}\n\n${shapes.join('\n\n')}\n\n[node name="Town500mDryTerrain" type="Node3D"]\nmetadata/authoring_source = "design/town-500m/phase2/terrain-authoring.cjs"\nmetadata/wet_collision = "none; exact canonical river/lake union excluded"\n\n${nodes.join('\n\n')}\n`;
    if (checkOnly) assert.equal(fs.readFileSync(path.join(outputDir, 'dry_terrain.tscn'), 'utf8'), scene, 'Stale terrain scene');
    else fs.writeFileSync(path.join(outputDir, 'dry_terrain.tscn'), scene);
    const hashes = Object.fromEntries(['layout.json', 'terrain-contract.json', 'building-catalogue.json'].map(n => [n, crypto.createHash('sha256').update(fs.readFileSync(path.join(sourceDir, n))).digest('hex')]));
    const fullReport = {status: 'OFFLINE STATIC GEOMETRY CHECKED; NATIVE PENDING', authoring_libraries: 'Node standard library only; existing Concept B convex partition pattern', source_sha256: hashes, ...report, road_grades: grades, continuous_road_triangle_grades: continuous, dry_route_graph_grades: graphGrades, mesh_groups: chunks.size, chunk_bounds_m: 100, collision: 'dry triangles only; StaticBody3D layer1 mask0; no submerged bed/water geometry', height_profile_policy: 'Canonical node elevations with exact flat pad/corner/adjacent-strip overlap intervals, piecewise linear between intervals; partition every profile breakpoint; actual corridor priority asphalt/gravel/dirt over duplicate route graph', boundary: 'visible last2m local base+4m dry escarpment/berm capped20, exact gridcuts at248; road termini owned by primary collapse geometry', limitations: ['Godot import/winding/player/ray/nav checks pending primary MCP', 'Natural berm profiles override at actual external road termini; visible collapse blockers owned by primary', 'Road surfaces must clip/conform to exported terrain triangles', 'Continuous grade checks exclude triangle area below1e-5m2 numerical slivers;1m centre/both-edge sampling remains included', 'No jump containment or performance claim']};
    if (!checkOnly) fs.writeFileSync(path.join(__dirname, 'terrain-authoring.report.json'), JSON.stringify(fullReport, null, 2) + '\n');
    console.log(JSON.stringify({mode: checkOnly ? 'check' : 'write', triangles: triangles.length, groups: chunks.size, dry_area_m2: report.dry_area_m2, wet_area_m2: report.excluded_wet_union_area_m2, pads: pads.length, y: [report.min_y_m, report.max_y_m]}));
    return fullReport;
}
if (require.main === module) build(process.argv.includes('--check'));
module.exports = {generate, build, authoredHeight, heightAt, triangleHeight, sampleProfiles, continuousGrades, wet, pads, segments, splitPolygon, signedArea, area, bounds, overlap, get triangles() {if (!triangles) generate(); return triangles;}};
