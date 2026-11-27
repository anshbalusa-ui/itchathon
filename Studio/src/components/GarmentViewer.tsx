import { useEffect, useRef, useState } from 'react';
import type { KeyboardEvent } from 'react';
import {
  AmbientLight,
  Color,
  DirectionalLight,
  DoubleSide,
  Group,
  Mesh,
  MeshBasicMaterial,
  MeshStandardMaterial,
  PerspectiveCamera,
  Scene,
  Spherical,
  WebGLRenderer,
} from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import type { AdmittedMesh, FitModelRevision, GarmentRevision } from '../domain/types';
import { createGarmentGeometry, createModelGeometry, type PreviewModelGeometry } from '../rendering/preview';

type View = 'front' | 'side' | 'back';
interface Runtime {
  camera: PerspectiveCamera;
  renderer: WebGLRenderer;
  controls: OrbitControls;
  group: Group;
  bodyMaterial: MeshStandardMaterial;
  shortsMaterial: MeshStandardMaterial;
  garmentMaterial: MeshStandardMaterial;
  comparisonMaterial: MeshBasicMaterial;
  render: () => void;
  current?: PreviewModelGeometry;
  bodyMesh?: Mesh;
  shortsMesh?: Mesh;
  garmentMesh?: Mesh;
  comparisonMesh?: Mesh;
}

export interface GarmentViewerProps {
  revision: GarmentRevision;
  model: FitModelRevision;
  meshes: ReadonlyMap<string, AdmittedMesh>;
  selectedSizeId?: string | null;
  comparison?: { revision: GarmentRevision; sizeId: string | null } | null;
}

