# Description
#   MantisBT integration for Hubot
#
# Configuration:
#   HUBOT_MANTIS_BASE_URL - e.g. https://bugs.example.com/
#   HUBOT_MANTIS_CONNECT_URL - URL for mantisconnect.php, default `HUBOT_MANTIS_BASE_URL`api/soap/mantisconnect.php?wsdl
#   HUBOT_MANTIS_USERNAME - Mantis username to use
#   HUBOT_MANTIS_PASSWORD - Mantis password
#   HUBOT_MANTIS_DATE_FORMAT - default YYYY-MM-DD hh:mm:ss
#
# Commands:
#   hubot mantis [<assigned|monitored|reported> ]issues for <user>[, project <project>] - last issues for user and optionally for project
#   hubot mantis my [<assigned|monitored|reported>] issues[ for project <project>] - my last issues
#   hubot mantis set username <username> - set username you have in Mantis (for the `my issues` command)
#   hubot mantis projects - list all projects
#
# Other functionality:
#   Automatic issue preview when pasting a link to the bug tracker or a message in format MT123 or MT 123
#
# License: MIT

soap = require "soap"
moment = require "moment"

unless process.env.HUBOT_MANTIS_BASE_URL and process.env.HUBOT_MANTIS_USERNAME and process.env.HUBOT_MANTIS_PASSWORD
  console.log "Mantis environment variables not set"
  process.exit 1

process.env.HUBOT_MANTIS_CONNECT_URL ?= "#{process.env.HUBOT_MANTIS_BASE_URL}api/soap/mantisconnect.php?wsdl"
username = process.env.HUBOT_MANTIS_USERNAME
password = process.env.HUBOT_MANTIS_PASSWORD
date_format = process.env.HUBOT_MANTIS_DATE_FORMAT ? "YYYY-MM-DD hh:mm:ss"

PROJECTS = {}

client = null

soap.createClient(
  process.env.HUBOT_MANTIS_CONNECT_URL,
  (err, cl) ->
    if err
      console.log "SOAP createClient failed: #{err.response}"
      process.exit 1
    else
      console.log "SOAP client created."
      client = cl

      # Get projects and save them

      client.mc_projects_get_user_accessible(
        {
          username: username
          password: password
        }
        (err, result) ->
          if err
            console.log "Mantis project init error", err.response
          else
            url = "#{process.env.HUBOT_MANTIS_BASE_URL}set_project.php?project_id="

            # API doesn't return project 0 (all projects), it will be useful

            PROJECTS['0'] =
              id: 0
              name: "All projects"
              view_state: "private"
              url: url + 0

            for item in result.return.item
              PROJECTS[item.id.$value] =
                id: item.id.$value
                name: item.name.$value
                view_state: item.view_state.name.$value
                url: url + item.id.$value
      )
)

allIssueTypes = ["assigned", "monitored", "reported"]

# regex escaping

escapeRegExp = (s) ->
  s.replace(/[-\/\\^$*+?.()|[\]{}]/g, '\\$&')

# Helper for getting project IDs by name

getProjectIdsByName = (name, regex = true, stopAfterFirstMatch = false) ->
  projectIDs = []
  for id, project of PROJECTS
    if regex
      match = project.name.match(new RegExp(name, "i"))
      projectIDs.push(project.id) if match
    else
      projectIDs.push(project.id) if project.name == name
    break if stopAfterFirstMatch

  projectIDs

# Helper for getting issues

