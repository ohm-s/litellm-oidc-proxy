#!/bin/bash

echo "Testing simple CONNECT request..."
echo -e "CONNECT httpbin.org:443 HTTP/1.1\r\nHost: httpbin.org:443\r\n\r\n" | nc -v localhost 9002