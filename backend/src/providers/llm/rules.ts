import type { LlmExtractInput, LlmExtractResult, LlmProvider } from '../types.js';
import { parseCommand } from '../../modules/assistant/rulesParser.js';

/** Deterministic Hinglish/English rule parser — zero cost, works offline, used as fast path and in tests. */
export class RulesLlmProvider implements LlmProvider {
  readonly name = 'rules';
  async extract(input: LlmExtractInput): Promise<LlmExtractResult> {
    const r = parseCommand(input.text, { today: input.context.today, employeeNames: input.context.employeeNames, role: input.context.role });
    return { ...r, provider: this.name };
  }
}
