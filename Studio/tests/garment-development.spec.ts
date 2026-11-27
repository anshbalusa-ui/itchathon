import { expect, test } from '@playwright/test';
import type { Page } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import type { GarmentRevision, ParametricGarmentRevision, ProjectPackage } from '../src/domain/types';
import type { MeasurementId, PatternDefinition } from '../src/domain/development-types';
import { POMS } from '../src/patterns/generator';

async function createDesign(page: Page, name: string, mode: 'parametric' | 'legacy' = 'parametric') {
  await page.goto('/');
  await page.getByLabel('Project name', { exact: true }).fill(name);
  await page.getByLabel('Garment name', { exact: true }).fill('Development tee');
  await page.getByRole('combobox', { name: 'Template', exact: true }).selectOption(mode);
  await page.getByRole('button', { name: 'Create project', exact: true }).click();
  await expect(page.getByRole('heading', { level: 1, name })).toBeVisible();
  await expect(page.getByText('Saved locally', { exact: true })).toBeVisible();
}
async function download(page: Page, button: string): Promise<Buffer> {
  const received = page.waitForEvent('download');
  await page.getByRole('button', { name: button, exact: true }).click();
  return readFile((await (await received).path())!);
}
async function packageFromPage(page: Page): Promise<{ bytes: Buffer; document: ProjectPackage }> {
  const bytes = await download(page, 'Export package');
  return { bytes, document: JSON.parse(bytes.toString('utf8')) as ProjectPackage };
}
function current(document: ProjectPackage): GarmentRevision {
  return document.revisions.find(item => item.id === document.project.currentGarmentRevisionId)!;
}
function parametric(document: ProjectPackage): ParametricGarmentRevision {
  const revision = current(document);
  expect(revision.schemaVersion).toBe(2);
  return revision as ParametricGarmentRevision;
}
function endpointMeasurement(pattern: PatternDefinition, id: MeasurementId): number {
  const definition = POMS.find(pom => pom.id === id)!;
  const piece = pattern.pieces.find(item => item.id === definition.endpoints.pieceId)!;
  const a = piece.points.find(point => point.id === definition.endpoints.startPointId)!;
  const b = piece.points.find(point => point.id === definition.endpoints.endPointId)!;
  return definition.method === 'vertical-projection' ? Math.abs(a.y - b.y) : Math.abs(a.x - b.x);
}
async function canvasPixels(page: Page): Promise<Buffer> {
  await page.evaluate(() => { const pending = Promise.withResolvers<void>(); requestAnimationFrame(() => requestAnimationFrame(() => pending.resolve())); return pending.promise; });
  return page.locator('canvas').screenshot();
}
async function changedPixels(page: Page, before: Buffer, after: Buffer): Promise<number> {
  return page.evaluate(async ({ a, b }) => {
    const decode = async (data: string) => {
      const image = new Image(); image.src = `data:image/png;base64,${data}`; await image.decode();
      const surface = new OffscreenCanvas(image.width, image.height), context = surface.getContext('2d')!;
      context.drawImage(image, 0, 0); return context.getImageData(0, 0, image.width, image.height).data;
    };
    const first = await decode(a), second = await decode(b);
    if (first.length !== second.length) throw new Error('Preview dimensions changed during comparison.');
    let count = 0;
    for (let index = 0; index < first.length; index += 4) if (Math.max(Math.abs(first[index] - second[index]), Math.abs(first[index + 1] - second[index + 1]), Math.abs(first[index + 2] - second[index + 2])) > 12) count++;
    return count / (first.length / 4);
  }, { a: before.toString('base64'), b: after.toString('base64') });
}
async function importPackage(page: Page, bytes: Buffer) {
  const opened = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Import project', exact: true }).click();
  await (await opened).setFiles({ name: 'design.onyou.json', mimeType: 'application/json', buffer: bytes });
}

