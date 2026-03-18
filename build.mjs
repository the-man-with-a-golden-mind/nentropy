import { build } from 'esbuild';

// ESM bundle
await build({
  entryPoints: ['src/Entropy.res.mjs'],
  bundle: true,
  format: 'esm',
  outfile: 'dist/index.mjs',
  target: 'es2020',
  sourcemap: true,
  treeShaking: true,
});

// CJS bundle
await build({
  entryPoints: ['src/Entropy.res.mjs'],
  bundle: true,
  format: 'cjs',
  outfile: 'dist/index.cjs',
  target: 'es2020',
  sourcemap: true,
  treeShaking: true,
});

// IIFE browser bundle (UEntropy global)
await build({
  entryPoints: ['src/Entropy.res.mjs'],
  bundle: true,
  format: 'iife',
  globalName: 'UEntropy',
  outfile: 'dist/entropy.min.js',
  target: 'es2020',
  sourcemap: true,
  minify: true,
  treeShaking: true,
});

console.log('Built: dist/index.mjs, dist/index.cjs, dist/entropy.min.js');
