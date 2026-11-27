import { test, expect } from '@playwright/test';
import type { Page } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import type { ProjectPackage } from '../src/domain/types';

async function createProject(page: Page, name = 'Eternal — everyday tee') {
  await page.goto('/');
  await page.getByLabel('Project name', { exact: true }).fill(name);
  await page.getByLabel('Garment name', { exact: true }).fill('Everyday tee');
  await page.getByRole('combobox', { name: 'Template', exact: true }).selectOption('legacy');
  await page.getByRole('button', { name: 'Create project', exact: true }).click();
  await expect(page.getByRole('heading', { level: 1, name })).toBeVisible();
  await expect(page.getByText('Saved locally', { exact: true })).toBeVisible();
}

async function captureCanvas(page: Page): Promise<Buffer> {
  await page.evaluate(() => {
    const { promise, resolve } = Promise.withResolvers<void>();
    requestAnimationFrame(() => requestAnimationFrame(() => resolve()));
    return promise;
  });
  return page.locator('canvas').screenshot();
}

async function pixelDifference(page: Page, first: Buffer, second: Buffer): Promise<number> {
  return page.evaluate(async ({ a, b }) => {
    const pixels = async (source: string) => {
      const image = new Image();
      image.src = `data:image/png;base64,${source}`;
      await image.decode();
      const surface = new OffscreenCanvas(image.width, image.height);
      const context = surface.getContext('2d')!;
      context.drawImage(image, 0, 0);
      return context.getImageData(0, 0, image.width, image.height).data;
    };
    const x = await pixels(a), y = await pixels(b);
    if (x.length !== y.length) throw new Error('Canvas dimensions changed during comparison');
    let changed = 0;
    for (let index = 0; index < x.length; index += 4) {
      if (Math.max(Math.abs(x[index] - y[index]), Math.abs(x[index + 1] - y[index + 1]), Math.abs(x[index + 2] - y[index + 2])) > 12) changed++;
    }
    return changed / (x.length / 4);
  }, { a: first.toString('base64'), b: second.toString('base64') });
}

async function downloadPackage(page: Page): Promise<{ bytes: Buffer; document: ProjectPackage }> {
  const downloadEvent = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Export package', exact: true }).click();
  const download = await downloadEvent;
  const bytes = await readFile((await download.path())!);
  return { bytes, document: JSON.parse(bytes.toString('utf8')) as ProjectPackage };
}

async function importBytes(page: Page, bytes: Buffer) {
  const chooserEvent = page.waitForEvent('filechooser');
  await page.getByRole('button', { name: 'Import project', exact: true }).click();
  await (await chooserEvent).setFiles({ name: 'project.onyou.json', mimeType: 'application/json', buffer: bytes });
}

