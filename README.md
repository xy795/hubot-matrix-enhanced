# About

Initial idea from [davidar](https://github.com/davidar).

Simple Hubot adapter for [matrix](https://matrix.org) written in coffeeScript.

# Configuration

All parameters can be specified by environment variables or in a config file (config/default.json).

ENV | json key | Default | Description
--- | --- | --- | ---
HUBOT_MATRIX_HOST_SERVER | matrix_host_server | https://matrix.org | Address to the matrix host
HUBOT_MATRIX_USER | matrix_user | \<Bot name\> | Username of the bot
HUBOT_ACCESS_TOKEN | matrix_access_token |   | Access token for token authentication
HUBOT_MATRIX_PASSWORD | matrix_password |   | Password for password authentication
