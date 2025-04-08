#!/bin/bash

rm nginx -rf
git clone https://github.com/nuniesmith/nginx.git
cd nginx
./start.sh
