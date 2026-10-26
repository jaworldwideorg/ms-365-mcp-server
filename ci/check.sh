#!/usr/bin/env bash
set -euo pipefail
npm ci --no-audit --no-fund
npm run generate > generation.log 2>&1
npm run lint
npm run format:check
npm run typecheck
npm run build
npm test
