const https = require('https');

const proxyOptions = {
  hostname: 'localhost',
  port: 9002,
  path: 'statsig.anthropic.com:443',
  method: 'CONNECT',
};

console.log('Creating CONNECT request to proxy...');
const req = https.request(proxyOptions);

req.on('connect', (res, socket, head) => {
  console.log('CONNECT tunnel established!', res.statusCode);
  
  // Make the actual HTTPS request through the tunnel
  const options = {
    socket: socket,
    agent: false,
    hostname: 'statsig.anthropic.com',
    port: 443,
    path: '/',
    method: 'GET'
  };
  
  const apiReq = https.request(options, (apiRes) => {
    console.log('API Response Status:', apiRes.statusCode);
    apiRes.on('data', (chunk) => {
      console.log('Data:', chunk.toString());
    });
  });
  
  apiReq.on('error', (err) => {
    console.error('API request error:', err);
  });
  
  apiReq.end();
});

req.on('error', (err) => {
  console.error('Proxy connection error:', err);
});

req.end();