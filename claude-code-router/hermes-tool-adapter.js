/**
 * Hermes Tool Adapter Transformer
 *
 * Converts local model responses to Claude API tool_use format.
 * This enables local LLMs to work with Claude Code's tool calling system.
 *
 * The transformer:
 * 1. Injects tool definitions into the system prompt
 * 2. Detects JSON tool calls in model responses
 * 3. Converts them to Claude API tool_use format
 */

class HermesToolAdapter {
  name = 'hermes-tool-adapter';

  constructor(options = {}) {
    this.options = {
      debug: true,  // Enable debug for testing
      ...options
    };
    this.toolIdCounter = 0;
    console.log('[hermes-tool-adapter] Transformer initialized');
  }

  log(...args) {
    if (this.options.debug) {
      console.log(`[hermes-tool-adapter] ${args.join(' ')}`);
    }
  }

  generateToolId() {
    this.toolIdCounter++;
    const timestamp = Date.now().toString(36);
    const random = Math.random().toString(36).substring(2, 8);
    return `toolu_${timestamp}${random}${this.toolIdCounter}`;
  }

  // System prompt to instruct model on tool usage format
  getToolInstructionPrompt() {
    return `You have access to tools. When you need to use a tool, output ONLY a JSON object in this exact format:
{"tool_name": "ToolName", "parameters": {...}}

Available tools:
- Read: Read a file. Parameters: {"file_path": "absolute path"}
- Edit: Edit a file. Parameters: {"file_path": "path", "old_string": "text to find", "new_string": "replacement text"}
- Write: Write/create a file. Parameters: {"file_path": "path", "content": "file content"}
- Bash: Run a command. Parameters: {"command": "shell command", "description": "what it does"}
- Glob: Find files by pattern. Parameters: {"pattern": "glob pattern", "path": "optional directory"}
- Grep: Search file contents. Parameters: {"pattern": "regex pattern", "path": "optional directory"}

IMPORTANT:
- Output ONLY the JSON when using a tool, no other text
- Do NOT wrap JSON in markdown code blocks
- Respond directly without thinking out loud (no *asterisk* thoughts)
- Start immediately with either a tool call JSON or your direct response`;
  }

  // Parse potential tool calls from model response
  parseToolCall(text) {
    if (!text || typeof text !== 'string') return null;

    // Clean up the text
    let cleaned = text.trim();

    // Remove markdown code blocks if present
    cleaned = cleaned.replace(/^```(?:json)?\s*\n?/i, '').replace(/\n?```\s*$/i, '');
    cleaned = cleaned.trim();

    // Remove any thinking prefixes
    cleaned = cleaned.replace(/^\*[^*]+\*\s*/g, '');

    // Try to find JSON object
    const jsonMatch = cleaned.match(/\{[\s\S]*\}/);
    if (!jsonMatch) return null;

    try {
      const parsed = JSON.parse(jsonMatch[0]);

      // Check for our expected format
      if (parsed.tool_name && parsed.parameters) {
        return {
          name: parsed.tool_name,
          input: parsed.parameters
        };
      }

      // Check for alternative formats
      if (parsed.tool && parsed.args) {
        return {
          name: parsed.tool,
          input: parsed.args
        };
      }

      if (parsed.function && parsed.arguments) {
        return {
          name: parsed.function,
          input: parsed.arguments
        };
      }

      // Check for tool_call wrapper
      if (parsed.tool_call) {
        const tc = parsed.tool_call;
        return {
          name: tc.type || tc.name || tc.tool_name,
          input: tc.content || tc.parameters || tc.args
        };
      }

      // Check for direct tool name format: {"Bash": {...}} or {"Read": {...}}
      const toolNames = ['Read', 'Edit', 'Write', 'Bash', 'Glob', 'Grep', 'bash', 'read', 'edit', 'write', 'glob', 'grep'];
      const keys = Object.keys(parsed);
      if (keys.length === 1) {
        const key = keys[0];
        if (toolNames.includes(key) && typeof parsed[key] === 'object') {
          return {
            name: key,
            input: parsed[key]
          };
        }
      }

      return null;
    } catch (e) {
      this.log('Failed to parse JSON:', e.message);
      return null;
    }
  }

  // Map local tool names to Claude tool names if needed
  mapToolName(name) {
    const mapping = {
      'file_edit': 'Edit',
      'file_read': 'Read',
      'file_write': 'Write',
      'bash': 'Bash',
      'shell': 'Bash',
      'command': 'Bash',
      'search': 'Grep',
      'find': 'Glob',
      'read': 'Read',
      'edit': 'Edit',
      'write': 'Write',
      'glob': 'Glob',
      'grep': 'Grep'
    };

    const lower = name.toLowerCase();
    return mapping[lower] || name;
  }

  // Map parameter names to Claude's expected format
  mapParameters(toolName, params) {
    const mapped = { ...params };

    // Common mappings
    if (params.filename && !params.file_path) {
      mapped.file_path = params.filename;
      delete mapped.filename;
    }
    if (params.file && !params.file_path) {
      mapped.file_path = params.file;
      delete mapped.file;
    }
    if (params.path && !params.file_path && toolName !== 'Glob' && toolName !== 'Grep') {
      mapped.file_path = params.path;
      delete mapped.path;
    }

    // Edit tool mappings
    if (toolName === 'Edit') {
      if (params.search && !params.old_string) {
        mapped.old_string = params.search;
        delete mapped.search;
      }
      if (params.replace && !params.new_string) {
        mapped.new_string = params.replace;
        delete mapped.replace;
      }
      if (params.find && !params.old_string) {
        mapped.old_string = params.find;
        delete mapped.find;
      }
      if (params.replacement && !params.new_string) {
        mapped.new_string = params.replacement;
        delete mapped.replacement;
      }
    }

    // Bash tool mappings
    if (toolName === 'Bash') {
      if (params.cmd && !params.command) {
        mapped.command = params.cmd;
        delete mapped.cmd;
      }
    }

    return mapped;
  }

