const http = require('http');
const https = require('https');

const PORT = 3457;
const LOCAL_LLM_URL = 'http://localhost:8003/v1/chat/completions';
const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
const ANTHROPIC_API_KEY = process.env.ANTHROPIC_API_KEY;

function makeRequest(url, options, body) {
  return new Promise((resolve, reject) => {
    const isHttps = url.startsWith('https');
    const lib = isHttps ? https : http;
    const urlObj = new URL(url);
    
    const reqOptions = {
      hostname: urlObj.hostname,
      port: urlObj.port || (isHttps ? 443 : 80),
      path: urlObj.pathname,
      method: 'POST',
      headers: options.headers
    };

    const req = lib.request(reqOptions, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        resolve({ status: res.statusCode, headers: res.headers, body: data });
      });
    });
    
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

function convertToOpenAI(anthropicBody) {
  const parsed = JSON.parse(anthropicBody);
  return JSON.stringify({
    model: parsed.model || 'llama-4-scout',
    messages: parsed.messages,
    max_tokens: parsed.max_tokens || 1024,
    stream: false
  });
}

const server = http.createServer(async (req, res) => {
  if (req.method !== 'POST') {
    res.writeHead(200, {'Content-Type': 'application/json'});
    res.end(JSON.stringify({message: 'Compare Proxy - POST to /v1/messages'}));
    return;
  }

  let body = '';
  req.on('data', chunk => body += chunk);
  req.on('end', async () => {
    console.log('\n' + '='.repeat(80));
    console.log('INCOMING REQUEST:');
    console.log('Headers:', JSON.stringify(req.headers, null, 2));
    console.log('Body:', body);
    
    try {
      // Request to Local LLM (OpenAI format)
      console.log('\n--- Sending to LOCAL LLM (port 8003) ---');
      const openaiBody = convertToOpenAI(body);
      console.log('Converted body:', openaiBody);
      
      const localStart = Date.now();
      const localResponse = await makeRequest(LOCAL_LLM_URL, {
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer not-needed'
        }
      }, openaiBody);
      const localTime = Date.now() - localStart;
      
      console.log('\nLOCAL LLM Response (' + localTime + 'ms):');
      console.log('Status:', localResponse.status);
      console.log('Body:', localResponse.body.substring(0, 500));

      // Request to Anthropic
      if (ANTHROPIC_API_KEY) {
        console.log('\n--- Sending to ANTHROPIC ---');
        const anthropicStart = Date.now();
        const anthropicResponse = await makeRequest(ANTHROPIC_URL, {
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': ANTHROPIC_API_KEY,
            'anthropic-version': '2023-06-01'
          }
        }, body);
        const anthropicTime = Date.now() - anthropicStart;
        
        console.log('\nANTHROPIC Response (' + anthropicTime + 'ms):');
        console.log('Status:', anthropicResponse.status);
        console.log('Body:', anthropicResponse.body.substring(0, 500));
      } else {
        console.log('\n--- ANTHROPIC_API_KEY not set, skipping ---');
      }

      // Return local response (converted to Anthropic format)
      const localParsed = JSON.parse(localResponse.body);
      const anthropicFormat = {
        id: 'msg_compare_' + Date.now(),
        type: 'message',
        role: 'assistant',
        model: localParsed.model || 'local-llm',
        content: [{
          type: 'text',
          text: localParsed.choices?.[0]?.message?.content || 'No response'
        }],
        stop_reason: 'end_turn',
        usage: {
          input_tokens: localParsed.usage?.prompt_tokens || 0,
          output_tokens: localParsed.usage?.completion_tokens || 0
        }
      };

      res.writeHead(200, {'Content-Type': 'application/json'});
      res.end(JSON.stringify(anthropicFormat));
      
    } catch (err) {
      console.error('ERROR:', err.message);
      res.writeHead(500, {'Content-Type': 'application/json'});
      res.end(JSON.stringify({error: err.message}));
    }
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log('Compare Proxy listening on port ' + PORT);
  console.log('Local LLM:', LOCAL_LLM_URL);
  console.log('Anthropic:', ANTHROPIC_URL);
  console.log('API Key set:', !!ANTHROPIC_API_KEY);
});
