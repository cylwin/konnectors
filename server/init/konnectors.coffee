path = require 'path'
fs = require 'fs'
async = require 'async'
log = require('printit')
    prefix: null
    date: true

Konnector = require '../models/konnector'
konnectorModules = require '../lib/konnector_hash'

module.exports = (done) ->
    Konnector.all (err, konnectors) ->
        if err
            log.error err
            callback err
        else
            konnectorHash = {}
            async.eachSeries konnectors, (konnector, callback) ->
                konnectorHash[konnector.slug] = konnector
                konnectorResetValue konnector, callback
            , (err) ->
                if err
                    log.error err
                konnectorsToCreate = getKonnectorsToCreate konnectorHash
                console.log "konnectors existing : #{Object.keys(konnectorHash).length}"
                console.log "konnectors to create : #{konnectorsToCreate.length}"
                return done() if konnectorsToCreate.length is 0
                createKonnectors konnectorsToCreate, done

konnectorResetValue = (konnector, callback) ->

    # Reset isImporting state to false if value is true
    # This happens when the app is crashing while importing
    if konnector.isImporting is true
        konnector.isImporting = false
        konnector.save (err) ->
            if err
                log.debug "#{konnector.slug} | #{err}"
            else
                log.debug "#{konnector.slug}: reseting isImporting"
            callback()
    else
        callback()


getKonnectorsToCreate = (konnectorHash) ->

    konnectorsToCreate = []

    for name, konnectorModule of konnectorModules
        unless konnectorHash[konnectorModule.slug]?
            konnectorsToCreate.push konnectorModule
    return konnectorsToCreate

createKonnectors = (konnectorsToCreate, done) ->

    #console.log konnectorHash
    async.eachSeries konnectorsToCreate, (konnector, callback) ->

        initializeKonnector konnector, callback

    , (err) ->
        log.info 'All konnectors created'
        done()

initializeKonnector = (konnector, callback) ->
    console.log "name : #{konnector.slug}"

    konnector.init (err) ->
        if err
            console.log "#{konnector.slug} : err"
            log.error err
            callback err
        else
            console.log "create : #{konnector.slug}"
            Konnector.create konnector, (err) ->
                log.error err if err
                callback err