export function GarmentViewer({ revision, model, meshes, selectedSizeId, comparison = null }: GarmentViewerProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const runtimeRef = useRef<Runtime | null>(null);
  const [contextError, setContextError] = useState<string | null>(null);
  const [modelError, setModelError] = useState<string | null>(null);
  const [garmentError, setGarmentError] = useState<string | null>(null);
  const [comparisonError, setComparisonError] = useState<string | null>(null);
  const [stats, setStats] = useState<PreviewModelGeometry | null>(null);
  const [garmentInfo, setGarmentInfo] = useState<{ sizeLabel: string | null; identity: string; warnings: string[] } | null>(null);
  const error = contextError || modelError || garmentError;
  const garmentSource = revision.schemaVersion === 1 ? revision.previewMeshes : revision.development;
  const legacyModelKey = revision.schemaVersion === 1 ? model.id : null;
  const comparisonSource = comparison?.revision.schemaVersion === 1 ? comparison.revision.previewMeshes : comparison?.revision.development;
  const comparisonLegacyModelKey = comparison?.revision.schemaVersion === 1 ? model.id : null;
  const [view, setView] = useState<View | null>('front');

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const viewport = canvas.parentElement;
    if (!viewport) return;
    let runtime: Runtime | undefined;
    let renderer: WebGLRenderer | undefined;
    let resizeObserver: ResizeObserver | undefined;
    let frame = 0;
    const contextLost = (event: Event) => {
      event.preventDefault();
      setContextError('The WebGL context was lost. Switch to 2D and back to retry.');
    };
    const contextRestored = () => { setContextError(null); runtime?.render(); };
    try {
      const scene = new Scene();
      scene.background = new Color('#f5f5f0');
      const camera = new PerspectiveCamera(34, 1, 0.05, 30);
      camera.position.set(0, 0.9, 4.2);
      renderer = new WebGLRenderer({ canvas, antialias: true, alpha: false });
      renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
      renderer.setSize(Math.max(viewport.clientWidth, 1), Math.max(viewport.clientHeight, 1), false);
      renderer.outputColorSpace = 'srgb';
      renderer.setClearColor('#f5f5f0', 1);
      scene.add(new AmbientLight(0xffffff, 1.5));
      const key = new DirectionalLight(0xffffff, 2.2);
      key.position.set(-2.5, 4, 4);
      scene.add(key);
      const fill = new DirectionalLight(0xc7d7ef, 1.1);
      fill.position.set(3, 1.5, -3);
      scene.add(fill);
      const group = new Group();
      scene.add(group);
      const bodyMaterial = new MeshStandardMaterial({ color: '#c2c1b8', roughness: 0.88, metalness: 0 });
      const shortsMaterial = new MeshStandardMaterial({ color: '#4c5550', roughness: 0.82, metalness: 0 });
      const garmentMaterial = new MeshStandardMaterial({ color: revision.visualMaterial.color, roughness: 0.78, metalness: 0, side: DoubleSide });
      const comparisonMaterial = new MeshBasicMaterial({ color: '#a26137', wireframe: true, transparent: true, opacity: 0.72, side: DoubleSide });
      const controls = new OrbitControls(camera, canvas);
      controls.enableDamping = false;
      controls.enablePan = false;
      controls.target.set(0, 0.9, 0);
      controls.minDistance = 1.3;
      controls.maxDistance = 8;
      controls.minPolarAngle = 0.18;
      controls.maxPolarAngle = Math.PI - 0.18;
      controls.update();
      const render = () => {
        if (frame) cancelAnimationFrame(frame);
        frame = requestAnimationFrame(() => {
          frame = 0;
          renderer?.render(scene, camera);
        });
      };
      const changed = () => { setView(null); render(); };
      controls.addEventListener('change', changed);
      resizeObserver = new ResizeObserver(() => {
        const width = Math.max(viewport.clientWidth, 1);
        const height = Math.max(viewport.clientHeight, 1);
        camera.aspect = width / height;
        camera.updateProjectionMatrix();
        renderer?.setSize(width, height, false);
        render();
      });
      resizeObserver.observe(viewport);
      runtime = { camera, renderer, controls, group, bodyMaterial, shortsMaterial, garmentMaterial, comparisonMaterial, render };
      runtimeRef.current = runtime;
      canvas.addEventListener('webglcontextlost', contextLost);
      canvas.addEventListener('webglcontextrestored', contextRestored);
      setContextError(null);
      render();
    } catch (cause) {
      renderer?.dispose();
      setContextError(cause instanceof Error ? cause.message : 'WebGL preview could not be started.');
      return () => resizeObserver?.disconnect();
    }
    return () => {
      resizeObserver?.disconnect();
      if (frame) cancelAnimationFrame(frame);
      canvas.removeEventListener('webglcontextlost', contextLost);
      canvas.removeEventListener('webglcontextrestored', contextRestored);
      if (!runtime) return;
      runtime.controls.dispose();
      runtime.current?.body.dispose();
      runtime.current?.shorts.dispose();
      runtime.garmentMesh?.geometry.dispose();
      runtime.comparisonMesh?.geometry.dispose();
      runtime.bodyMaterial.dispose();
      runtime.shortsMaterial.dispose();
      runtime.garmentMaterial.dispose();
      runtime.comparisonMaterial.dispose();
      runtime.renderer.dispose();
      runtimeRef.current = null;
    };
    // The rendering context and controls are mount-lifetime resources.
  }, []);

  useEffect(() => {
    const runtime = runtimeRef.current;
    if (!runtime) return;
    runtime.current?.body.dispose();
    runtime.current?.shorts.dispose();
    if (runtime.bodyMesh) runtime.group.remove(runtime.bodyMesh);
    if (runtime.shortsMesh) runtime.group.remove(runtime.shortsMesh);
    runtime.current = undefined;
    setStats(null);
    try {
      const next = createModelGeometry(model, meshes);
      runtime.current = next;
      runtime.bodyMesh = new Mesh(next.body, runtime.bodyMaterial);
      runtime.shortsMesh = new Mesh(next.shorts, runtime.shortsMaterial);
      runtime.group.add(runtime.bodyMesh, runtime.shortsMesh);
      if (revision.schemaVersion === 2) runtime.garmentMesh?.position.set(0, model.heightM * (1.5 / 1.8), 0.055);
      if (comparison?.revision.schemaVersion === 2) runtime.comparisonMesh?.position.set(0, model.heightM * (1.5 / 1.8), 0.055);
      setStats(next);
      setModelError(null);
    } catch (cause) {
      setModelError(cause instanceof Error ? cause.message : 'The selected fitting model could not be displayed.');
    }
    runtime.render();
  }, [model, meshes]);

  useEffect(() => {
    const runtime = runtimeRef.current;
    if (!runtime) return;
    runtime.garmentMesh?.geometry.dispose();
    if (runtime.garmentMesh) runtime.group.remove(runtime.garmentMesh);
    runtime.garmentMesh = undefined;
    setGarmentInfo(null);
    try {
      const next = createGarmentGeometry(revision, model, meshes, selectedSizeId);
      runtime.garmentMesh = new Mesh(next.geometry, runtime.garmentMaterial);
      runtime.garmentMesh.position.set(...next.offset);
      runtime.group.add(runtime.garmentMesh);
      setGarmentInfo({ sizeLabel: next.sizeLabel, identity: next.identity, warnings: next.warnings });
      setGarmentError(null);
    } catch (cause) {
      setGarmentError(cause instanceof Error ? cause.message : 'The selected garment geometry could not be displayed.');
    }
    runtime.render();
  }, [garmentSource, selectedSizeId, meshes, legacyModelKey]);

  useEffect(() => {
    const runtime = runtimeRef.current;
    if (!runtime) return;
    runtime.comparisonMesh?.geometry.dispose();
    if (runtime.comparisonMesh) runtime.group.remove(runtime.comparisonMesh);
    runtime.comparisonMesh = undefined;
    setComparisonError(null);
    if (comparison) {
      try {
        const next = createGarmentGeometry(comparison.revision, model, meshes, comparison.sizeId);
        runtime.comparisonMesh = new Mesh(next.geometry, runtime.comparisonMaterial);
        runtime.comparisonMesh.position.set(...next.offset);
        runtime.comparisonMesh.renderOrder = 2;
        runtime.group.add(runtime.comparisonMesh);
      } catch (cause) {
        setComparisonError(cause instanceof Error ? cause.message : 'The compared garment is unsupported.');
      }
    }
    runtime.render();
  }, [comparisonSource, comparison?.sizeId, meshes, comparisonLegacyModelKey]);

  useEffect(() => {
    const runtime = runtimeRef.current;
    if (!runtime) return;
    runtime.garmentMaterial.color.set(revision.visualMaterial.color);
    runtime.render();
  }, [revision.visualMaterial.color]);

  const setPreset = (preset: View) => {
    const runtime = runtimeRef.current;
    if (!runtime) return;
    const centerY = runtime.current ? runtime.current.heightM / 2 : 0.9;
    const distance = runtime.camera.position.distanceTo(runtime.controls.target) || 4;
    const angle = preset === 'front' ? 0 : preset === 'side' ? Math.PI / 2 : Math.PI;
    runtime.controls.target.set(0, centerY, 0);
    runtime.camera.position.set(Math.sin(angle) * distance, centerY, Math.cos(angle) * distance);
    runtime.camera.up.set(0, 1, 0);
    runtime.camera.lookAt(0, centerY, 0);
    runtime.controls.update();
    setView(preset);
  };
  const reset = () => {
    const runtime = runtimeRef.current;
    if (!runtime) return;
    const centerY = runtime.current ? runtime.current.heightM / 2 : 0.9;
    runtime.controls.target.set(0, centerY, 0);
    runtime.camera.position.set(0, centerY, Math.max(3.6, (runtime.current?.heightM ?? 1.8) * 2.35));
    runtime.camera.up.set(0, 1, 0);
    runtime.controls.update();
    setView('front');
  };
  const onKeyDown = (event: KeyboardEvent<HTMLCanvasElement>) => {
    const runtime = runtimeRef.current;
    if (!runtime || error) return;
    if (event.key === 'Home') { event.preventDefault(); reset(); return; }
    if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', '+', '=', '-', '_'].includes(event.key)) return;
    event.preventDefault();
    const spherical = new Spherical().setFromVector3(runtime.camera.position.clone().sub(runtime.controls.target));
    if (event.key === 'ArrowLeft') spherical.theta -= 0.12;
    if (event.key === 'ArrowRight') spherical.theta += 0.12;
    if (event.key === 'ArrowUp') spherical.phi -= 0.12;
    if (event.key === 'ArrowDown') spherical.phi += 0.12;
    if (event.key === '+' || event.key === '=') spherical.radius -= 0.2;
    if (event.key === '-' || event.key === '_') spherical.radius += 0.2;
    spherical.phi = Math.max(runtime.controls.minPolarAngle, Math.min(runtime.controls.maxPolarAngle, spherical.phi));
    spherical.radius = Math.max(runtime.controls.minDistance, Math.min(runtime.controls.maxDistance, spherical.radius));
    runtime.camera.position.setFromSpherical(spherical).add(runtime.controls.target);
    runtime.controls.update();
  };

  return <section className="preview-panel" aria-label="3D garment preview">
    <div className="panel-heading viewer-heading"><h2>3D preview</h2><span>{model.name}{garmentInfo?.sizeLabel ? ` · ${garmentInfo.sizeLabel}` : ''}</span></div>
    <div className="viewer-controls" role="group" aria-label="3D view controls">
      <button type="button" disabled={!!error || !stats} aria-pressed={view === 'front'} onClick={() => setPreset('front')}>Front</button>
      <button type="button" disabled={!!error || !stats} aria-pressed={view === 'side'} onClick={() => setPreset('side')}>Side</button>
      <button type="button" disabled={!!error || !stats} aria-pressed={view === 'back'} onClick={() => setPreset('back')}>Back</button>
      <button type="button" disabled={!!error || !stats} onClick={reset}>Reset</button>
    </div>
    <div className="drawing-surface viewer-surface">
      <canvas ref={canvasRef} tabIndex={0} onKeyDown={onKeyDown} aria-label={`3D preview of ${revision.name} on ${model.name}. Drag to orbit, scroll to zoom; focus and use arrow keys to orbit, plus or minus to zoom, Home to reset.`} style={{ display: 'block', width: '100%', height: '100%', minWidth: 0, minHeight: 0, outlineOffset: -3 }} />
      {error && <p role="alert" style={{ position: 'absolute', inset: 'auto 1rem 1rem', padding: '0.75rem', background: '#fff', color: '#8b1e1e' }}>3D preview unavailable: {error}</p>}
      {!error && !stats && <p role="status" style={{ position: 'absolute', inset: '1rem auto auto 1rem' }}>Loading 3D preview…</p>}
    </div>
    {stats && <div className="panel-caption viewer-caption"><p aria-live="polite">{model.name} · {stats.heightM.toFixed(2)} m · {stats.bodyVertexCount.toLocaleString()} vertices · mesh <code>{stats.bodyHash.slice(0, 12)}</code></p><p>Drag to orbit · Scroll to zoom · Keyboard: arrows, + / −, Home</p>{garmentInfo?.sizeLabel && <p>Garment: {garmentInfo.sizeLabel} · {revision.id.slice(0, 8)} · dimensions independent of model</p>}{comparison && <p className="comparison-key">Wireframe: compared revision / size · same model, rigid anchor and camera</p>}{comparisonError && <p role="alert">Comparison unavailable: {comparisonError}</p>}{garmentInfo && <details><summary>Preview assumptions</summary><ul>{garmentInfo.warnings.map(warning => <li key={warning}>{warning}</li>)}</ul></details>}</div>}
  </section>;
}

