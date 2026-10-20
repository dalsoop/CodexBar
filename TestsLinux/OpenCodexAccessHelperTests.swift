import Foundation
import Testing
@testable import CodexBarCore

struct OpenCodexAccessHelperTests {
    @Test func `OpenCodexAccess helper uses exact id patch and contains package runtime and output`() async throws {
        let node = try #require(ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":")
            .map { String($0) + "/node" }.first { FileManager.default.isExecutableFile(atPath: $0) })
        let helper = try #require(OpenCodexAccessRenameInstallation.helperURL)
        let script = #"""
        import { mkdtempSync, mkdirSync, writeFileSync, chmodSync, linkSync, symlinkSync, rmSync } from 'node:fs';
        import { tmpdir } from 'node:os';
        import { join, dirname } from 'node:path';
        import { execFileSync } from 'node:child_process';
        import { pathToFileURL } from 'node:url';
        import assert from 'node:assert/strict';
        const helper = process.argv[2];
        const { renameOnce } = await import(pathToFileURL(helper));
        const root = mkdtempSync(join(tmpdir(), 'access-fake-package-'));
        const createdAt = '2026-10-20T01:02:03Z';
        function fixture(mode) {
          const pkg = join(root, mode);
          mkdirSync(join(pkg, 'bin'), { recursive: true });
          mkdirSync(join(pkg, 'src/cli'), { recursive: true });
          mkdirSync(join(pkg, 'node_modules/bun/bin'), { recursive: true });
          const cli = join(pkg, 'bin/ocx.mjs');
          const runtime = join(pkg, 'node_modules/bun/bin/bun.exe');
          writeFileSync(cli, 'CLI MUST NOT EXECUTE'); chmodSync(cli, 0o755);
          linkSync(process.execPath, runtime);
          writeFileSync(join(pkg, 'package.json'), JSON.stringify({ name: '@bitkyc08/opencodex', version: '2.88.0',
            type: 'module', bin: { ocx: './bin/ocx.mjs' }, dependencies: { bun: '1.4.2' } }));
          writeFileSync(join(pkg, 'node_modules/bun/package.json'), JSON.stringify({ name: 'bun', version: '1.4.2' }));
          const source = `
            console.log('synthetic-module-secret'); console.error('synthetic-module-secret');
            export async function runtimeBaseUrl() { return 'http://localhost:4321'; }
            globalThis.fetch = async (url, init) => {
              if (url !== 'http://localhost:4321/api/keys' || init.method !== 'PATCH' || init.redirect !== 'error'
                || init.credentials !== 'omit' || init.body !== JSON.stringify({ id: 'gone-id', name: 'new' })) throw Error('synthetic-secret');
              // The selected id disappeared, while another key now has that id as its name.
              const rows = [{ id: 'another', name: 'gone-id', allowedModels: ['kept'] }];
              if ('${mode}' === 'gone') {
                const target = rows.find(row => row.id === JSON.parse(init.body).id);
                if (target || rows[0].name !== 'gone-id' || rows[0].allowedModels[0] !== 'kept') throw Error('wrong key changed');
                return new Response(JSON.stringify({ error: 'synthetic-secret' }), { status: 404 });
              }
              if ('${mode}' === 'denied') return new Response('synthetic-secret', { status: 403 });
              if ('${mode}' === 'redirect') return new Response('synthetic-secret', { status: 302, headers: { location: 'https://evil.invalid' } });
              if ('${mode}' === 'large') return new Response('x'.repeat(262145));
              if ('${mode}' === 'throw') throw Error('synthetic-secret');
              return new Response(JSON.stringify({ id: '${mode}' === 'wrong' ? 'another' : 'gone-id', name: 'new',
                createdAt: '${createdAt}', allowedProviders: ['claude'], allowedModels: ['model'], key: 'synthetic-secret' }));
            };
            export async function runtimeRequest(path, init, deps) {
              if (path !== '/api/keys' || deps.baseUrl !== 'http://localhost:4321') throw Error('synthetic-secret');
              const response = await deps.fetchImpl(deps.baseUrl + path, init);
              if (!response.ok) throw { status: response.status, body: 'synthetic-secret' };
              return response.json();
            }
          `;
          writeFileSync(join(pkg, 'src/cli/runtime-api.ts'), source);
          return { cli, runtime, pkg };
        }
        function run(f, input = JSON.stringify({ id: 'gone-id', name: 'new' })) {
          const output = execFileSync(f.runtime, [helper, f.cli], { input, encoding: 'utf8',
            env: { PATH: process.env.PATH, HOME: root, NODE_NO_WARNINGS: '1',
                DYLD_LIBRARY_PATH: join(dirname(process.execPath), '../lib') } });
          assert(!output.includes('synthetic-secret') && !output.includes('synthetic-module-secret'));
          return JSON.parse(output);
        }
        try {
          assert.deepEqual(run(fixture('success')), { id: 'gone-id', name: 'new', createdAt,
            allowedProviders: ['claude'], allowedModels: ['model'] });
          assert.deepEqual(run(fixture('gone')), { error: 'not_found' });
          assert.deepEqual(run(fixture('denied')), { error: 'permission_denied' });
          for (const mode of ['wrong', 'redirect', 'throw', 'large']) {
            assert.deepEqual(run(fixture(mode)), { error: 'confirmation_required' });
          }
          const valid = fixture('input');
          for (const input of ['{}', '{', JSON.stringify({ id: 'x', name: 'new', url: 'http://evil.invalid' }),
            JSON.stringify({ id: '', name: 'new' }), JSON.stringify({ id: 'x', name: '\nnew' }),
            JSON.stringify({ id: 'x', name: '--json' }), 'x'.repeat(4097)]) {
            assert.deepEqual(run(valid, input), { error: 'invalid_input' });
          }
          for (const [mode, relative] of [['missing-module','src/cli/runtime-api.ts'],
            ['missing-runtime','node_modules/bun/bin/bun.exe'], ['missing-package','package.json']]) {
            const f = fixture(mode); rmSync(join(f.pkg, relative));
            // missing runtime cannot launch; exercise exported validation with a synthetic runtime path.
            assert.deepEqual(await renameOnce(f.cli, f.runtime, '{"id":"x","name":"new"}'), { error: 'unsupported_installation' });
          }
          const wrong = fixture('wrong-package');
          writeFileSync(join(wrong.pkg, 'package.json'), '{"name":"other","version":"2.88.0"}');
          assert.deepEqual(run(wrong), { error: 'unsupported_installation' });
          const version = fixture('wrong-version');
          writeFileSync(join(version.pkg, 'package.json'), '{"name":"@bitkyc08/opencodex","version":"2.89.0"}');
          assert.deepEqual(run(version), { error: 'unsupported_installation' });
          const escape = fixture('escape');
          rmSync(join(escape.pkg, 'src/cli/runtime-api.ts'));
          symlinkSync(join(valid.pkg, 'src/cli/runtime-api.ts'), join(escape.pkg, 'src/cli/runtime-api.ts'));
          assert.deepEqual(run(escape), { error: 'unsupported_installation' });
          const noContract = fixture('no-contract');
          writeFileSync(join(noContract.pkg, 'src/cli/runtime-api.ts'), 'export function runtimeRequest() {}');
          assert.deepEqual(run(noContract), { error: 'unsupported_installation' });
          const noRequest = fixture('no-request');
          writeFileSync(join(noRequest.pkg, 'src/cli/runtime-api.ts'), 'export function runtimeBaseUrl() {}');
          assert.deepEqual(run(noRequest), { error: 'unsupported_installation' });
          console.log('OpenCodexAccess fake helper checks passed');
        } finally { rmSync(root, { recursive: true, force: true }); }
        """#
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let driver = directory.appendingPathComponent("fake-helper-tests.mjs")
        try script.write(to: driver, atomically: true, encoding: .utf8)
        let result = try await SubprocessRunner.run(
            binary: node, arguments: [driver.path, helper.path],
            environment: ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? "", "NODE_NO_WARNINGS": "1"],
            timeout: 30, maxOutputBytes: 262_144, label: "OpenCodexAccess fake helper")
        #expect(result.stdout.contains("fake helper checks passed"))
        #expect(result.stderr.isEmpty)
    }
}