getIssues = (msg, issuesType = null, targetUser = null, projectId = 0, pageNumber = 1, perPage = 10) ->
  options =
    username: username
    password: password
    project_id: projectId
    page_number: pageNumber
    per_page: perPage

  options.target_user = { name: targetUser } if targetUser?
  options.filter_type = issuesType if issuesType?

  client.mc_project_get_issues_for_user(
    options
    (err, result) ->
      if err
        text = "Error when requesting #{issuesType} issues for user #{targetUser}:\n"
        if err.body.match("User with id")
          text += "User not found. Are you sure your Mantis username `#{targetUser}` is correct?"
          text += "\nIf not, you can set a new one with `#{robot.name} mantis set username your_mantis_username`"
        else
          text += err
          console.log "Mantis issues error", err.response
        msg.reply text
      else
        issues = result.return.item
        unless issues?
          return msg.reply "No #{issuesType} issues found."

        issues = [issues] unless Array.isArray(issues)

        text = "#{targetUser} has #{issues.length} #{issuesType} issues (max #{perPage} shown)\n"

        for item in issues
          issue =
            lastUpdated: moment(item.last_updated.$value).format(date_format)
            summary: item.summary.$value
            projectName: item.project.name.$value
            url: "#{process.env.HUBOT_MANTIS_BASE_URL}view.php?id=#{item.id.$value}"
          text += "\n#{issue.lastUpdated} - #{issue.summary} [#{issue.projectName}] - #{issue.url}"

        msg.reply text
  )

getProjectIdForIssue = (msg, projectName) ->
  projectIds = getProjectIdsByName(projectName, true, false)
  if projectIds.length == 0
    msg.reply "No project found. All projects can be returned with `mantis projects`"
    return false
  else if projectIds.length > 1
    text = "More than 1 projects found. Specify the project in a better way."
    text += "\nIf you want the exact match like project \"ATS\", specify it as ^ATS$"
    text += "\nProjects matching this expression:"
    for id in projectIds
      text += "\n#{PROJECTS[id].name} - #{PROJECTS[id].view_state} - #{PROJECTS[id].url}"
    msg.reply text
    return false
  else
    return projectIds[0]

