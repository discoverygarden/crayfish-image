#!/bin/bash

if curl -s -o /dev/null -w '%{http_code}' localhost/houdini/convert | grep '^401$'; then
  echo Failed to authenicate successfully
  exit 0
else
  echo Failed uncessuflly
  exit 1
fi

