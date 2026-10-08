import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['dist/**', 'node_modules/**'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    rules: {
      '@typescript-eslint/no-explicit-any': 'off',
      '@typescript-eslint/no-unused-vars': ['warn', { argsIgnorePattern: '^_', varsIgnorePattern: '^_', ignoreRestSiblings: true }],
      // Devanagari ranges (\u0900-\u097f) contain combining marks by design.
      'no-misleading-character-class': 'off',
      'no-restricted-imports': ['error', {
        patterns: [{ group: ['razorpay', 'firebase-admin', '@google/genai', '@aws-sdk/*', 'puppeteer-core'], message: 'Vendor SDKs may only be imported inside src/providers/** adapters.' }],
      }],
    },
  },
  { files: ['src/providers/**'], rules: { 'no-restricted-imports': 'off' } },
);
