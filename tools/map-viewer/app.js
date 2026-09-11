import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const $ = id => document.getElementById(id);
const gameToViewer = p => new THREE.Vector3(p[0], p[2], -p[1]);
const viewerToGame = p => [p.x, -p.z, p.y].map(n => Number(n.toFixed(6)));
const status = (message, error = false) => { $('status').textContent = message; $('status').classList.toggle('error', error); };
let project, layout, world, selected = null, moving = false, dirty = false, busy = false;
const history = [];
const scene = new THREE.Scene();
scene.background = new THREE.Color('#101820');
const camera = new THREE.PerspectiveCamera(48, 1, 1, 70000);
const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.localClippingEnabled = true;
$('viewport').appendChild(renderer.domElement);
const controls = new OrbitControls(camera, renderer.domElement);
controls.enableDamping = true;
controls.minDistance = 25;
controls.maxDistance = 45000;
scene.add(new THREE.HemisphereLight(0xc5e4ff, 0x697b8b, 2.3));
const sunlight = new THREE.DirectionalLight(0xffedd6, 2.7);
sunlight.position.set(1000, 3000, 800); scene.add(sunlight);
const clip = new THREE.Plane(new THREE.Vector3(0, -1, 0), 10000);
const markerGroup = new THREE.Group(); scene.add(markerGroup);
const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2();
const markerTargets = [];

function changed() {
  dirty = true;
  $('save').textContent = 'Save & install •';
  status('Unsaved changes. Save installs the layout for the next match.');
}
function remember() {
  history.push(structuredClone(layout.markers));
  if (history.length > 40) history.shift();
}
function disposeMarkers() {
  markerGroup.traverse(object => {
    object.geometry?.dispose();
    if (object.material) { object.material.map?.dispose(); object.material.dispose(); }
  });
  markerGroup.clear(); markerTargets.length = 0;
}
function textSprite(text, color) {
  const canvas = document.createElement('canvas'); canvas.width = 512; canvas.height = 128;
  const context = canvas.getContext('2d');
  context.fillStyle = '#10202ce8'; context.fillRect(0, 0, 512, 128);
  context.strokeStyle = color; context.lineWidth = 5; context.strokeRect(3, 3, 506, 122);
  context.fillStyle = color; context.font = 'bold 29px system-ui'; context.textAlign = 'center';
  context.fillText(text, 256, 76, 480);
  const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(canvas), depthTest: false }));
  sprite.scale.set(190, 47.5, 1); return sprite;
}
function drawMarkers() {
  disposeMarkers();
  $('markers').replaceChildren();
  layout.markers.forEach(marker => {
    const preset = project.presets[marker.preset];
    const option = new Option(`${preset.symbol}  ${marker.id}`, marker.id);
    option.selected = marker.id === selected; $('markers').add(option);
    const group = new THREE.Group(); group.position.copy(gameToViewer(marker.position));
    group.visible = marker.position[2] <= Number($('ceiling').value);
    const color = marker.id === selected ? '#ffffff' : preset.color;
    const anchor = new THREE.Mesh(new THREE.SphereGeometry(6, 12, 8), new THREE.MeshBasicMaterial({ color, depthTest: false }));
    anchor.userData.id = marker.id; markerTargets.push(anchor); group.add(anchor);
    const radians = marker.yaw * Math.PI / 180;
    const forward = gameToViewer([Math.cos(radians), Math.sin(radians), 0]);
    group.add(new THREE.ArrowHelper(forward, new THREE.Vector3(0, 4, 0), 48, color, 12, 7));
    const interactive = ['wall_buy', 'quick_revive', 'power', 'magic_wheel', 'barricade'].includes(marker.preset);
    if (interactive || marker.id === selected) {
      const radius = interactive ? 96 : 24;
      const ring = new THREE.Mesh(new THREE.RingGeometry(radius - 1.5, radius, 48), new THREE.MeshBasicMaterial({ color, side: THREE.DoubleSide, transparent: true, opacity: .65 }));
      ring.rotation.x = -Math.PI / 2; ring.position.y = 3; group.add(ring);
    }
    const label = textSprite(`${preset.symbol} · ${marker.id}`, color);
    label.position.y = 64; label.userData.id = marker.id;
    group.add(label); markerTargets.push(label); markerGroup.add(group);
  });
  $('count').textContent = `${layout.markers.length} / 32`;
  $('undo').disabled = history.length === 0;
  const marker = layout.markers.find(m => m.id === selected);
  $('properties').hidden = !marker;
  if (marker) {
    $('identity').value = marker.id;
    ['x', 'y', 'z'].forEach((axis, i) => $(axis).value = marker.position[i]);
    $('yaw').value = marker.yaw;
  }
  $('move').textContent = moving ? 'Click a surface…' : 'Move on surface';
}
function select(id) { selected = id; moving = false; drawMarkers(); }
function uniqueID(preset) {
  let count = 1;
  while (layout.markers.some(m => m.id === `${preset}_${count}`)) count++;
  return `${preset}_${count}`;
}
function frame(center, distance, top = false) {
  controls.target.copy(center);
  camera.up.set(0, 1, 0);
  camera.position.copy(center).add(top ? new THREE.Vector3(0, distance, .1) : new THREE.Vector3(distance * .6, distance * .75, distance * .6));
  controls.update();
}
function fit() {
  if (!world) return;
  const box = new THREE.Box3().setFromObject(world);
  frame(box.getCenter(new THREE.Vector3()), box.getSize(new THREE.Vector3()).length() * .65);
}
$('fit').onclick = fit;
$('focus').onclick = () => {
  const marker = layout?.markers.find(m => m.id === selected);
  if (marker) frame(gameToViewer(marker.position), 650);
};
$('top').onclick = () => frame(controls.target.clone(), camera.position.distanceTo(controls.target), true);
$('ceiling').oninput = () => {
  clip.constant = Number($('ceiling').value);
  $('ceiling-value').textContent = clip.constant;
  if (layout) drawMarkers();
};
$('markers').onchange = () => select($('markers').value);
$('move').onclick = () => { moving = !moving; drawMarkers(); };
$('delete').onclick = () => {
  remember(); layout.markers = layout.markers.filter(m => m.id !== selected);
  selected = null; moving = false; changed(); drawMarkers();
};
$('duplicate').onclick = () => {
  if (layout.markers.length >= 32) return status('32 marker limit reached.', true);
  const marker = structuredClone(layout.markers.find(m => m.id === selected));
  remember(); marker.id = uniqueID(marker.preset); layout.markers.push(marker);
  selected = marker.id; moving = true; changed(); drawMarkers();
};
$('undo').onclick = () => {
  if (!history.length) return;
  layout.markers = history.pop(); selected = null; moving = false; changed(); drawMarkers();
};
$('properties').onsubmit = event => {
  event.preventDefault();
  const id = $('identity').value;
  if (layout.markers.some(m => m.id === id && m.id !== selected)) return status('That ID is already used.', true);
  const position = ['x', 'y', 'z'].map(axis => Number($(axis).value));
  const yaw = Number($('yaw').value);
  if (![...position, yaw].every(Number.isFinite)) return status('Use finite coordinate values.', true);
  if (position.some((n, i) => n < project.geometry.bounds.min[i] - 256 || n > project.geometry.bounds.max[i] + 256)) return status('Position is outside the exported world.', true);
  remember();
  Object.assign(layout.markers.find(m => m.id === selected), { id, position, yaw: ((yaw % 360) + 360) % 360 });
  selected = id; changed(); drawMarkers();
};

