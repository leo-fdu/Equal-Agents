export default function (pi: any) {
  pi.registerTool({
    name: 'meeting_sources', label: 'Meeting sources',
    description: 'Search public web, fetch a URL, list sources, or read_source by ID and offset. All retrieved results are archived automatically when sharing is enabled. Read original passages before relying on them.',
    parameters: { type: 'object', properties: {
      action: { type: 'string', enum: ['search', 'fetch', 'sources', 'read_source'] },
      query: { type: 'string' }, url: { type: 'string' }, id: { type: 'string' }, offset: { type: 'integer' }
    }, required: ['action'], additionalProperties: false },
    async execute(_id: string, args: any, signal: AbortSignal) {
      const response = await fetch(process.env.EQUAL_AGENTS_TOOL_URL!, {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + process.env.EQUAL_AGENTS_TOOL_TOKEN! }, body: JSON.stringify(args), signal
      });
      const data = await response.json(); if (!response.ok) throw Error(data.error || 'Source tool failed');
      return { content: [{ type: 'text', text: JSON.stringify(data) }], details: {} };
    }
  });
}