module.exports = (robot) ->
  # Description of SOAP API endpoints
  # Usage:
  #     mantis describe [<endpoint_regex>]
  #         <endpoint_regex> - optional, returns:
  #                                   - more than 1 endpoint matching: all endpoint keys which match the regex
  #                                   - 1 endpoint: input and output of the endpoint
  #                            without it, returns list of all endpoints

  robot.respond /mantis describe(.*)/i, (msg) ->
    arg = msg.match[1]
    if arg
      arg = arg.trim()
      regex = new RegExp(arg)
      methods = Object.keys(client.describe().MantisConnect.MantisConnectPort)
      methods = methods.filter (method) -> method.match(regex)
      if methods.length > 1
        msg.reply "Available methods: #{methods.join(", ")}"
      else if methods.length == 1
        described = client.describe().MantisConnect.MantisConnectPort[methods[0]]
        described = JSON.stringify(described, null, '\t')
        msg.reply "#{methods[0]}\n```#{described}```"
    else
      msg.reply Object.keys(client.describe().MantisConnect.MantisConnectPort).join(", ")

  # Gets any user's issues
  # Usage:
  #     mantis get <type> issues for user <username>

  robot.respond /(?:mantis)?(?: get)?(?: (assigned|monitored|reported))?(?: (?:issues|bugs|qa)) for (?:user )?([\w ]+)(?:, project (.+))?/i, (msg) ->
    if msg.match[1] in allIssueTypes
      issueTypes = [msg.match[1]]
    else
      issueTypes = allIssueTypes

    user = msg.match[2]
    projectName = msg.match[3]

    if projectName
      projectId = getProjectIdForIssue(msg, projectName)
      return unless projectId
    else
      projectId = 0

    perPage = 10

    for issueType in issueTypes
      getIssues(msg, issueType, user, projectId, 1, perPage)

  # Gets user's own isues

  robot.respond /(?:mantis)?(?: get)? my(?: (assigned|monitored|reported))?(?: (?:issues|bugs|qa))(?: for project (.*))?/i, (msg) ->
    if msg.match[1] in allIssueTypes
      issueTypes = [msg.match[1]]
    else
      issueTypes = allIssueTypes

    user = robot.brain.get "#{robot.name}_mantis_user_#{msg.message.user.id}"
    user = msg.message.user.name unless user

    projectName = msg.match[2]

    if projectName
      projectId = getProjectIdForIssue(msg, projectName)
      return unless projectId
    else
      projectId = 0

    perPage = 10

    for issueType in issueTypes
      getIssues(msg, issueType, user, projectId, 1, perPage)

  # Associates the current account with the Mantis username.

  robot.respond /mantis set username (.*)/i, (msg) ->
    robot.brain.set "#{robot.name}_mantis_user_#{msg.message.user.id}", msg.match[1]
    msg.reply "I set your Mantis name to #{msg.match[1]}. I will remember it even if you change your nick!"

  # Returns projects

  robot.respond /mantis (?:get )?projects/i, (msg) ->
    text = "There are #{Object.keys(PROJECTS).length} projects.\n"
    for id, project of PROJECTS
      text += "\n#{project.name} - #{project.view_state} - #{project.url}"

    msg.reply text

  # Rich formatting for Mantis links
  robot.hear new RegExp("(?:^| )\\MT\\s?(\\d+)(?:$| )|#{escapeRegExp(process.env.HUBOT_MANTIS_BASE_URL + "view.php?id=")}(\\d+)", "mi"), (msg) ->
    msg.match = msg.match.filter Boolean # remove null values
    issueId = msg.match[1]

    priorityToColor =
      none: null
      low: "#7eb7e0"
      normal: "#31a4f7"
      high: "warning"
      urgent: "danger"
      immediate: "danger"

    options =
      username: username
      password: password
      issue_id: issueId

    client.mc_issue_get(
      options
      (err, result) ->
        if err
          return # silently fail

        issue =
          id: msg.match[1]
          summary: result.return.summary.$value
          #description: result.return.description.$value
          project:
            id: result.return.project.id.$value
            name: result.return.project.name.$value
          #category: result.return.category.$value
          #priority: result.return.priority.name.$value
          #severity: result.return.severity.name.$value
          status: result.return.status.name.$value
          #reporter: result.return.reporter.name.$value
          #handler: result.return.handler?.name.$value ? ""
          #date_submitted:  moment(result.return.date_submitted.$value).format(date_format)
          #last_updated: moment(result.return.last_updated.$value).format(date_format)

        attachment =
          fallback: "Issue: #{issue.summary} (project #{issue.projectName}, category #{issue.category}, " +
                    "priority #{issue.priority}, severity #{issue.severity}, " +
                    "last updated #{issue.last_updated})"
          title: issue.summary
          title_link: "#{process.env.HUBOT_MANTIS_BASE_URL}view.php?id=#{issueId}"
          text: issue.description
          author_name: issue.reporter
          color: priorityToColor[issue.priority] ? null
          fields: [
            {}=
              title: "Priority"
              value: issue.priority
              short: true
            {}=
              title: "Severity"
              value: issue.severity
              short: true
            {}=
              title: "Status"
              value: issue.status
              short: true
            {}=
              title: "Assigned to"
              value: issue.handler
              short: true
            {}=
              title: "Project"
              value: "<#{process.env.HUBOT_MANTIS_BASE_URL}set_project.php?project_id=#{issue.project.id}|#{issue.project.name}>"
              short: true
            {}=
              title: "Category"
              value: issue.category
              short: true
            {}=
              title: "Date submitted"
              value: issue.date_submitted
              short: true
            {}=
              title: "Last update"
              value: issue.last_updated
              short: true
          ]
        msg.send "MT#{issueId} - #{issue.project.name} - #{issue.status} - #{issue.summary}"
        if (!msg.match[0].startsWith('http'))
            msg.send attachment.title_link
        #robot.adapter.customMessage
        #  channel: msg.envelope.room
        #  username: msg.robot.name
        #  attachments: [attachment]
    )