let down;
renderer.domElement.addEventListener('pointerdown', e => { if (e.button === 0) down = [e.clientX, e.clientY]; });
renderer.domElement.addEventListener('pointerup', e => {
  if (e.button !== 0 || !down || Math.hypot(e.clientX - down[0], e.clientY - down[1]) > 5 || !world) return;
  down = null;
  const rect = renderer.domElement.getBoundingClientRect();
  pointer.set((e.clientX - rect.left) / rect.width * 2 - 1, -(e.clientY - rect.top) / rect.height * 2 + 1);
  raycaster.setFromCamera(pointer, camera);
  const markerHit = raycaster.intersectObjects(markerTargets, false).find(hit => hit.object.parent.visible);
  if (!moving && markerHit) return select(markerHit.object.userData.id);
  const hit = raycaster.intersectObject(world, true).find(item => item.point.y <= clip.constant + .001);
  if (!hit) return status('No visible world surface at that point.', true);
  const position = viewerToGame(hit.point);
  $('coordinates').textContent = `Game X ${position[0].toFixed(3)} / Y ${position[1].toFixed(3)} / Z ${position[2].toFixed(3)}`;
  const preset = $('preset').value;
  if (!moving && !preset) { status('Surface inspected. Choose a symbol to place here.'); return; }
  const normalMatrix = new THREE.Matrix3().getNormalMatrix(hit.object.matrixWorld);
  const surfaceNormal = hit.face.normal.clone().applyMatrix3(normalMatrix).normalize();
  if (surfaceNormal.dot(raycaster.ray.direction) > 0) surfaceNormal.negate();
  const normal = viewerToGame(surfaceNormal);
  if (moving) {
    remember(); Object.assign(layout.markers.find(m => m.id === selected), { position, normal }); moving = false;
  } else {
    if (layout.markers.length >= 32) return status('32 marker limit reached.', true);
    remember(); selected = uniqueID(preset);
    const yaw = Math.abs(normal[2]) < .8 ? (Math.atan2(normal[1], normal[0]) * 180 / Math.PI + 360) % 360 : 0;
    layout.markers.push({ id: selected, preset, position, normal, yaw });
  }
  changed(); drawMarkers();
});

