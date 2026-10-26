import fs from 'node:fs';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { InMemoryTransport } from '@modelcontextprotocol/sdk/inMemory.js';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { registerDiscoveryTools } from '../dist/graph-tools.js';
import { installToolSchemaRefNormalization } from '../dist/normalize-tool-schema.js';
const eagerTools = JSON.parse(fs.readFileSync('ci/eager-tools.json'));
const server = new McpServer({ name: 'ci-surface', version: '1' });
registerDiscoveryTools(server, {}, { orgMode: true, httpMode: true, eagerTools });
installToolSchemaRefNormalization(server);
const [a, b] = InMemoryTransport.createLinkedPair();
await server.connect(a);
const client = new Client({ name: 'ci-check', version: '1' });
await client.connect(b);
const tools = (await client.listTools()).tools;
const names = new Set(tools.map((t) => t.name));
if (names.size !== eagerTools.length + 3 || !eagerTools.every((n) => names.has(n)))
  throw new Error('Unexpected hybrid tool surface');
const bytes = Buffer.byteLength(JSON.stringify(tools));
if (bytes > 400000)
  throw new Error(`Hybrid schemas exceed the 400,000 byte deployment budget: ${bytes}`);
console.log(`Verified ${tools.length} tools; ${bytes} schema bytes`);
await client.close();
await server.close();