test('real geometry, camera, appearance, local reopen and portable package round-trip', async ({ page, context }, testInfo) => {
  const errors: string[] = [];
  page.on('pageerror', error => errors.push(error.message));
  await createProject(page);
  await expect(page.getByRole('heading', { name: '2D garment', exact: true })).toBeVisible();
  await expect(page.locator('canvas')).toBeVisible();
  const initialRevision = await page.locator('.revision-line code').innerText();
  const originalCanvas = await page.locator('canvas').elementHandle();
  const modelA = await captureCanvas(page);
  const framing = await page.evaluate(async imageBase64 => {
    const image = new Image();
    image.src = `data:image/png;base64,${imageBase64}`;
    await image.decode();
    const surface = new OffscreenCanvas(image.width, image.height);
    const context = surface.getContext('2d')!;
    context.drawImage(image, 0, 0);
    const pixels = context.getImageData(0, 0, image.width, image.height).data;
    const background = (4 * image.width + 4) * 4;
    let minimumX = image.width, minimumY = image.height, maximumX = -1, maximumY = -1;
    // Exclude fractional screenshot-edge antialiasing, not any garment/model pixels.
    for (let y = 2; y < image.height - 2; y++) for (let x = 2; x < image.width - 2; x++) {
      const offset = (y * image.width + x) * 4;
      if (Math.max(Math.abs(pixels[offset] - pixels[background]), Math.abs(pixels[offset + 1] - pixels[background + 1]), Math.abs(pixels[offset + 2] - pixels[background + 2])) > 12) {
        minimumX = Math.min(minimumX, x); maximumX = Math.max(maximumX, x);
        minimumY = Math.min(minimumY, y); maximumY = Math.max(maximumY, y);
      }
    }
    return { minimumX, minimumY, maximumX, maximumY, width: image.width, height: image.height };
  }, modelA.toString('base64'));
  expect(framing.minimumX).toBeGreaterThan(8);
  expect(framing.minimumY).toBeGreaterThan(8);
  expect(framing.maximumX).toBeLessThan(framing.width - 8);
  expect(framing.maximumY).toBeLessThan(framing.height - 8);
  expect(framing.maximumY - framing.minimumY).toBeGreaterThan(framing.height / 3);
  await page.getByLabel('Fitting model', { exact: true }).selectOption({ label: 'Fit Model B' });
  const modelB = await captureCanvas(page);
  expect(await pixelDifference(page, modelA, modelB)).toBeGreaterThan(0.01);
  expect(await originalCanvas!.evaluate(node => node === document.querySelector('canvas'))).toBe(true);
  await page.getByRole('button', { name: 'Save project', exact: true }).click();
  await expect(page.getByText('Saved locally', { exact: true })).toBeVisible();
  await expect(page.locator('.revision-line code')).toHaveText(initialRevision);

  await page.getByRole('button', { name: 'Moss', exact: true }).click();
  await expect(page.locator('svg polygon')).toHaveAttribute('fill', '#677361');
  const moss = await captureCanvas(page);
  expect(await pixelDifference(page, modelB, moss)).toBeGreaterThan(0.005);
  expect(await originalCanvas!.evaluate(node => node === document.querySelector('canvas'))).toBe(true);
  await page.getByRole('button', { name: 'Side', exact: true }).click();
  const side = await captureCanvas(page);
  expect(await pixelDifference(page, moss, side)).toBeGreaterThan(0.03);
  await page.getByRole('button', { name: 'Back', exact: true }).click();
  expect(await pixelDifference(page, side, await captureCanvas(page))).toBeGreaterThan(0.03);
  await page.getByRole('button', { name: 'Front', exact: true }).focus();
  await page.keyboard.press('Space');
  const front = await captureCanvas(page);
  const bounds = (await page.locator('canvas').boundingBox())!;
  await page.mouse.move(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);
  await page.mouse.down();
  await page.mouse.move(bounds.x + bounds.width / 2 + 90, bounds.y + bounds.height / 2 + 20, { steps: 6 });
  await page.mouse.up();
  expect(await pixelDifference(page, front, await captureCanvas(page))).toBeGreaterThan(0.01);
  await page.getByRole('button', { name: 'Reset', exact: true }).click();
  const reset = await captureCanvas(page);
  await page.mouse.move(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);
  await page.mouse.wheel(0, -250);
  expect(await pixelDifference(page, reset, await captureCanvas(page))).toBeGreaterThan(0.01);
  await page.getByRole('button', { name: 'Reset', exact: true }).click();
  const keyboardFront = await captureCanvas(page);
  await page.locator('canvas').focus();
  await page.keyboard.press('ArrowLeft');
  await page.keyboard.press('ArrowUp');
  await page.keyboard.press('+');
  expect(await pixelDifference(page, keyboardFront, await captureCanvas(page))).toBeGreaterThan(0.005);
  await page.keyboard.press('Home');
  await page.getByLabel('Garment name', { exact: true }).fill('Everyday tee — moss');
  await page.getByRole('button', { name: 'Save project', exact: true }).click();
  await expect(page.getByText('Saved locally', { exact: true })).toBeVisible();
  const savedRevision = await page.locator('.revision-line code').innerText();
  expect(savedRevision).not.toBe(initialRevision);
  await page.screenshot({ path: testInfo.outputPath('studio-workspace.png'), fullPage: true });
  const original = await downloadPackage(page);
  expect(original.document.assets).toHaveLength(6);
  const selected = original.document.fitModels.find(model => model.id === original.document.project.selectedFitModelRevisionId)!;
  expect(selected.name).toBe('Fit Model B');
  expect(original.document.revisions.at(-1)!.visualMaterial.color).toBe('#677361');
  expect(errors).toEqual([]);
  await page.close();

  const reopened = await context.newPage();
  await reopened.goto('/');
  await reopened.getByRole('button', { name: /Eternal — everyday tee.*Open/ }).click();
  await expect(reopened.getByLabel('Fitting model', { exact: true })).toHaveValue(selected.id);
  await expect(reopened.getByLabel('Garment name', { exact: true })).toHaveValue('Everyday tee — moss');
  await expect(reopened.locator('svg polygon')).toHaveAttribute('fill', '#677361');
  await expect(reopened.locator('.revision-line code')).toHaveText(savedRevision);
  await importBytes(reopened, original.bytes);
  await expect(reopened.getByText(/Imported as a separate project/)).toBeVisible();
  await expect(reopened.locator('.revision-line code')).toHaveText(savedRevision);
  const imported = await downloadPackage(reopened);
  expect(imported.document.project.id).not.toBe(original.document.project.id);
  expect(imported.document.project.importedFrom).toEqual({ projectId: original.document.project.id, projectRevisionId: original.document.project.revisionId });
  expect(imported.document.revisions).toEqual(original.document.revisions);
  expect(imported.document.assets).toEqual(original.document.assets);
  await reopened.getByRole('button', { name: 'Projects', exact: true }).click();
  await expect(reopened.locator('.project-row')).toHaveCount(2);
});

