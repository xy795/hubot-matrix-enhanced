# About

Initial idea from [davidar](https://github.com/davidar).

Simple Hubot adapter for [matrix](https://matrix.org) written in coffeeScript.

# Configuration

All parameters can be specified by environment variables or in a config file (config/default.json).

ENV | json key | Default | Description
--- | --- | --- | ---
HUBOT_MATRIX_HOST | matrix.host | https://matrix.org | the host of the matrix server to connect to
HUBOT_MATRIX_USER | matrix.user | \<Bot name\> | the hubot user for connecting to matrix
HUBOT_MATRIX_ACCESS_TOKEN | matrix.access_token |   | access token for token authentication
HUBOT_MATRIX_PASSWORD | matrix.password |   | password for password authentication
