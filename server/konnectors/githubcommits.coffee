americano = require 'americano-cozy'
requestJson = require 'request-json'
request = require 'request'
moment = require 'moment'
cheerio = require 'cheerio'
fs = require 'fs'
async = require 'async'

fetcher = require '../lib/fetcher'

log = require('printit')
    prefix: "Github"
    date: true


# Models

Commit = americano.getModel 'Commit',
    date: Date
    sha: String
    parent: String
    tree: String
    url: String
    author: String
    email: String
    message: String
    additions: Number
    deletions: Number
    files: (x) -> x
    vendor: {type: String, default: 'Github'}

Commit.all = (params, callback) ->
    Commit.request 'byDate', params, callback


# Konnector

module.exports =

    name: "Github Commits"
    slug: "githubcommits"
    description: "Save infos from all your Github Commits."
    vendorLink: "https://www.github.com/"

    fields:
        login: "text"
        password: "password"
    models:
        commit: Commit

    # Define model requests.
    init: (callback) ->
        map = (doc) -> emit doc.date, doc
        Commit.defineRequest 'byDate', map, (err) ->
            callback err

    fetch: (requiredFields, callback) ->
        log.info "Import started"

        fetcher.new()
            .use(getEvents)
            .use(buildCommitDateHash)
            .use(logCommits)
            .args(requiredFields, {}, {})
            .fetch ->
                log.info "Github commits imported"
                callback()


# Get latest events list to know wich commits were pushed.
getEvents = (requiredFields, commits, data, next) ->
    client = requestJson.newClient 'https://api.github.com'
    username = requiredFields.login
    pass = requiredFields.password

    client.setBasicAuth username, pass

    path = "users/#{username}/events/public?page="

    data.commits = []
    log.info "Fetch commits sha from events..."
    async.eachSeries [1..10], (page, callback) ->
        log.info "Fetch events page #{page}..."
        client.get path + page, (err, res, events) ->
            unless err?
                for event in events
                    if event.type is 'PushEvent'
                        for commit in event.payload.commits
                            data.commits.push commit
            else
                log.error err
            callback()
    , (err) ->
        log.info "All events data fetched."
        next()


# Build hash listing all already downloaded commits.
buildCommitDateHash = (requiredFields, entries, data, next) ->
    entries.commitHash = {}
    Commit.all limit: 1000, (err, commits) ->
        if err
            log.error err
            next err
        else
            for commit in commits
                entries.commitHash[commit.sha] = true
            next()


# Retrieve and save non existing commits one by one.
logCommits = (requiredFields, entries, data, next) ->
    client = requestJson.newClient 'https://api.github.com'
    username = requiredFields.login
    pass = requiredFields.password

    client.setBasicAuth username, pass
    async.eachSeries data.commits, (commit, callback) ->
        path = commit.url.substring 'https://api.github.com/'.length
        if entries.commitHash[commit.sha]
            log.info "Commit #{commit.sha} not saved: already exists."
            callback()
        else
            client.get path, (err, res, commit) ->
                log.info "Saving commit #{commit.sha}..."
                if err
                    log.error err
                    callback()
                else if not commit? or not commit.commit? or not commit.author?
                    log.info "Commit #{commit.sha} not saved: no metadata."
                    callback()
                else if commit.author.login isnt username
                    log.info "Commit #{commit.sha} not saved: " + \
                             "user is not author (#{commit.author.login})."
                    callback()
                else
                    data =
                        date: commit.commit.author.date
                        sha: commit.sha
                        parent: commit.parents[0].sha
                        url: commit.url
                        author: commit.commit.author.name
                        email: commit.commit.author.email
                        message: commit.commit.message
                        tree: commit.commit.tree.sha
                        additions: commit.stats.additions
                        deletions: commit.stats.deletions
                        files: commit.files
                    Commit.create data, (err) ->
                        if err
                            log.error err
                        else
                            log.info "Commit #{commit.sha} saved."
                        callback()
    , (err) ->
        next()