#!/bin/bash

if curl -s -o /dev/null -w '%{http_code}' -A "healthcheck" localhost/healthz | grep '^200$'; then
  echo Success
  exit 0
else
  echo Failure
  exit 1
fi