test('specification → actual patterns and 3D → grade → compare → restore → reopen → portable project', async ({ page, context }, testInfo) => {
  test.setTimeout(60_000);
  const errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  await createDesign(page, 'Eternal garment development');
  await expect(page.locator('.viewer-surface [role="alert"]')).toHaveCount(0);
  await page.getByRole('button', { name: 'Moss', exact: true }).click();
  await page.getByRole('button', { name: 'Save project', exact: true }).click();
  await expect(page.getByText('Saved locally', { exact: true })).toBeVisible();
  const initial = await packageFromPage(page);
  const originalRevision = parametric(initial.document);
  const originalSize = originalRevision.development.sizeSet.sizes[0];
  await page.getByRole('combobox', { name: '2D representation', exact: true }).selectOption('piece-front');
  const frontPath = page.locator('g.current-pattern[data-piece-id="front"] path[data-boundary="seam"]');
  const initialPath = (await frontPath.getAttribute('d'))!;
  const originalCanvas = await page.locator('canvas').elementHandle();
  const originalPixels = await canvasPixels(page);
  await page.getByRole('spinbutton', { name: 'Body length (cm)', exact: true }).fill('74');
  await expect(frontPath).not.toHaveAttribute('d', initialPath);
  expect(await changedPixels(page, originalPixels, await canvasPixels(page))).toBeGreaterThan(0.0005);
  expect(await originalCanvas!.evaluate(node => node === document.querySelector('canvas'))).toBe(true);
  await page.getByRole('button', { name: 'Save project', exact: true }).click();
  await expect(page.getByText('Saved locally', { exact: true })).toBeVisible();
  const lengthSaved = await packageFromPage(page);
  const lengthRevision = parametric(lengthSaved.document);
  expect(lengthRevision.parentRevisionId).toBe(originalRevision.id);
  expect(lengthSaved.document.revisions.slice(0, initial.document.revisions.length)).toEqual(initial.document.revisions);
  expect(endpointMeasurement(lengthRevision.development.patterns[0], 'bodyLength')).toBeCloseTo(0.74, 6);
  for (const pom of POMS.filter(item => item.id !== 'bodyLength')) expect(lengthRevision.development.sizeSet.sizes[0].specification.values[pom.id]).toBe(originalSize.specification.values[pom.id]);

  await page.getByRole('tab', { name: 'Size chart & grading', exact: true }).click();
  await page.getByLabel('New size label', { exact: true }).fill('Roomy');
  await page.getByRole('button', { name: 'Add size', exact: true }).click();
  await expect(page.getByRole('combobox', { name: 'Preview size', exact: true })).toHaveValue(await page.getByRole('combobox', { name: 'Preview size', exact: true }).locator('option').filter({ hasText: 'Roomy' }).getAttribute('value') as string);
  await page.getByRole('spinbutton', { name: 'Grade Chest width (cm)', exact: true }).fill('2');
  await expect(page.getByRole('spinbutton', { name: 'Grade Body length (cm)', exact: true })).toHaveValue('0');
  await page.getByRole('tab', { name: 'Compare & history', exact: true }).click();
  await page.getByRole('button', { name: 'Compare another size', exact: true }).click();
  await expect(page.locator('.compared-pattern')).not.toHaveCount(0);
  await expect(page.getByText(/Wireframe: compared revision/)).toBeVisible();
  const chestComparison = page.locator('.comparison-table tbody tr').filter({ has: page.getByRole('rowheader', { name: 'Chest width', exact: true }) });
  await expect(chestComparison.locator('td').last()).toHaveText('+2.000');
  await page.getByRole('button', { name: 'Side', exact: true }).click();
  await page.getByRole('combobox', { name: 'Fitting model', exact: true }).selectOption({ label: 'Fit Model B' });
  await expect(page.getByRole('button', { name: 'Side', exact: true })).toHaveAttribute('aria-pressed', 'true');
  const desktopViewport = page.viewportSize()!;
  for (const viewport of [{ width: 1024, height: 768 }, desktopViewport]) {
    await page.setViewportSize(viewport);
    await expect.poll(async () => page.locator('canvas').evaluate(canvas => {
      const surface = canvas.parentElement!;
      return Math.max(Math.abs(canvas.clientWidth - surface.clientWidth), Math.abs(canvas.clientHeight - surface.clientHeight));
    })).toBeLessThanOrEqual(1);
    await expect(page.getByRole('button', { name: 'Side', exact: true })).toHaveAttribute('aria-pressed', 'true');
  }
  await page.getByRole('button', { name: 'Save project', exact: true }).click();
  await expect(page.getByText('Saved locally', { exact: true })).toBeVisible();
  const graded = await packageFromPage(page);
  const gradedRevision = parametric(graded.document);
  const roomy = gradedRevision.development.sizeSet.sizes.find(item => item.label === 'Roomy')!;
  const roomyPattern = gradedRevision.development.patterns.find(item => item.sizeId === roomy.id)!;
  expect(roomy.specification.values.bodyLength).toBeCloseTo(0.74, 8);
  expect(endpointMeasurement(roomyPattern, 'bodyLength')).toBeCloseTo(0.74, 6);
  expect(endpointMeasurement(roomyPattern, 'chestWidth')).toBeCloseTo(originalSize.specification.values.chestWidth + 0.02, 6);
  expect(graded.document.fitModels.find(item => item.id === graded.document.project.selectedFitModelRevisionId)!.name).toBe('Fit Model B');
  expect(gradedRevision.development.sizeSet.gradeRules.find(rule => rule.toSizeId === roomy.id)!.deltasM.bodyLength).toBe(0);
  await page.screenshot({ path: testInfo.outputPath('graded-comparison.png'), fullPage: true });

  await page.getByRole('combobox', { name: 'Compare revision', exact: true }).selectOption(originalRevision.id);
  await page.getByRole('button', { name: 'Restore compared design as new revision', exact: true }).click();
  await page.getByRole('button', { name: 'Save and continue', exact: true }).click();
  await page.getByRole('tab', { name: 'Measurements', exact: true }).click();
  await expect(page.getByRole('spinbutton', { name: 'Body length (cm)', exact: true })).toHaveValue(String(originalSize.specification.values.bodyLength * 100));
  await page.getByRole('combobox', { name: 'Display units', exact: true }).selectOption('in');
  await expect(page.getByRole('spinbutton', { name: 'Body length (in)', exact: true })).toHaveValue(/27\.559/);
  await page.getByRole('button', { name: 'Save project', exact: true }).click();
  await expect(page.getByText('Saved locally', { exact: true })).toBeVisible();
  const restored = await packageFromPage(page);
  const restoredRevision = parametric(restored.document);
  expect(restoredRevision.id).not.toBe(originalRevision.id);
  expect(restoredRevision.parentRevisionId).toBe(gradedRevision.id);
  expect(restoredRevision.restoredFromRevisionId).toBe(originalRevision.id);
  expect(restoredRevision.development.sizeSet.sizes.map(item => item.specification.values)).toEqual(originalRevision.development.sizeSet.sizes.map(item => item.specification.values));
  expect(restored.document.revisions.slice(0, graded.document.revisions.length)).toEqual(graded.document.revisions);
  expect(errors).toEqual([]);
  await page.close();

  const reopened = await context.newPage();
  await reopened.goto('/');
  await reopened.getByRole('button', { name: /Eternal garment development.*Open/ }).click();
  await expect(reopened.getByRole('combobox', { name: 'Display units', exact: true })).toHaveValue('in');
  await expect(reopened.getByRole('spinbutton', { name: 'Body length (in)', exact: true })).toHaveValue(/27\.559/);
  await importPackage(reopened, restored.bytes);
  await expect(reopened.getByText(/Imported as a separate project/)).toBeVisible();
  const imported = await packageFromPage(reopened);
  expect(imported.document.project.id).not.toBe(restored.document.project.id);
  expect(imported.document.revisions).toEqual(restored.document.revisions);
  expect(imported.document.assets).toEqual(restored.document.assets);
  expect(imported.document.project.selectedFitModelRevisionId).toBe(restored.document.project.selectedFitModelRevisionId);
  expect(imported.document.project.selectedSizeId).toBe(restored.document.project.selectedSizeId);
  await reopened.getByRole('tab', { name: 'Specification exports', exact: true }).click();
  const csv = (await download(reopened, 'Export specification CSV')).toString('utf8');
  expect(csv).toContain(restoredRevision.id);
  expect(csv).toContain('bodyLength');
  expect(csv).toContain('in');
  expect(csv).toContain('provisional');
});