test('invalid packages cannot replace a saved project or request external assets', async ({ page }) => {
  await createProject(page, 'Protected original');
  const original = await downloadPackage(page);
  const externalRequests: string[] = [];
  page.on('request', request => { if (new URL(request.url()).origin !== new URL(page.url()).origin) externalRequests.push(request.url()); });
  const wrongVersion = structuredClone(original.document);
  Object.assign(wrongVersion, { schemaVersion: 999 });
  await importBytes(page, Buffer.from(JSON.stringify(wrongVersion)));
  await expect(page.locator('.message-bar.error')).toBeVisible();
  const corrupt = structuredClone(original.document);
  corrupt.assets[0].data += ' ';
  await importBytes(page, Buffer.from(JSON.stringify(corrupt)));
  await expect(page.locator('.message-bar.error')).toBeVisible();
  const external = structuredClone(original.document);
  Object.assign(external.meshAssets[0], { url: 'https://untrusted.example/model.glb' });
  await importBytes(page, Buffer.from(JSON.stringify(external)));
  await expect(page.locator('.message-bar.error')).toBeVisible();
  await importBytes(page, Buffer.alloc(12 * 1024 * 1024 + 1, 32));
  await expect(page.locator('.message-bar.error')).toBeVisible();
  await expect(page.getByRole('heading', { level: 1, name: 'Protected original' })).toBeVisible();
  const after = await downloadPackage(page);
  expect(after.document.project).toEqual(original.document.project);
  expect(after.document.revisions).toEqual(original.document.revisions);
  expect(externalRequests).toEqual([]);
  await page.getByRole('button', { name: 'Projects', exact: true }).click();
  await expect(page.locator('.project-row')).toHaveCount(1);
});

test('a real IndexedDB write failure preserves the acknowledged save and allows retry', async ({ page }) => {
  await createProject(page, 'Storage recovery');
  const before = await downloadPackage(page);
  const savedColor = before.document.revisions.at(-1)!.visualMaterial.color;
  await page.getByRole('button', { name: 'Clay', exact: true }).click();
  // Fault injection only: fail the next real write; no fake successful storage or app-state writes.
  await page.evaluate(() => {
    const put = IDBObjectStore.prototype.put;
    IDBObjectStore.prototype.put = function (...args: Parameters<IDBObjectStore['put']>) {
      IDBObjectStore.prototype.put = put;
      throw new DOMException('Deliberate browser storage quota fault', 'QuotaExceededError');
    };
  });
  await page.getByRole('button', { name: 'Save project', exact: true }).click();
  await expect(page.locator('.message-bar.error')).toBeVisible();
  await expect(page.getByText('Unsaved changes', { exact: true })).toBeVisible();
  page.once('dialog', dialog => void dialog.accept());
  await page.reload();
  await page.getByRole('button', { name: /Storage recovery.*Open/ }).click();
  await expect(page.locator('svg polygon')).toHaveAttribute('fill', savedColor);
  const recovered = await downloadPackage(page);
  expect(recovered.document.project).toEqual(before.document.project);
  expect(recovered.document.revisions).toEqual(before.document.revisions);
  await page.getByRole('button', { name: 'Clay', exact: true }).click();
  await page.getByRole('button', { name: 'Save project', exact: true }).click();
  await expect(page.getByText('Saved locally', { exact: true })).toBeVisible();
  const retried = await downloadPackage(page);
  expect(retried.document.revisions.at(-1)!.visualMaterial.color).toBe('#a56954');
});