  async transformRequestIn(request, provider) {
    try {
      const body = request?.body || request;
      if (!body) {
        return { body: request, config: {} };
      }

      this.log('Processing request for provider:', provider?.name);

      // Handle OpenAI format messages array
      if (body.messages && Array.isArray(body.messages)) {
        const hasSystem = body.messages.some(m => m.role === 'system');

        if (hasSystem) {
          // Prepend to existing system message
          for (let i = 0; i < body.messages.length; i++) {
            const msg = body.messages[i];
            if (msg.role === 'system') {
              if (typeof msg.content === 'string') {
                body.messages[i] = {
                  ...msg,
                  content: this.getToolInstructionPrompt() + '\n\n' + msg.content
                };
              } else if (Array.isArray(msg.content)) {
                body.messages[i].content.unshift({
                  type: 'text',
                  text: this.getToolInstructionPrompt()
                });
              }
              this.log('Prepended tool instruction to system message');
              break;
            }
          }
        } else {
          // Add new system message at the beginning
          body.messages.unshift({
            role: 'system',
            content: this.getToolInstructionPrompt()
          });
          this.log('Added new system message with tool instructions');
        }
      }

      // Handle Anthropic format system array
      if (body.system && Array.isArray(body.system)) {
        body.system.unshift({
          type: 'text',
          text: this.getToolInstructionPrompt()
        });
        this.log('Added tool instruction to Anthropic system array');
      }

      return { body, config: {} };

    } catch (err) {
      this.log('ERROR in transformRequestIn:', err.message);
      return { body: request?.body || request, config: {} };
    }
  }

  async transformResponseOut(response, context) {
    try {
      this.log('Processing response, type:', typeof response);
      this.log('Response constructor:', response?.constructor?.name);

      // If response is a fetch Response object, we need to transform the body
      if (response && typeof response.json === 'function') {
        this.log('Response is a fetch Response object');
        // Clone the response so we can read it
        const cloned = response.clone();
        try {
          const data = await cloned.json();
          this.log('Parsed response data:', JSON.stringify(data).substring(0, 300));

          // Transform the data
          const transformed = await this.transformParsedResponse(data);

          // Return a new Response with transformed data
          return new Response(JSON.stringify(transformed), {
            status: response.status,
            statusText: response.statusText,
            headers: {
              'Content-Type': 'application/json'
            }
          });
        } catch (e) {
          this.log('Failed to parse response as JSON:', e.message);
          return response;
        }
      }

      // Handle already-parsed response objects
      return this.transformParsedResponse(response);
    } catch (err) {
      this.log('ERROR in transformResponseOut:', err.message);
      return response;
    }
  }

  async transformParsedResponse(response) {
    try {
      // Handle OpenAI format (most common for llama.cpp)
      if (response?.choices && Array.isArray(response.choices)) {
        for (let choice of response.choices) {
          if (choice.message?.content) {
            const content = choice.message.content;
            const toolCall = this.parseToolCall(content);

            if (toolCall) {
              this.log('Detected tool call:', toolCall.name);

              const mappedName = this.mapToolName(toolCall.name);
              const mappedParams = this.mapParameters(mappedName, toolCall.input);

              // Keep in OpenAI format with tool_calls - router will convert to Claude
              choice.message.content = null;
              choice.message.tool_calls = [
                {
                  id: this.generateToolId(),
                  type: 'function',
                  function: {
                    name: mappedName,
                    arguments: JSON.stringify(mappedParams)
                  }
                }
              ];
              choice.finish_reason = 'tool_calls';

              this.log('Converted to OpenAI tool_calls format:', JSON.stringify(choice.message.tool_calls[0]));
              return response;
            } else {
              // No tool call detected - clean up thinking patterns
              let text = content;
              text = text.replace(/^\*[^*\n]+\*\s*\n?/gm, '');
              text = text.replace(/\*(?:Hmm|Okay|Let me|thinking)[^*]*\*\s*/gi, '');
              choice.message.content = text.trim();
            }
          }
        }
      }

      // Handle Anthropic format (passthrough with cleanup)
      if (response?.content && Array.isArray(response.content)) {
        for (let i = 0; i < response.content.length; i++) {
          if (response.content[i].type === 'text' && response.content[i].text) {
            let text = response.content[i].text;

            // Check for embedded tool calls
            const toolCall = this.parseToolCall(text);
            if (toolCall) {
              const mappedName = this.mapToolName(toolCall.name);
              const mappedParams = this.mapParameters(mappedName, toolCall.input);

              response.content[i] = {
                type: 'tool_use',
                id: this.generateToolId(),
                name: mappedName,
                input: mappedParams
              };
              response.stop_reason = 'tool_use';
            } else {
              // Clean up thinking patterns
              text = text.replace(/^\*[^*\n]+\*\s*\n?/gm, '');
              text = text.replace(/\*(?:Hmm|Okay|Let me|thinking)[^*]*\*\s*/gi, '');
              response.content[i].text = text.trim();
            }
          }
        }
      }

      return response;
    } catch (err) {
      this.log('ERROR in transformParsedResponse:', err.message);
      return response;
    }
  }
}

module.exports = HermesToolAdapter;