test('Goal 2 packages upgrade explicitly and both legacy and parametric designs remain restorable', async ({ page }) => {
  await createDesign(page, 'Legacy continuity', 'legacy');
  const original = await packageFromPage(page);
  expect(original.document.schemaVersion).toBe(1);
  expect(current(original.document).schemaVersion).toBe(1);
  await page.getByRole('button', { name: 'Upgrade to parametric T-shirt', exact: true }).click();
  await expect(page.getByText(/Parametric revision saved with explicitly authored defaults/)).toBeVisible();
  const upgraded = await packageFromPage(page);
  expect(upgraded.document.schemaVersion).toBe(2);
  expect(upgraded.document.revisions[0]).toEqual(original.document.revisions[0]);
  expect(upgraded.document.assets).toEqual(original.document.assets);
  const upgradedRevision = parametric(upgraded.document);
  await page.getByRole('tab', { name: 'Compare & history', exact: true }).click();
  await page.getByRole('combobox', { name: 'Compare revision', exact: true }).selectOption(current(original.document).id);
  await expect(page.locator('.comparison-table')).toHaveCount(0);
  await page.getByRole('button', { name: 'Restore compared design as new revision', exact: true }).click();
  await page.getByRole('button', { name: 'Save and continue', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Upgrade to parametric T-shirt', exact: true })).toBeVisible();
  await page.getByRole('combobox', { name: 'Historical design', exact: true }).selectOption(upgradedRevision.id);
  await page.getByRole('button', { name: 'Restore selected design as new revision', exact: true }).click();
  await page.getByRole('button', { name: 'Save and continue', exact: true }).click();
  await expect(page.getByRole('tab', { name: 'Measurements', exact: true })).toBeVisible();
  const restored = await packageFromPage(page);
  expect(restored.document.revisions.slice(0, upgraded.document.revisions.length)).toEqual(upgraded.document.revisions);
  expect(parametric(restored.document).restoredFromRevisionId).toBe(upgradedRevision.id);
});

test('invalid dimensions and grade outputs retain valid geometry and the prior acknowledged save', async ({ page }) => {
  await createDesign(page, 'Bounded dimensions');
  await page.getByRole('combobox', { name: '2D representation', exact: true }).selectOption('piece-front');
  await page.getByRole('button', { name: 'Save project', exact: true }).click();
  await expect(page.getByText('Saved locally', { exact: true })).toBeVisible();
  const before = await packageFromPage(page);
  const path = page.locator('g.current-pattern[data-piece-id="front"] path[data-boundary="seam"]');
  const drawing = (await path.getAttribute('d'))!;
  await page.getByRole('spinbutton', { name: 'Body length (cm)', exact: true }).fill('0');
  await expect(page.locator('.geometry-error')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Save project', exact: true })).toBeDisabled();
  await expect(path).toHaveAttribute('d', drawing);
  page.once('dialog', dialog => void dialog.accept());
  await page.reload();
  await page.getByRole('button', { name: /Bounded dimensions.*Open/ }).click();
  const afterInvalid = await packageFromPage(page);
  expect(afterInvalid.document.revisions).toEqual(before.document.revisions);
  await page.getByRole('tab', { name: 'Size chart & grading', exact: true }).click();
  await page.getByLabel('New size label', { exact: true }).fill('Roomy');
  await page.getByRole('button', { name: 'Add size', exact: true }).click();
  await page.getByRole('spinbutton', { name: 'Grade Chest width (cm)', exact: true }).fill('-100');
  await expect(page.locator('.geometry-error')).toContainText('Grade Chest width');
  await expect(page.getByRole('button', { name: 'Save project', exact: true })).toBeDisabled();
  page.once('dialog', dialog => void dialog.accept());
  await page.reload();
  await page.getByRole('button', { name: /Bounded dimensions.*Open/ }).click();
  const recovered = await packageFromPage(page);
  expect(recovered.document.revisions).toEqual(before.document.revisions);
});

test('specification JSON and physical-scale vector files export actual supported records', async ({ page }) => {
  await createDesign(page, 'Preliminary exports');
  await page.getByRole('spinbutton', { name: 'Body length (cm)', exact: true }).fill('74');
  await page.getByRole('button', { name: 'Save project', exact: true }).click();
  await expect(page.getByText('Saved locally', { exact: true })).toBeVisible();
  const saved = await packageFromPage(page);
  const revision = parametric(saved.document);
  await page.getByRole('tab', { name: 'Specification exports', exact: true }).click();
  const json = JSON.parse((await download(page, 'Export specification JSON')).toString('utf8')) as unknown;
  const records: Record<string, unknown>[] = [];
  function visit(value: unknown) {
    if (!value || typeof value !== 'object') return;
    if (Array.isArray(value)) { for (const item of value) visit(item); return; }
    const record = value as Record<string, unknown>; records.push(record);
    for (const item of Object.values(record)) visit(item);
  }
  visit(json);
  for (const size of revision.development.sizeSet.sizes) expect(records.some(record => record.id === size.specification.id && JSON.stringify(record.values) === JSON.stringify(size.specification.values))).toBe(true);
  expect(JSON.stringify(json)).toContain(revision.id);
  const svgText = (await download(page, 'Export pattern SVG')).toString('utf8');
  const vector = await page.evaluate(text => {
    const xml = new DOMParser().parseFromString(text, 'image/svg+xml');
    const root = xml.documentElement;
    return { errors: xml.querySelectorAll('parsererror').length, name: root.localName, width: root.getAttribute('width'), height: root.getAttribute('height'), viewBox: root.getAttribute('viewBox'), paths: [...root.querySelectorAll('path')].map(path => path.getAttribute('d')), scripts: root.querySelectorAll('script,foreignObject,image,use').length, text: root.textContent };
  }, svgText);
  expect(vector.errors).toBe(0); expect(vector.name).toBe('svg');
  expect(vector.width).toMatch(/[0-9](mm|cm|m)$/); expect(vector.height).toMatch(/[0-9](mm|cm|m)$/);
  expect(vector.viewBox).toBeTruthy(); expect(vector.paths.filter(Boolean).length).toBeGreaterThanOrEqual(5);
  expect(vector.scripts).toBe(0); expect(svgText).toContain(revision.id);
  expect(endpointMeasurement(revision.development.patterns[0], 'bodyLength')).toBeCloseTo(0.74, 6);
});