test('unsaved navigation, project switching and smaller desktop layout remain usable', async ({ page }) => {
  await page.setViewportSize({ width: 1000, height: 900 });
  await createProject(page, 'First project');
  await page.getByLabel('Garment name', { exact: true }).fill('');
  await expect(page.locator('canvas')).toBeVisible();
  await expect(page.locator('.viewer-surface [role="alert"]')).toHaveCount(0);
  await page.getByLabel('Garment name', { exact: true }).fill('Uncommitted tee');
  await page.getByRole('button', { name: 'Projects', exact: true }).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog')).not.toBeVisible();
  await expect(page.getByLabel('Garment name', { exact: true })).toHaveValue('Uncommitted tee');
  await page.getByRole('button', { name: 'New project', exact: true }).click();
  await page.getByRole('button', { name: 'Save and continue', exact: true }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'Projects' })).toBeVisible();
  await page.getByLabel('Project name', { exact: true }).fill('Second project');
  await page.getByRole('button', { name: 'Create project', exact: true }).click();
  await expect(page.getByRole('heading', { level: 1, name: 'Second project' })).toBeVisible();
  await page.getByLabel('Switch project', { exact: true }).selectOption({ label: await page.getByLabel('Switch project', { exact: true }).locator('option').filter({ hasText: 'First project' }).innerText() });
  await expect(page.getByRole('heading', { level: 1, name: 'First project' })).toBeVisible();
  await expect(page.getByLabel('Garment name', { exact: true })).toHaveValue('Uncommitted tee');
  await page.getByRole('button', { name: '2D', exact: true }).click();
  await expect(page.locator('canvas')).toHaveCount(0);
  await expect(page.getByRole('img')).toBeVisible();
  await page.getByRole('button', { name: '3D', exact: true }).click();
  await expect(page.locator('canvas')).toBeVisible();
  await page.getByRole('button', { name: 'Save project', exact: true }).click();
  await expect(page.getByText('Saved locally', { exact: true })).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});

test('unsupported WebGL is explicit while 2D editing, saving and export still work', async ({ page }) => {
  await page.addInitScript(() => {
    const getContext = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function (this: HTMLCanvasElement, id: string, ...args: unknown[]) {
      if (id.includes('webgl')) return null;
      return Reflect.apply(getContext, this, [id, ...args]);
    } as typeof getContext;
  });
  await createProject(page, 'No WebGL');
  await expect(page.getByText(/WebGL.*(unavailable|unsupported|not available|could not)|3D.*(unavailable|unsupported|not available)/i).first()).toBeVisible();
  await page.getByRole('button', { name: 'Ink', exact: true }).click();
  await page.getByRole('button', { name: 'Save project', exact: true }).click();
  await expect(page.getByText('Saved locally', { exact: true })).toBeVisible();
  const exported = await downloadPackage(page);
  expect(exported.document.revisions.at(-1)!.visualMaterial.color).toBe('#273342');
});

test('failed first save leaves an editable draft that can be saved on retry', async ({ page }) => {
  await page.goto('/');
  await page.getByLabel('Project name', { exact: true }).fill('Retry initial save');
  await page.getByLabel('Garment name', { exact: true }).fill('Initial tee');
  await page.getByRole('combobox', { name: 'Template', exact: true }).selectOption('legacy');
  await page.evaluate(() => {
    const put = IDBObjectStore.prototype.put;
    IDBObjectStore.prototype.put = function (...args: Parameters<IDBObjectStore['put']>) {
      IDBObjectStore.prototype.put = put;
      throw new DOMException('Deliberate first-save quota fault', 'QuotaExceededError');
    };
  });
  await page.getByRole('button', { name: 'Create project', exact: true }).click();
  await expect(page.locator('.message-bar.error')).toBeVisible();
  await expect(page.getByText('Unsaved changes', { exact: true })).toBeVisible();
  await page.getByLabel('Garment name', { exact: true }).fill('Recovered draft tee');
  await page.getByRole('button', { name: 'Save project', exact: true }).click();
  await expect(page.getByText('Saved locally', { exact: true })).toBeVisible();
  await page.reload();
  await page.getByRole('button', { name: /Retry initial save.*Open/ }).click();
  await expect(page.getByLabel('Garment name', { exact: true })).toHaveValue('Recovered draft tee');
});
