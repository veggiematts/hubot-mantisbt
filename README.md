# hubot-mantisbt [![npm version](https://badge.fury.io/js/hubot-mantisbt.svg)](http://badge.fury.io/js/hubot-mantisbt)

Mantis integration for Hubot

See [`src/mantisbt.coffee`](src/mantisbt.coffee) for full documentation.

## Installation

In hubot project repo, run:

`npm install hubot-mantisbt --save`

Then add **hubot-mantisbt** to your `external-scripts.json`:

```json
[
  "hubot-mantisbt"
]
```

## Configuration

* `HUBOT_MANTIS_BASE_URL` - e.g. https://bugs.example.com
* `HUBOT_MANTIS_CONNECT_URL` - URL for mantisconnect.php, default `HUBOT_MANTIS_BASE_URL`api/soap/mantisconnect.php?wsdl
* `HUBOT_MANTIS_USERNAME`
* `HUBOT_MANTIS_PASSWORD`
* `HUBOT_MANTIS_DATE_FORMAT` - default YYYY-MM-DD hh:mm:ss

## Commands

* `hubot [mantis ][<assigned|monitored|reported> ]issues for <user>[, project <project>]` - last issues for user and optionally for project
* `hubot [mantis ]my [<assigned|monitored|reported>] issues[ for project <project>]` - my last issues
* `hubot mantis set username <username>` - set username you have in Mantis (for the `my issues` command)
* `hubot mantis projects` - list all projects

## NPM Module

https://www.npmjs.com/package/hubot-mantisbt

