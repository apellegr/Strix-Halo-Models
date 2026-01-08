/**
 * Hermes Direct Response Transformer
 *
 * Adds a system prompt to Hermes models to prevent internal monologue
 * and ensure direct responses without thinking prefixes like "*Hmm..."
 */

class HermesDirectTransformer {
  name = 'hermes-direct';

  constructor(options = {}) {
    this.options = {
      debug: options.debug || false,
      ...options
    };
  }

  log(...args) {
    if (this.options.debug) {
      console.log(`[hermes-direct] ${args.join(' ')}`);
    }
  }

  // System prompt to prevent thinking out loud
  getDirectResponsePrompt() {
    return `IMPORTANT: Respond directly and concisely. Do NOT include internal monologue, thinking out loud, or text prefixed with asterisks like "*Hmm..." or "*thinking*". Start your response with the actual answer or content immediately.`;
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
        // Check if there's already a system message
        const hasSystem = body.messages.some(m => m.role === 'system');

        if (hasSystem) {
          // Prepend to existing system message
          for (let i = 0; i < body.messages.length; i++) {
            const msg = body.messages[i];
            if (msg.role === 'system') {
              if (typeof msg.content === 'string') {
                body.messages[i] = {
                  ...msg,
                  content: this.getDirectResponsePrompt() + '\n\n' + msg.content
                };
              } else if (Array.isArray(msg.content)) {
                // Handle array content format
                body.messages[i].content.unshift({
                  type: 'text',
                  text: this.getDirectResponsePrompt()
                });
              }
              this.log('Prepended direct response instruction to system message');
              break;
            }
          }
        } else {
          // Add new system message at the beginning
          body.messages.unshift({
            role: 'system',
            content: this.getDirectResponsePrompt()
          });
          this.log('Added new system message with direct response instruction');
        }
      }

      // Handle Anthropic format system array
      if (body.system && Array.isArray(body.system)) {
        body.system.unshift({
          type: 'text',
          text: this.getDirectResponsePrompt()
        });
        this.log('Added direct response instruction to Anthropic system array');
      }

      return { body, config: {} };

    } catch (err) {
      this.log('ERROR:', err.message);
      return { body: request?.body || request, config: {} };
    }
  }

  async transformResponseOut(response, provider) {
    try {
      // Optional: Strip any remaining thinking patterns from response
      if (response?.content) {
        for (let i = 0; i < response.content.length; i++) {
          if (response.content[i].type === 'text' && response.content[i].text) {
            let text = response.content[i].text;
            // Remove lines that start with asterisk thinking patterns
            text = text.replace(/^\*[^*\n]+\*\s*\n?/gm, '');
            // Remove inline thinking patterns
            text = text.replace(/\*(?:Hmm|Okay|Let me|thinking)[^*]*\*\s*/gi, '');
            response.content[i].text = text.trim();
          }
        }
      }

      // Handle OpenAI format
      if (response?.choices) {
        for (let choice of response.choices) {
          if (choice.message?.content) {
            let text = choice.message.content;
            text = text.replace(/^\*[^*\n]+\*\s*\n?/gm, '');
            text = text.replace(/\*(?:Hmm|Okay|Let me|thinking)[^*]*\*\s*/gi, '');
            choice.message.content = text.trim();
          }
        }
      }

      return response;
    } catch (err) {
      this.log('ERROR in transformResponseOut:', err.message);
      return response;
    }
  }
}

module.exports = HermesDirectTransformer;
