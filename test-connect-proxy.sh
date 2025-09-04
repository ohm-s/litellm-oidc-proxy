#!/bin/bash

# Test CONNECT proxy functionality
echo "Testing CONNECT proxy on port 9002..."
echo "Note: Make sure to start the Anthropic proxy server from the menu bar app!"
echo ""

# Test 1: Test basic CONNECT request
echo -e "\n=== Test 1: Basic CONNECT request ==="
(echo -ne "CONNECT statsig.anthropic.com:443 HTTP/1.1\r\nHost: statsig.anthropic.com:443\r\n\r\n"; sleep 1) | nc localhost 9002

# Test 2: Test with curl using proxy
echo -e "\n\n=== Test 2: HTTPS request through proxy with curl ==="
curl -v -x http://localhost:9002 https://httpbin.org/ip 2>&1 | grep -E "(Connected to proxy|HTTP/1.1 200|Proxy-Connection|origin)"

# Test 3: Test CONNECT with telnet-like approach
echo -e "\n\n=== Test 3: Raw CONNECT test ==="
(
  echo "CONNECT httpbin.org:443 HTTP/1.1"
  echo "Host: httpbin.org:443"
  echo "Proxy-Connection: Keep-Alive"
  echo ""
  sleep 1
) | nc -v localhost 9002 2>&1 | head -20

echo -e "\n\nDone."