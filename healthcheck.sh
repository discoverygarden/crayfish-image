#!/bin/bash

if curl -s -o /dev/null -w '%{http_code}' -A "healthcheck" localhost/houdini/convert | grep '^400$'; then
  echo Success
  exit 0
else
  echo Failure
  exit 1
fi