$('save').onclick = async () => {
  if (busy) return;
  busy = true; $('save').disabled = true;
  const submitted = JSON.stringify(layout);
  try {
    const response = await fetch('/api/layout', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: submitted });
    const result = await response.json();
    if (!response.ok) throw new Error(result.error);
    if (JSON.stringify(layout) === submitted) {
      layout = result.layout; dirty = false; $('save').textContent = 'Save & install'; drawMarkers(); status(result.message);
    } else status('Submitted layout installed. Newer edits are still unsaved.');
  } catch (error) { status(error.message, true); }
  finally { busy = false; $('save').disabled = false; }
};
$('export').onclick = () => {
  const url = URL.createObjectURL(new Blob([JSON.stringify(layout, null, 2) + '\n'], { type: 'application/json' }));
  const link = document.createElement('a'); link.href = url; link.download = 'mp_prime.json'; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
};
$('import').onclick = () => $('file').click();
$('file').onchange = async () => {
  try {
    const file = $('file').files[0]; if (!file) return;
    if (file.size > 65536) throw new Error('Layout exceeds 64 KiB.');
    const value = JSON.parse(await file.text());
    if (value.schemaVersion !== 1 || value.baseMap !== 'mp_prime' || value.geometry?.sha256 !== project.geometry.sha256 || value.geometry?.worldChecksum !== project.geometry.worldChecksum) throw new Error('Map or geometry fingerprint mismatch.');
    if (!Array.isArray(value.markers) || value.markers.length > 32) throw new Error('Invalid marker list.');
    const ids = new Set();
    for (const m of value.markers) {
      if (!m || typeof m.id !== 'string' || !/^[a-z][a-z0-9_]{0,39}$/.test(m.id) || ids.has(m.id) || !Object.hasOwn(project.presets, m.preset)) throw new Error('Invalid or duplicate marker ID / preset.');
      ids.add(m.id);
      if (![m.position, m.normal].every(v => Array.isArray(v) && v.length === 3 && v.every(Number.isFinite)) || !Number.isFinite(m.yaw) || Math.abs(m.normal.reduce((sum, n) => sum + n*n, 0) - 1) > .01) throw new Error('Invalid marker coordinates / normal.');
      if (m.position.some((n, i) => n < project.geometry.bounds.min[i] - 256 || n > project.geometry.bounds.max[i] + 256)) throw new Error('Marker is outside the exported world.');
    }
    remember(); layout = value; selected = null; moving = false; changed(); drawMarkers();
    status('Imported into the working layout. Save & install when ready.');
  } catch (error) { status(error.message, true); }
  finally { $('file').value = ''; }
};
window.addEventListener('beforeunload', event => { if (dirty) { event.preventDefault(); event.returnValue = ''; } });

new ResizeObserver(() => {
  const view = $('viewport'); camera.aspect = view.clientWidth / view.clientHeight;
  camera.updateProjectionMatrix(); renderer.setSize(view.clientWidth, view.clientHeight);
}).observe($('viewport'));
renderer.setAnimationLoop(() => { controls.update(); renderer.render(scene, camera); });

try {
  const response = await fetch('/api/project'); project = await response.json();
  if (!response.ok) throw new Error(project.error);
  layout = project.layout;
  for (const [id, preset] of Object.entries(project.presets)) $('preset').add(new Option(`${preset.symbol} — ${preset.label}`, id));
  const bounds = project.geometry.bounds;
  $('ceiling').min = Math.floor(bounds.min[2]); $('ceiling').max = Math.ceil(bounds.max[2]) + 1;
  $('ceiling').value = $('ceiling').max; $('ceiling').oninput();
  const gltf = await new GLTFLoader().loadAsync('/world.glb');
  world = gltf.scene;
  world.traverse(object => {
    if (object.isMesh) {
      object.material.dispose();
      object.material = new THREE.MeshStandardMaterial({ color: '#617c8e', flatShading: true, side: THREE.DoubleSide, roughness: .95, clippingPlanes: [clip] });
    }
  });
  scene.add(world); world.updateMatrixWorld(true); fit(); drawMarkers();
  $('coverage').textContent = `${project.geometry.triangles.toLocaleString()} triangles · ${project.geometry.omittedStaticProps.toLocaleString()} props omitted · no collision mesh`;
  $('save').disabled = false; $('loading').hidden = true;
  status('Ready. Reference markers use the original game coordinates.');
} catch (error) {
  $('loading').textContent = error.message; status(error.message, true);
}
